//
//  SessionDelegate.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

class SessionDelegate: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    weak var fileProvider: FileProvider?
    var credential: URLCredential?
    
    var finishDownloadHandler: ((_ session: Foundation.URLSession, _ downloadTask: URLSessionDownloadTask, _ didFinishDownloadingToURL: URL) -> Void)?
    var didSendDataHandler: ((_ session: Foundation.URLSession, _ task: URLSessionTask, _ bytesSent: Int64, _ totalBytesSent: Int64, _ totalBytesExpectedToSend: Int64) -> Void)?
    var didReceivedData: ((_ session: Foundation.URLSession, _ downloadTask: URLSessionDownloadTask, _ bytesWritten: Int64, _ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void)?
    
    init(fileProvider: FileProvider, credential: URLCredential?) {
        self.fileProvider = fileProvider
        self.credential = credential
    }
    
    // codebeat:disable[ARITY]
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.finishDownloadHandler?(session, downloadTask, location)
        return
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.didSendDataHandler?(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
        
        guard let desc = task.taskDescription, let json = jsonToDictionary(desc) else {
            return
        }
        guard let type = json["type"] as? String, let source = json["source"] as? String else {
            return
        }
        let dest = json["dest"] as? String
        let op : FileOperation
        switch type {
        case "Create":
            op = .create(path: source)
        case "Copy":
            guard let dest = dest else { return }
            op = .copy(source: source, destination: dest)
        case "Move":
            guard let dest = dest else { return }
            op = .move(source: source, destination: dest)
        case "Modify":
            op = .modify(path: source)
        case "Remove":
            op = .remove(path: source)
        case "Link":
            guard let dest = dest else { return }
            op = .link(link: source, target: dest)
        default:
            return
        }
        
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        
        fileProvider?.delegate?.fileproviderProgress(fileProvider!, operation: op, progress: progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.didReceivedData?(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
        
        guard let desc = downloadTask.taskDescription, let json = jsonToDictionary(desc), let source = json["source"] as? String, let dest = json["dest"] as? String else {
            return
        }
        
        fileProvider?.delegate?.fileproviderProgress(fileProvider!, operation: .copy(source: source, destination: dest), progress: Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let deposition: Foundation.URLSession.AuthChallengeDisposition = credential != nil ? .useCredential : .performDefaultHandling
        completionHandler(deposition, credential)
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let deposition: Foundation.URLSession.AuthChallengeDisposition = credential != nil ? .useCredential : .performDefaultHandling
        completionHandler(deposition, credential)
    }
}

public enum FileProviderHTTPErrorCode: Int {
    case `continue` = 100
    case switchingProtocols = 101
    case processing = 102
    case ok = 200
    case created = 201
    case accepted = 202
    case nonAuthoritativeInformation = 203
    case noContent = 204
    case resetContent = 205
    case partialContent = 206
    case multiStatus = 207
    case alreadyReported = 208
    case imUsed = 226
    case multipleChoices = 300
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case useProxy = 305
    case switchProxy = 306
    case temporaryRedirect = 307
    case permanentRedirect = 308
    case badRequest = 400
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case proxyAuthenticationRequired = 407
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case payloadTooLarge = 413
    case uriTooLong = 414
    case unsupportedMediaType = 415
    case rangeNotSatisfiable = 416
    case expectationFailed = 417
    case misdirectedRequest = 421
    case unprocessableEntity = 422
    case locked = 423
    case failedDependency = 424
    case unorderedCollection = 425
    case upgradeRequired = 426
    case preconditionRequired = 428
    case tooManyRequests = 429
    case requestHeaderFieldsTooLarge = 431
    case unavailableForLegalReasons = 451
    case internalServerError = 500
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case httpVersionNotSupported = 505
    case variantlsoNegotiates = 506
    case insufficientStorage = 507
    case loopDetected = 508
    case bandwidthLimitExceeded = 509
    case notExtended = 510
    case networkAuthenticationRequired = 511
    
    fileprivate static let status1xx = [100: "Continue", 101: "Switching Protocols", 102: "Processing"]
    fileprivate static let status2xx = [200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used"]
    fileprivate static let status3xx = [300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 305: "Use Proxy", 306: "Switch Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect"]
    fileprivate static let status4xx = [400: "Bad Request", 401: "Unauthorized/Expired Session", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Payload Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 421: "Misdirected Request", 422: "Unprocessable Entity", 423: "Locked", 424: "Failed Dependency", 425: "Unordered Collection", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons"]
    fileprivate static let status5xx = [500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected", 509: "Bandwidth Limit Exceeded", 510: "Not Extended", 511: "Network Authentication Required"]
    
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
    
    public var typeDescription: String {
        switch self.rawValue {
        case 100...199: return "Informational"
        case 200...299: return "Success"
        case 300...399: return "Redirection"
        case 400...499: return "Client Error"
        case 500...599: return "Server Error"
        default: return "Server Error"
        }
    }
}
