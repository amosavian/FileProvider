//
//  SessionDelegate.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/// Allows to get progress or cancel an in-progress operation, for remote, `URLSession` based providers.
/// This class keeps strong reference to tasks.
open class RemoteOperationHandle: OperationHandle {
    
    internal var tasks: [URLSessionTask]
    
    open private(set) var operationType: FileOperationType
    
    init(operationType: FileOperationType, tasks: [URLSessionTask]) {
        self.operationType = operationType
        self.tasks = tasks
    }
    
    internal func add(task: URLSessionTask) {
        tasks.append(task)
    }
    
    internal func reape() {
        self.tasks = tasks.filter { $0.state != .completed }
    }
    
    open var bytesSoFar: Int64 {
        return tasks.reduce(0) {
            switch $1 {
            case let task as URLSessionUploadTask:
                return $0 + task.countOfBytesSent
            case let task as FileProviderStreamTask:
                return $0 + task.countOfBytesSent + task.countOfBytesReceived
            default:
                return $0 + $1.countOfBytesReceived
            }
        }
    }
    
    open var totalBytes: Int64 {
        return tasks.reduce(0) {
            switch $1 {
            case let task as URLSessionUploadTask:
                return $0 + task.countOfBytesExpectedToSend
            case let task as FileProviderStreamTask:
                return $0 + task.countOfBytesExpectedToSend + task.countOfBytesExpectedToReceive
            default:
                return $0 + $1.countOfBytesExpectedToReceive
            }
        }
    }
    
    open func cancel() -> Bool {
        var canceled = false
        for taskbox in tasks {
            taskbox.cancel()
            canceled = true
        }
        return canceled
    }
    
    open var inProgress: Bool {
        return tasks.reduce(false) { $0 || $1.state == .running }
    }
}

/// A protocol defines properties for errors returned by HTTP/S based providers.
/// Including Dropbox, OneDrive and WebDAV.
public protocol FileProviderHTTPError: Error, CustomStringConvertible {
    /// HTTP status code returned for error by server.
    var code: FileProviderHTTPErrorCode { get }
    /// Path of file/folder casued that error
    var path: String { get }
    /// Contents returned by server as error description
    var errorDescription: String? { get }
}

extension FileProviderHTTPError {
    public var description: String {
        return code.description
    }
    
    public var localizedDescription: String {
        return description
    }
}

internal var completionHandlersForTasks = [Int: SimpleCompletionHandler]()
internal var downloadCompletionHandlersForTasks = [Int: (URL) -> Void]()
internal var dataCompletionHandlersForTasks = [Int: (Data) -> Void]()

class SessionDelegate: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionStreamDelegate {
    
    weak var fileProvider: (FileProviderBasicRemote & FileProviderOperations)?
    var credential: URLCredential?
    
    var finishDownloadHandler: ((_ session: URLSession, _ downloadTask: URLSessionDownloadTask, _ didFinishDownloadingToURL: URL) -> Void)?
    var didSendDataHandler: ((_ session: URLSession, _ task: URLSessionTask, _ bytesSent: Int64, _ totalBytesSent: Int64, _ totalBytesExpectedToSend: Int64) -> Void)?
    var didReceivedData: ((_ session: URLSession, _ downloadTask: URLSessionDownloadTask, _ bytesWritten: Int64, _ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?
    var didBecomeStream :((_ session: URLSession, _ taskId: Int, _ didBecome: InputStream, _ outputStream: OutputStream) -> Void)?
    
    init(fileProvider: FileProviderBasicRemote & FileProviderOperations, credential: URLCredential?) {
        self.fileProvider = fileProvider
        self.credential = credential
    }
    
    // codebeat:disable[ARITY]
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            let completionHandler = completionHandlersForTasks[task.taskIdentifier] ?? nil
            completionHandler?(error)
            completionHandlersForTasks.removeValue(forKey: task.taskIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let completionHandler = dataCompletionHandlersForTasks[dataTask.taskIdentifier] ?? nil
        completionHandler?(data)
        completionHandlersForTasks.removeValue(forKey: dataTask.taskIdentifier)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.finishDownloadHandler?(session, downloadTask, location)
        
        let dcompletionHandler = downloadCompletionHandlersForTasks[downloadTask.taskIdentifier]
        dcompletionHandler?(location)
        completionHandlersForTasks.removeValue(forKey: downloadTask.taskIdentifier)
        
        guard let json = downloadTask.taskDescription?.deserializeJSON(),
            let op = FileOperationType(json: json), let fileProvider = fileProvider else {
                return
        }
        
        DispatchQueue.main.async {
            fileProvider.delegate?.fileproviderSucceed(fileProvider, operation: op)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.didSendDataHandler?(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
        
        guard let json = task.taskDescription?.deserializeJSON(),
              let op = FileOperationType(json: json), let fileProvider = fileProvider else {
            return
        }
        
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        
        DispatchQueue.main.async {
            fileProvider.delegate?.fileproviderProgress(fileProvider, operation: op, progress: progress)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.didReceivedData?(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
        
        guard let json = downloadTask.taskDescription?.deserializeJSON(),
              let op = FileOperationType(json: json), let fileProvider = fileProvider else {
            return
        }
        
        DispatchQueue.main.async {
            fileProvider.delegate?.fileproviderProgress(fileProvider, operation: op, progress: Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(didReceive: challenge, completionHandler: completionHandler)
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(didReceive: challenge, completionHandler: completionHandler)
    }
    
    func authenticate(didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch (challenge.previousFailureCount, credential != nil) {
        case (0...1, true):
            completionHandler(.useCredential, credential)
        case (0, false):
            completionHandler(.useCredential, challenge.proposedCredential)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    @available(iOS 9.0, macOS 10.11, *)
    func urlSession(_ session: URLSession, streamTask: URLSessionStreamTask, didBecome inputStream: InputStream, outputStream: OutputStream) {
        self.didBecomeStream?(session, streamTask.taskIdentifier, inputStream, outputStream)
    }
}

/// HTTP status codes as an enum.
public enum FileProviderHTTPErrorCode: Int, CustomStringConvertible {
    /// `Continue` informational status with HTTP code 100
    case `continue` = 100
    /// `Switching Protocols` informational status with HTTP code 101
    case switchingProtocols = 101
    /// `Processing` informational status with HTTP code 102
    case processing = 102
    /// `OK` success status with HTTP code 200
    case ok = 200
    /// `Created` success status with HTTP code 201
    case created = 201
    /// `Accepted` success status with HTTP code 202
    case accepted = 202
    /// `Non Authoritative Information` success status with HTTP code 203
    case nonAuthoritativeInformation = 203
    /// `No Content` success status with HTTP code 204
    case noContent = 204
    /// `ResetcContent` success status with HTTP code 205
    case resetContent = 205
    /// `Partial Content` success status with HTTP code 206
    case partialContent = 206
    /// `Multi Status` success status with HTTP code 207
    case multiStatus = 207
    /// `Already Reported` success status with HTTP code 208
    case alreadyReported = 208
    /// `IM Used` success status with HTTP code 226
    case imUsed = 226
    /// `Multiple Choices` redirection status with HTTP code 300
    case multipleChoices = 300
    /// `Moved Permanently` redirection status with HTTP code 301
    case movedPermanently = 301
    /// `Found` redirection status with HTTP code 302
    case found = 302
    /// `See Other` redirection status with HTTP code 303
    case seeOther = 303
    /// `Not Modified` redirection status with HTTP code 304
    case notModified = 304
    /// `Use Proxy` redirection status with HTTP code 305
    case useProxy = 305
    /// `Switch Proxy` redirection status with HTTP code 306
    case switchProxy = 306
    /// `Temporary Redirect` redirection status with HTTP code 307
    case temporaryRedirect = 307
    /// `Permanent Redirect` redirection status with HTTP code 308
    case permanentRedirect = 308
    /// `Bad Request` client error status with HTTP code 400
    case badRequest = 400
    /// `Unauthorized` client error status with HTTP code 401
    case unauthorized = 401
    /// `Payment Required` client error status with HTTP code 402
    case paymentRequired = 402
    /// `Forbidden` client error status with HTTP code 403
    case forbidden = 403
    /// `Not Found` client error status with HTTP code 404
    case notFound = 404
    /// `Method Not Allowed` client error status with HTTP code 405
    case methodNotAllowed = 405
    /// `Not Acceptable` client error status with HTTP code 406
    case notAcceptable = 406
    /// `Proxy Authentication Required` client error status with HTTP code 407
    case proxyAuthenticationRequired = 407
    /// `Request Timeout` client error status with HTTP code 408
    case requestTimeout = 408
    /// `Conflict` client error status with HTTP code 409
    case conflict = 409
    /// `Gone` client error status with HTTP code 410
    case gone = 410
    /// `Length Required` client error status with HTTP code 411
    case lengthRequired = 411
    /// `Precondition Failed` client error status with HTTP code 412
    case preconditionFailed = 412
    /// `Payload Too Large` client error status with HTTP code 413
    case payloadTooLarge = 413
    /// `URI Too Long` client error status with HTTP code 414
    case uriTooLong = 414
    /// `Unsupported Media Type` status with HTTP code 415
    case unsupportedMediaType = 415
    /// `Range Not Satisfiable` client error status with HTTP code 416
    case rangeNotSatisfiable = 416
    /// `Expectation Failed` client error status with HTTP code 417
    case expectationFailed = 417
    /// `Misdirected Request` client error status with HTTP code 421
    case misdirectedRequest = 421
    /// `Unprocessable Entity` client error status with HTTP code 422
    case unprocessableEntity = 422
    /// `Locked` client error status with HTTP code 423
    case locked = 423
    /// `Failed Dependency` client error status with HTTP code 424
    case failedDependency = 424
    /// `Unordered Collection` client error status with HTTP code 425
    case unorderedCollection = 425
    /// `Upgrade Required` client error status with HTTP code 426
    case upgradeRequired = 426
    /// `Precondition Required` client error status with HTTP code 428
    case preconditionRequired = 428
    /// `Too Many Requests` client error status with HTTP code 429
    case tooManyRequests = 429
    /// `Request Header Fields Too Large` client error status with HTTP code 431
    case requestHeaderFieldsTooLarge = 431
    /// `Unavailable For Legal Reasons` client error status with HTTP code 451
    case unavailableForLegalReasons = 451
    /// `Internal Server Error` server error status with HTTP code 500
    case internalServerError = 500
    /// `Bad Gateway` server error status with HTTP code 502
    case badGateway = 502
    /// `Service Unavailable` server error status with HTTP code 503
    case serviceUnavailable = 503
    /// `Gateway Timeout` server error status with HTTP code 504
    case gatewayTimeout = 504
    /// `HTTP Version Not Supported` server error status with HTTP code 505
    case httpVersionNotSupported = 505
    /// `Variant Also Negotiates` server error status with HTTP code 506
    case variantAlsoNegotiates = 506
    /// `Insufficient Storage` server error status with HTTP code 507
    case insufficientStorage = 507
    /// `Loop Detected` server error status with HTTP code 508
    case loopDetected = 508
    /// `Bandwidth Limit Exceeded` server error status with HTTP code 509
    case bandwidthLimitExceeded = 509
    /// `Not Extended` server error status with HTTP code 510
    case notExtended = 510
    /// `Network Authentication Required` server error status with HTTP code 511
    case networkAuthenticationRequired = 511
    
    fileprivate static let status1xx: [Int: String] = [100: "Continue", 101: "Switching Protocols", 102: "Processing"]
    fileprivate static let status2xx: [Int: String] = [200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used"]
    fileprivate static let status3xx: [Int: String] = [300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 305: "Use Proxy", 306: "Switch Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect"]
    fileprivate static let status4xx: [Int: String] = [400: "Bad Request", 401: "Unauthorized/Expired Session", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Payload Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 421: "Misdirected Request", 422: "Unprocessable Entity", 423: "Locked", 424: "Failed Dependency", 425: "Unordered Collection", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons"]
    fileprivate static let status5xx: [Int: String] = [500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected", 509: "Bandwidth Limit Exceeded", 510: "Not Extended", 511: "Network Authentication Required"]
    
    public var description: String {
        switch self.rawValue {
        case 100...102: return FileProviderHTTPErrorCode.status1xx[self.rawValue]!
        case 200...208, 226: return FileProviderHTTPErrorCode.status2xx[self.rawValue]!
        case 300...308: return FileProviderHTTPErrorCode.status3xx[self.rawValue]!
        case 400...417, 421...426: fallthrough
        case 428, 429, 431, 451: return FileProviderHTTPErrorCode.status4xx[self.rawValue]!
        case 500...511: return FileProviderHTTPErrorCode.status5xx[self.rawValue]!
        default: return typeDescription
        }
    }
    
    /// Description of status based on first digit which indicated fail or success.
    public var typeDescription: String {
        switch self.rawValue {
        case 100...199: return "Informational"
        case 200...299: return "Success"
        case 300...399: return "Redirection"
        case 400...499: return "Client Error"
        case 500...599: return "Server Error"
        default: return "Unknown Error"
        }
    }
}
