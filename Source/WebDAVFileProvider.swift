//
//  WebDAVFileProvider.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/6/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

enum FileProviderWebDavErrorCode: Int {
    case OK = 200
    case Created = 201
    case NoContent = 204
    case MultiStatus = 207
    case Forbidden = 403
    case MethodNotAllowed = 405
    case Conflict = 409
    case PreconditionFailed = 412
    case UnsupportedMediaType = 415
    case Locked = 423
    case FailedDependency = 424
    case BadGateway = 502
    case InsufficientStorage = 507
}

struct FileProviderWebDavError: ErrorType, CustomStringConvertible {
    let code: FileProviderWebDavErrorCode
    let url: NSURL
    
    var description: String {
        switch code {
        case .OK: return "OK"
        case .Created: return "Created"
        case .NoContent: return "No Content"
        case .MultiStatus: return ""
        case .Forbidden: return "Forbidden"
        case .MethodNotAllowed: return "Method Not Allowed"
        case .Conflict: return "Conflict"
        case .PreconditionFailed: return "Precondition Failed"
        case .UnsupportedMediaType: return "Unsupported Media Type"
        case .Locked: return "Locked"
        case .FailedDependency: return "Failed Dependency"
        case .BadGateway: return "Bad Gateway"
        case .InsufficientStorage: return "Insufficient Storage"
        }
    }
}

final class WebDavFileObject: FileObject {
    let contentType: String
    let entryTag: String?
    
    init(absoluteURL: NSURL, name: String, size: Int64, contentType: String, createdDate: NSDate?, modifiedDate: NSDate?, fileType: FileType, isHidden: Bool, isReadOnly: Bool, entryTag: String?) {
        self.contentType = contentType
        self.entryTag = entryTag
        super.init(absoluteURL: absoluteURL, name: name, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
}

// Because this class uses NSURLSession, it's necessary to disable App Transport Security
// in case of using this class with unencrypted HTTP connection.

class WebDAVFileProvider: NSObject,  FileProvider {
    var type: String = "WebDAV"
    var isPathRelative: Bool = true
    var baseURL: NSURL?
    var currentPath: String = ""
    var dispatch_queue: dispatch_queue_t
    var delegate: FileProviderDelegate?
    let credential: NSURLCredential?
    
    typealias FileObjectClass = FileObject
    
    private var _session: NSURLSession?
    private var session: NSURLSession {
        if _session == nil {
            _session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration(), delegate: self, delegateQueue: nil)
        }
        return _session!
    }
    
    init? (baseURL: NSURL, credential: NSURLCredential?) {
        if  !["http", "https"].contains(baseURL.scheme.lowercaseString) {
            return nil
        }
        self.baseURL = baseURL
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        //let url = baseURL.absoluteString
        self.credential = credential
    }
    
    deinit {
    }
    
    func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObjectClass], error: ErrorType?) -> Void)) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PROPFIND"
        request.setValue(baseURL?.absoluteString, forHTTPHeaderField: "Host")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".dataUsingEncoding(NSUTF8StringEncoding)
        request.setValue(String(request.HTTPBody!.length), forHTTPHeaderField: "Content-Length")
        session.dataTaskWithRequest(request) { (data, response, error) in
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                var fileObjects = [WebDavFileObject]()
                for attr in xresponse {
                    let href = attr.href
                    if href.path == url.path {
                        continue
                    }
                    let name = attr.prop["displayname"] ?? path.lastPathComponent
                    let size = Int64(attr.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
                    let createdDate = self.resolveHTTPDate(attr.prop["creationdate"] ?? "")
                    let modifiedDate = self.resolveHTTPDate(attr.prop["getlastmodified"] ?? "")
                    let contentType = attr.prop["getcontenttype"] ?? "octet/stream"
                    let isDirectory = contentType == "httpd/unix-directory"
                    let entryTag = attr.prop["getetag"]
                    let fileObject = WebDavFileObject(absoluteURL: href, name: name, size: size, contentType: contentType, createdDate: createdDate, modifiedDate: modifiedDate, fileType: isDirectory ? .Directory : .Regular, isHidden: false, isReadOnly: false, entryTag: entryTag)
                    fileObjects.append(fileObject)
                }
                completionHandler(contents: fileObjects, error: error)
                return
            }
            completionHandler(contents: [], error: error)
        }.resume()
    }
    
    func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObjectClass?, error: ErrorType?) -> Void)) {
        let request = NSMutableURLRequest(URL: absoluteURL(path))
        request.HTTPMethod = "PROPFIND"
        request.setValue(baseURL?.absoluteString, forHTTPHeaderField: "Host")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".dataUsingEncoding(NSUTF8StringEncoding)
        request.setValue(String(request.HTTPBody!.length), forHTTPHeaderField: "Content-Length")
        session.dataTaskWithRequest(request) { (data, response, error) in
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                if let attr = xresponse.first {
                    let href = attr.href
                    let name = attr.prop["displayname"] ?? path.lastPathComponent
                    let size = Int64(attr.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
                    let createdDate = self.resolveHTTPDate(attr.prop["creationdate"] ?? "")
                    let modifiedDate = self.resolveHTTPDate(attr.prop["getlastmodified"] ?? "")
                    let contentType = attr.prop["getcontenttype"] ?? "octet/stream"
                    let isDirectory = contentType == "httpd/unix-directory"
                    let entryTag = attr.prop["getetag"]
                    let fileObject = WebDavFileObject(absoluteURL: href, name: name, size: size, contentType: contentType, createdDate: createdDate, modifiedDate: modifiedDate, fileType: isDirectory ? .Directory : .Regular, isHidden: false, isReadOnly: false, entryTag: entryTag)
                    completionHandler(attributes: fileObject, error: error)
                    return
                }
            }
            completionHandler(attributes: nil, error: error)
        }.resume()
    }
    
    func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        let url = absoluteURL(atPath.stringByAppendingPathComponent(folderName) + "/")
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "MKCOL"
        request.setValue(baseURL?.absoluteString, forHTTPHeaderField: "Host")
        session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse, let code = FileProviderWebDavErrorCode(rawValue: response.statusCode) where code != .OK {
                completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                return
            }
            completionHandler?(error: error)
            dispatch_async(dispatch_get_main_queue(), {
                self.delegate?.fileproviderCreateModifyNotify(self, path: atPath)
            })
        }.resume()
    }
    
    func createFile(fileAttribs: FileObject, atPath path: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
        let request = NSMutableURLRequest(URL: absoluteURL(path))
        request.HTTPMethod = "PUT"
        session.uploadTaskWithRequest(request, fromData: data) { (data, response, error) in
            completionHandler?(error: error)
            dispatch_async(dispatch_get_main_queue(), {
                self.delegate?.fileproviderCreateModifyNotify(self, path: path)
            })
        }.resume()
    }
    
    func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "MOVE"
        request.setValue(baseURL?.absoluteString, forHTTPHeaderField: "Host")
        request.setValue(absoluteURL(path).absoluteString, forHTTPHeaderField: "Destination")
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse, let code = FileProviderWebDavErrorCode(rawValue: response.statusCode) {
                if code == .OK {
                    dispatch_async(dispatch_get_main_queue(), {
                        self.delegate?.fileproviderMoveNotify(self, fromPath: path, toPath: toPath)
                    })
                } else if code == .MultiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses {
                        if xresponse.status >= 300 {
                            completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                        }
                    }
                } else {
                    completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                }
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderMoveNotify(self, fromPath: path, toPath: toPath)
                })
                return
            }
            completionHandler?(error: error)
        }.resume()
    }
    
    func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "COPY"
        request.setValue(baseURL?.absoluteString, forHTTPHeaderField: "Host")
        request.setValue(absoluteURL(path).absoluteString, forHTTPHeaderField: "Destination")
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse, let code = FileProviderWebDavErrorCode(rawValue: response.statusCode) {
                if code == .OK {
                    dispatch_async(dispatch_get_main_queue(), {
                        self.delegate?.fileproviderCopyNotify(self, fromPath: path, toPath: toPath)
                    })
                } else if code == .MultiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses {
                        if xresponse.status >= 300 {
                            completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                        }
                    }
                    dispatch_async(dispatch_get_main_queue(), {
                        self.delegate?.fileproviderCopyNotify(self, fromPath: path, toPath: toPath)
                    })
                } else {
                    completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                }
                return
            }
            completionHandler?(error: error)
        }.resume()
    }
    
    func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "DELETE"
        request.setValue(baseURL?.absoluteString, forHTTPHeaderField: "Host")
        session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse, let code = FileProviderWebDavErrorCode(rawValue: response.statusCode) {
                if code == .OK {
                    dispatch_async(dispatch_get_main_queue(), {
                        self.delegate?.fileproviderRemoveNotify(self, path: path)
                    })
                } else if code == .MultiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses {
                        if xresponse.status >= 300 {
                            completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                        }
                    }
                    dispatch_async(dispatch_get_main_queue(), {
                        self.delegate?.fileproviderRemoveNotify(self, path: path)
                    })
                } else {
                    completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                }
                return
            }
            completionHandler?(error: error)
        }.resume()
    }
    
    func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        let request = NSMutableURLRequest(URL: absoluteURL(toPath))
        request.HTTPMethod = "PUT"
        session.uploadTaskWithRequest(request, fromFile: localFile) { (data, response, error) in
            completionHandler?(error: error)
            dispatch_async(dispatch_get_main_queue(), {
                self.delegate?.fileproviderCreateModifyNotify(self, path: toPath)
            })
        }.resume()
    }
    
    func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler) {
        let request = NSMutableURLRequest(URL: absoluteURL(path))
        session.downloadTaskWithRequest(request) { (sourceFileURL, response, error) in
            if let sourceFileURL = sourceFileURL {
                do {
                    try NSFileManager.defaultManager().copyItemAtURL(sourceFileURL, toURL: toLocalURL)
                } catch let e {
                    completionHandler?(error: e)
                    return
                }
            }
            completionHandler?(error: error)
        }.resume()
    }
    
    func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        let request = NSMutableURLRequest(URL: absoluteURL(path))
        request.HTTPMethod = "GET"
        session.dataTaskWithRequest(request) { (data, response, error) in
            completionHandler(contents: data, error: error)
        }.resume()
    }
    
    func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        let request = NSMutableURLRequest(URL: absoluteURL(path))
        request.HTTPMethod = "GET"
        request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        session.dataTaskWithRequest(request) { (data, response, error) in
            completionHandler(contents: data, error: error)
        }.resume()
    }
    
    func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool = false, completionHandler: SimpleCompletionHandler) {
        // FIXME: lock destination before writing process
        let url = atomically ? absoluteURL(path).URLByAppendingPathExtension("tmp") : absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PUT"
        session.uploadTaskWithRequest(request, fromData: data) { (data, response, error) in
            if atomically {
                self.moveItemAtPath(path.stringByAppendingPathExtension("tmp")!, toPath: path, completionHandler: completionHandler)
            }
            if let error = error {
                // If there is no error, completionHandler has been executed by move command
                completionHandler?(error: error)
            }
        }.resume()
    }
    
    func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObjectClass) -> Void)?, completionHandler: ((files: [FileObjectClass], error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    // TODO: implements methods for lock mechanism
}

// MARK: WEBDAV XML response implementation

extension WebDAVFileProvider {
    struct DavResponse {
        let href: NSURL
        let status: Int?
        let prop: [String: String]
    }
    
    private func parseXMLResponse(response: NSData) -> [DavResponse] {
        var result = [DavResponse]()
        do {
            let xml = try AEXMLDocument(xmlData: response)
            var responsetag = "response"
            for node in xml.root.all ?? [] {
                if node.name.lowercaseString.hasSuffix("response") {
                    responsetag = node.name
                }
            }
            for responseNode in xml.root[responsetag].all ?? [] {
                var hreftag = "href"
                var statustag = "status"
                var propstattag = "propstat"
                for tnode in responseNode.all ?? [] {
                    if tnode.name.lowercaseString.hasSuffix("href") {
                        hreftag = tnode.name
                    }
                    if tnode.name.lowercaseString.hasSuffix("status") {
                        statustag = tnode.name
                    }
                    if tnode.name.lowercaseString.hasSuffix("propstat") {
                        propstattag = tnode.name
                    }
                }
                let href = responseNode[hreftag].value
                if let href = href, hrefURL = NSURL(string: href) {
                    var status: Int?
                    let statusDesc = (responseNode[statustag].stringValue).componentsSeparatedByString(" ")
                    if statusDesc.count > 2 {
                        status = Int(statusDesc[1])
                    }
                    var propDic = [String: String]()
                    let propStatNode = responseNode[propstattag]
                    let statusDesc2 = (propStatNode[statustag].stringValue).componentsSeparatedByString(" ")
                    if statusDesc2.count > 2 {
                        status = Int(statusDesc2[1])
                    }
                    var proptag = "prop"
                    for tnode in propStatNode.all ?? [] {
                        if tnode.name.lowercaseString.hasSuffix("prop") {
                            proptag = tnode.name
                        }
                        break
                    }
                    for propItemNode in propStatNode[proptag].all ?? [] {
                        propDic[propItemNode.name.componentsSeparatedByString(":").last!.lowercaseString] = propItemNode.value
                    }
                    result.append(DavResponse(href: hrefURL, status: status, prop: propDic))
                }
            }
        } catch _ {
            
        }
        return result
    }
    
    func resolveHTTPDate(httpDateString: String) -> NSDate? {
        if let rfc1123 = NSDate(string: httpDateString, withFormat: "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss zzz") {
            return NSDate(timeIntervalSince1970: rfc1123.timeIntervalSince1970)
        }
        if let rfc850 = NSDate(string: httpDateString, withFormat: "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z") {
            return NSDate(timeIntervalSince1970: rfc850.timeIntervalSince1970)
            
        }
        if let asctime =  NSDate(string: httpDateString, withFormat: "EEE MMM d HH':'mm':'ss yyyy") {
            return NSDate(timeIntervalSince1970: asctime.timeIntervalSince1970)
        }
        //self.init()
        return nil
    }
}

// MARK: URLSession delegate
extension WebDAVFileProvider: NSURLSessionDownloadDelegate {
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        return
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        completionHandler(NSURLSessionAuthChallengeDisposition.UseCredential, credential)
    }
    
    func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        completionHandler(NSURLSessionAuthChallengeDisposition.UseCredential, credential)
    }
}