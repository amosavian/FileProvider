//
//  SessionDelegate.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

class SessionDelegate: NSObject, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate {
    
    weak var fileProvider: FileProvider?
    var credential: NSURLCredential?
    
    var finishDownloadHandler: ((session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL: NSURL) -> Void)?
    var didSendDataHandler: ((session: NSURLSession, task: NSURLSessionTask, bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) -> Void)?
    var didReceivedData: ((session: NSURLSession, downloadTask: NSURLSessionDownloadTask, bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) -> Void)?
    
    init(fileProvider: FileProvider, credential: NSURLCredential?) {
        self.fileProvider = fileProvider
        self.credential = credential
    }
    
    // codebeat:disable[ARITY]
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        self.finishDownloadHandler?(session: session, downloadTask: downloadTask, didFinishDownloadingToURL: location)
        return
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.didSendDataHandler?(session: session, task: task, bytesSent: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
        
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
            op = .Create(path: source)
        case "Copy":
            guard let dest = dest else { return }
            op = .Copy(source: source, destination: dest)
        case "Move":
            guard let dest = dest else { return }
            op = .Move(source: source, destination: dest)
        case "Modify":
            op = .Modify(path: source)
        case "Remove":
            op = .Remove(path: source)
        case "Link":
            guard let dest = dest else { return }
            op = .Link(link: source, target: dest)
        default:
            return
        }
        
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        
        fileProvider?.delegate?.fileproviderProgress(fileProvider!, operation: op, progress: progress)
    }
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.didReceivedData?(session: session, downloadTask: downloadTask, bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        
        guard let desc = downloadTask.taskDescription, let json = jsonToDictionary(desc), let source = json["source"] as? String, dest = json["dest"] as? String else {
            return
        }
        
        fileProvider?.delegate?.fileproviderProgress(fileProvider!, operation: .Copy(source: source, destination: dest), progress: Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        let deposition: NSURLSessionAuthChallengeDisposition = credential != nil ? .UseCredential : .PerformDefaultHandling
        completionHandler(deposition, credential)
    }
    
    func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        let deposition: NSURLSessionAuthChallengeDisposition = credential != nil ? .UseCredential : .PerformDefaultHandling
        completionHandler(deposition, credential)
    }
}

public enum FileProviderHTTPErrorCode: Int {
    case Continue = 100
    case SwitchingProtocols = 101
    case Processing = 102
    case OK = 200
    case Created = 201
    case Accepted = 202
    case NonAuthoritativeInformation = 203
    case NoContent = 204
    case ResetContent = 205
    case PartialContent = 206
    case MultiStatus = 207
    case AlreadyReported = 208
    case IMUsed = 226
    case MultipleChoices = 300
    case MovedPermanently = 301
    case Found = 302
    case SeeOther = 303
    case NotModified = 304
    case UseProxy = 305
    case SwitchProxy = 306
    case TemporaryRedirect = 307
    case PermanentRedirect = 308
    case BadRequest = 400
    case Unauthorized = 401
    case PaymentRequired = 402
    case Forbidden = 403
    case NotFound = 404
    case MethodNotAllowed = 405
    case NotAcceptable = 406
    case ProxyAuthenticationRequired = 407
    case RequestTimeout = 408
    case Conflict = 409
    case Gone = 410
    case LengthRequired = 411
    case PreconditionFailed = 412
    case PayloadTooLarge = 413
    case URITooLong = 414
    case UnsupportedMediaType = 415
    case RangeNotSatisfiable = 416
    case ExpectationFailed = 417
    case MisdirectedRequest = 421
    case UnprocessableEntity = 422
    case Locked = 423
    case FailedDependency = 424
    case UnorderedCollection = 425
    case UpgradeRequired = 426
    case PreconditionRequired = 428
    case TooManyRequests = 429
    case RequestHeaderFieldsTooLarge = 431
    case UnavailableForLegalReasons = 451
    case InternalServerError = 500
    case BadGateway = 502
    case ServiceUnavailable = 503
    case GatewayTimeout = 504
    case HTTPVersionNotSupported = 505
    case VariantlsoNegotiates = 506
    case InsufficientStorage = 507
    case LoopDetected = 508
    case BandwidthLimitExceeded = 509
    case NotExtended = 510
    case NetworkAuthenticationRequired = 511
    
    private static let status1xx = [100: "Continue", 101: "Switching Protocols", 102: "Processing"]
    private static let status2xx = [200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used"]
    private static let status3xx = [300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 305: "Use Proxy", 306: "Switch Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect"]
    private static let status4xx = [400: "Bad Request", 401: "Unauthorized/Expired Session", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Payload Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 421: "Misdirected Request", 422: "Unprocessable Entity", 423: "Locked", 424: "Failed Dependency", 425: "Unordered Collection", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons"]
    private static let status5xx = [500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected", 509: "Bandwidth Limit Exceeded", 510: "Not Extended", 511: "Network Authentication Required"]
    
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