//
//  SessionDelegate.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/// A protocol defines properties for errors returned by HTTP/S based providers.
/// Including Dropbox, OneDrive and WebDAV.
public protocol FileProviderHTTPError: LocalizedError, CustomStringConvertible {
    /// HTTP status codes as an enum.
    typealias Code = FileProviderHTTPErrorCode
    /// HTTP status code returned for error by server.
    var code: FileProviderHTTPErrorCode { get }
    /// Path of file/folder casued that error
    var path: String { get }
    /// Contents returned by server as error description
    var serverDescription: String? { get }
}

extension FileProviderHTTPError {
    public var description: String {
        return "Status \(code.rawValue): \(code.description)"
    }
    
    public var errorDescription: String? {
        return "Status \(code.rawValue): \(code.description)"
    }
}

internal var completionHandlersForTasks = [String: [Int: SimpleCompletionHandler]]()
internal var downloadCompletionHandlersForTasks = [String: [Int: (URL) -> Void]]()
internal var dataCompletionHandlersForTasks = [String: [Int: (Data) -> Void]]()
internal var responseCompletionHandlersForTasks = [String: [Int: (URLResponse) -> Void]]()

internal func initEmptySessionHandler(_ uuid: String) {
    completionHandlersForTasks[uuid] = [:]
    downloadCompletionHandlersForTasks[uuid] = [:]
    dataCompletionHandlersForTasks[uuid] = [:]
    responseCompletionHandlersForTasks[uuid] = [:]
}

internal func removeSessionHandler(for uuid: String) {
    _ = completionHandlersForTasks.removeValue(forKey: uuid)
    _ = downloadCompletionHandlersForTasks.removeValue(forKey: uuid)
    _ = dataCompletionHandlersForTasks.removeValue(forKey: uuid)
    _ = responseCompletionHandlersForTasks.removeValue(forKey: uuid)
}

/// All objects set to `FileProviderRemote.session` must be an instance of this class
final public class SessionDelegate: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionStreamDelegate {
    
    weak var fileProvider: (FileProviderBasicRemote & FileProviderOperations)?
    var credential: URLCredential?
    
    public init(fileProvider: FileProviderBasicRemote & FileProviderOperations) {
        self.fileProvider = fileProvider
        self.credential = fileProvider.credential
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let progress = context?.load(as: Progress.self), let newVal = change?[.newKey] as? Int64 {
            switch keyPath ?? "" {
            case #keyPath(URLSessionTask.countOfBytesReceived):
                progress.completedUnitCount = newVal
                if let startTime = progress.userInfo[ProgressUserInfoKey.startingTimeKey] as? Date, let task = object as? URLSessionTask {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let throughput = Double(newVal) / elapsed
                    progress.setUserInfoObject(NSNumber(value: throughput), forKey: .throughputKey)
                    if task.countOfBytesExpectedToReceive > 0 {
                        let remain = task.countOfBytesExpectedToReceive - task.countOfBytesReceived
                        let estimatedTimeRemaining = Double(remain) / elapsed
                        progress.setUserInfoObject(NSNumber(value: estimatedTimeRemaining), forKey: .estimatedTimeRemainingKey)
                    }
                }
            case #keyPath(URLSessionTask.countOfBytesSent):
                if let startTime = progress.userInfo[ProgressUserInfoKey.startingTimeKey] as? Date, let task = object as? URLSessionTask {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let throughput = Double(newVal) / elapsed
                    progress.setUserInfoObject(NSNumber(value: throughput), forKey: .throughputKey)
                    
                    // wokaround for multipart uploading
                    let json = task.taskDescription?.deserializeJSON()
                    let uploadedBytes = ((json?["uploadedBytes"] as? Int64) ?? 0) + newVal
                    let totalBytes = (json?["totalBytes"] as? Int64) ?? task.countOfBytesExpectedToSend
                    progress.completedUnitCount = uploadedBytes
                    if totalBytes > 0 {
                        let remain = totalBytes - uploadedBytes
                        let estimatedTimeRemaining = Double(remain) / elapsed
                        progress.setUserInfoObject(NSNumber(value: estimatedTimeRemaining), forKey: .estimatedTimeRemainingKey)
                    }
                } else {
                    progress.completedUnitCount = newVal
                }
            case #keyPath(URLSessionTask.countOfBytesExpectedToReceive), #keyPath(URLSessionTask.countOfBytesExpectedToSend):
                progress.totalUnitCount = newVal
            default:
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }
    }
    
    // codebeat:disable[ARITY]
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task is URLSessionUploadTask {
            task.removeObserver(self, forKeyPath: #keyPath(URLSessionTask.countOfBytesSent))
            //task.removeObserver(self, forKeyPath: #keyPath(URLSessionTask.countOfBytesExpectedToSend))
        } else if task is URLSessionDownloadTask {
            task.removeObserver(self, forKeyPath: #keyPath(URLSessionTask.countOfBytesReceived))
            task.removeObserver(self, forKeyPath: #keyPath(URLSessionTask.countOfBytesExpectedToReceive))
        }
        
        _ = dataCompletionHandlersForTasks[session.sessionDescription!]?.removeValue(forKey: task.taskIdentifier)
        if !(error == nil && task is URLSessionDownloadTask) {
            let completionHandler = completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] ?? nil
            completionHandler?(error)
            _ = completionHandlersForTasks[session.sessionDescription!]?.removeValue(forKey: task.taskIdentifier)
        }
        
        guard let json = task.taskDescription?.deserializeJSON(),
            let op = FileOperationType(json: json), let fileProvider = fileProvider else {
                return
        }
        
        switch op {
        case .fetch:
            if task is URLSessionDataTask {
                task.removeObserver(self, forKeyPath: #keyPath(URLSessionTask.countOfBytesReceived))
                task.removeObserver(self, forKeyPath: #keyPath(URLSessionTask.countOfBytesExpectedToReceive))
            }
        default:
            break
        }
        
        if !(task is URLSessionDownloadTask), case FileOperationType.fetch = op {
            return
        }
        if #available(iOS 9.0, macOS 10.11, *) {
            if task is URLSessionStreamTask {
                return
            }
        }
        
        fileProvider.delegateNotify(op, error: error)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let dcompletionHandler = downloadCompletionHandlersForTasks[session.sessionDescription!]?[downloadTask.taskIdentifier]
        dcompletionHandler?(location)
        _ = downloadCompletionHandlersForTasks[session.sessionDescription!]?.removeValue(forKey: downloadTask.taskIdentifier)
        _ = completionHandlersForTasks[session.sessionDescription!]?.removeValue(forKey: downloadTask.taskIdentifier)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let handler = responseCompletionHandlersForTasks[session.sessionDescription!]?[dataTask.taskIdentifier] ?? nil
        handler?(response)
        completionHandler(.allow)
        _ = responseCompletionHandlersForTasks[session.sessionDescription!]?.removeValue(forKey: dataTask.taskIdentifier)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let completionHandler = dataCompletionHandlersForTasks[session.sessionDescription!]?[dataTask.taskIdentifier] {
            /*if let json = dataTask.taskDescription?.deserializeJSON(),
               let op = FileOperationType(json: json), let fileProvider = fileProvider {
                fileProvider.delegateNotify(op, progress: Double(dataTask.countOfBytesReceived) / Double(dataTask.countOfBytesExpectedToReceive))
            }*/
            completionHandler(data)
        }
        
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let json = task.taskDescription?.deserializeJSON(),
              let op = FileOperationType(json: json), let fileProvider = fileProvider else {
            return
        }
        
        switch op {
        case .create(path: let path):
            if path.hasSuffix("/") { return }
            break
        case .modify:
            break
        case .copy(source: let source, destination: _) where source.hasPrefix("file://"):
            break
        default:
            return
        }
        
        // wokaround for multipart uploading
        let uploadedBytes = (json["uploadedBytes"] as? Int64) ?? 0
        let totalBytes = (json["totalBytes"] as? Int64) ?? totalBytesExpectedToSend
        
        fileProvider.delegateNotify(op, progress: Double(uploadedBytes + totalBytesSent) / Double(totalBytes))
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown { return }
        
        guard let json = downloadTask.taskDescription?.deserializeJSON(),
              let op = FileOperationType(json: json), let fileProvider = fileProvider else {
            return
        }
        
        fileProvider.delegateNotify(op, progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(didReceive: challenge, completionHandler: completionHandler)
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
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
    
    public var localizedDescription: String {
        return HTTPURLResponse.localizedString(forStatusCode: self.rawValue)
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
