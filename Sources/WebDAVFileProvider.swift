//
//  WebDAVFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public final class WebDavFileObject: FileObject {
    public let contentType: String
    public let entryTag: String?
    
    // codebeat:disable[ARITY]
    public init(absoluteURL: NSURL, name: String, path: String, size: Int64 = -1, contentType: String = "", createdDate: NSDate? = nil, modifiedDate: NSDate? = nil, fileType: FileType = .Regular, isHidden: Bool = false, isReadOnly: Bool = false, entryTag: String? = nil) {
        self.contentType = contentType
        self.entryTag = entryTag
        super.init(absoluteURL: absoluteURL, name: name, path: path, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
    // codebeat:enable[ARITY]
}

// Because this class uses NSURLSession, it's necessary to disable App Transport Security
// in case of using this class with unencrypted HTTP connection.

public class WebDAVFileProvider: NSObject,  FileProviderBasic {
    public let type: String = "WebDAV"
    public let isPathRelative: Bool = true
    public let baseURL: NSURL?
    public var currentPath: String = ""
    public var dispatch_queue: dispatch_queue_t {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    public weak var delegate: FileProviderDelegate?
    public let credential: NSURLCredential?
    
    private var _session: NSURLSession?
    private var sessionDelegate: SessionDelegate?
    private var session: NSURLSession {
        if _session == nil {
            self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
            let queue = NSOperationQueue()
            //queue.underlyingQueue = dispatch_queue
            _session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration(), delegate: sessionDelegate, delegateQueue: queue)
        }
        return _session!
    }
    
    public init? (baseURL: NSURL, credential: NSURLCredential?) {
        if  !["http", "https"].contains(baseURL.uw_scheme.lowercaseString) {
            return nil
        }
        self.baseURL = baseURL
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        //let url = baseURL.uw_absoluteString
        self.credential = credential
    }
    
    deinit {
        _session?.invalidateAndCancel()
    }
    
    public func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObject], error: ErrorType?) -> Void)) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".dataUsingEncoding(NSUTF8StringEncoding)
        request.setValue(String(request.HTTPBody!.length), forHTTPHeaderField: "Content-Length")
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                var fileObjects = [WebDavFileObject]()
                for attr in xresponse {
                    if attr.href.path == url.path {
                        continue
                    }
                    fileObjects.append(self.mapToFileObject(attr))
                }
                completionHandler(contents: fileObjects, error: responseError ?? error)
                return
            }
            completionHandler(contents: [], error: responseError ?? error)
        }
        task.resume()
    }
    
    public func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObject?, error: ErrorType?) -> Void)) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".dataUsingEncoding(NSUTF8StringEncoding)
        request.setValue(String(request.HTTPBody!.length), forHTTPHeaderField: "Content-Length")
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                if let attr = xresponse.first {
                    completionHandler(attributes: self.mapToFileObject(attr), error: responseError ?? error)
                    return
                }
            }
            completionHandler(attributes: nil, error: responseError ?? error)
        }
        task.resume()
    }
    
    public func storageProperties(completionHandler: ((total: Int64, used: Int64) -> Void)) {
        // Not all WebDAV clients implements RFC2518 which allows geting storage quota.
        // In this case you won't get error. totalSize is NSURLSessionTransferSizeUnknown
        // and used space is zero.
        guard let baseURL = baseURL else {
            return
        }
        let request = NSMutableURLRequest(URL: baseURL)
        request.HTTPMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop>\n</D:propfind>".dataUsingEncoding(NSUTF8StringEncoding)
        request.setValue(String(request.HTTPBody!.length), forHTTPHeaderField: "Content-Length")
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                if let attr = xresponse.first {
                    let totalSize = Int64(attr.prop["quota-available-bytes"] ?? "")
                    let usedSize = Int64(attr.prop["quota-used-bytes"] ?? "")
                    completionHandler(total: totalSize ?? -1, used: usedSize ?? 0)
                    return
                }
            }
            completionHandler(total: -1, used: 0)
        }
        task.resume()
    }
    
    public weak var fileOperationDelegate: FileOperationDelegate?
}

extension WebDAVFileProvider: FileProviderOperations {
    public func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL((atPath as NSString).stringByAppendingPathComponent(folderName) + "/")
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "MKCOL"
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let response = response as? NSHTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) where code != .OK {
                completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                return
            }
            completionHandler?(error: responseError ?? error)
            self.delegateNotify(.Create(path: (atPath as NSString).stringByAppendingPathComponent(folderName) + "/"), error: responseError ?? error)
        }
        task.resume()
    }
    
    public func createFile(fileAttribs: FileObject, atPath path: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PUT"
        let task = session.uploadTaskWithRequest(request, fromData: data) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(error: responseError ?? error)
            self.delegateNotify(.Create(path: (path as NSString).stringByAppendingPathComponent(fileAttribs.name)), error: responseError ?? error)
        }
        task.taskDescription = dictionaryToJSON(["type": "Create", "source": (path as NSString).stringByAppendingPathComponent(fileAttribs.name)])
        task.resume()
    }
    
    public func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        self.copyMoveItemAtPath(true, path: path, toPath: toPath, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    public func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        self.copyMoveItemAtPath(false, path: path, toPath: toPath, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    private func copyMoveItemAtPath(move:Bool, path: String, toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        if move {
            request.HTTPMethod = "MOVE"
        } else {
            request.HTTPMethod = "COPY"
        }
        request.setValue(absoluteURL(path).uw_absoluteString, forHTTPHeaderField: "Destination")
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                defer {
                    let op = move ? FileOperation.Move(source: path, destination: toPath) : .Copy(source: path, destination: toPath)
                    self.delegateNotify(op, error: error)
                }
                if code == .MultiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses where xresponse.status >= 300 {
                        completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                    }
                } else {
                    completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                }
                return
            }
            completionHandler?(error: error)
        }
        task.resume()
    }
    
    public func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "DELETE"
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                defer {
                    self.delegateNotify(.Remove(path: path), error: error)
                }
                if code == .MultiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses where xresponse.status >= 300 {
                        completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                    }
                } else {
                    completionHandler?(error: FileProviderWebDavError(code: code, url: url))
                }
                return
            }
            completionHandler?(error: error)
        }
        task.resume()
    }
    
    public func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(toPath)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PUT"
        let task = session.uploadTaskWithRequest(request, fromFile: localFile) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(error: responseError ?? error)
            self.delegateNotify(.Move(source: localFile.uw_absoluteString, destination: toPath), error: responseError ?? error)
        }
        task.taskDescription = dictionaryToJSON(["type": "Copy", "source": localFile.uw_absoluteString, "dest": toPath])
        task.resume()
    }
    
    public func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        let task = session.downloadTaskWithRequest(request) { (sourceFileURL, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let sourceFileURL = sourceFileURL {
                do {
                    try NSFileManager.defaultManager().copyItemAtURL(sourceFileURL, toURL: toLocalURL)
                } catch let e {
                    completionHandler?(error: e)
                    return
                }
            }
            completionHandler?(error: responseError ?? error)
        }
        task.taskDescription = dictionaryToJSON(["type": "Copy", "source": path, "dest": toLocalURL.uw_absoluteString])
        task.resume()
    }
}

extension WebDAVFileProvider: FileProviderReadWrite {
    public func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        self.contentsAtPath(path, offset: 0, length: -1, completionHandler: completionHandler)
    }
    
    public func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "GET"
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler(contents: data, error: responseError ?? error)
        }
        task.resume()
    }
    
    public func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool = false, completionHandler: SimpleCompletionHandler) {
        // FIXME: lock destination before writing process
        let url = atomically ? absoluteURL(path).uw_URLByAppendingPathExtension("tmp") : absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PUT"
        let task = session.uploadTaskWithRequest(request, fromData: data) { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: self.absoluteURL(path))
            }
            defer {
                self.delegateNotify(.Modify(path: path), error: responseError ?? error)
            }
            if let error = error {
                completionHandler?(error: error)
                return
            }
            if atomically {
                self.moveItemAtPath((path as NSString).stringByAppendingPathExtension("tmp")!, toPath: path, completionHandler: completionHandler)
            }
        }
        task.taskDescription = dictionaryToJSON(["type": "Modify", "source": path])
        task.resume()
    }
    
    public func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: ((files: [FileObject], error: ErrorType?) -> Void)) {
        let url = absoluteURL(path)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "PROPFIND"
        //request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".dataUsingEncoding(NSUTF8StringEncoding)
        request.setValue(String(request.HTTPBody!.length), forHTTPHeaderField: "Content-Length")
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            // FIXME: paginating results
            var responseError: FileProviderWebDavError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                var fileObjects = [WebDavFileObject]()
                for attr in xresponse {
                    if let path = attr.href.path where !((path as NSString).lastPathComponent.containsString(query)) {
                        continue
                    }
                    let fileObject = self.mapToFileObject(attr)
                    fileObjects.append(fileObject)
                    foundItemHandler?(fileObject)
                }
                completionHandler(files: fileObjects, error: responseError ?? error)
                return
            }
            completionHandler(files: [], error: responseError ?? error)
        }
        task.resume()
    }
    
    private func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is no unified api for monitoring WebDAV server content change/update
         * Microsoft Exchange uses SUBSCRIBE method, Apple uses push notification system.
         * while both is unavailable in a mobile platform.
         * A messy approach is listing a directory with an interval period and compare
         * with previous results
         */
    }
    private func unregisterNotifcation(path: String) {
        
    }
    // TODO: implements methods for lock mechanism
}

extension WebDAVFileProvider: FileProvider {}

// MARK: WEBDAV XML response implementation

internal extension WebDAVFileProvider {
    struct DavResponse {
        let href: NSURL
        let hrefString: String
        let status: Int?
        let prop: [String: String]
    }
    
    private func parseXMLResponse(response: NSData) -> [DavResponse] {
        var result = [DavResponse]()
        do {
            let xml = try AEXMLDocument(xmlData: response)
            var rootnode = xml.root
            var responsetag = "response"
            for node in rootnode.all ?? [] where node.name.lowercaseString.hasSuffix("multistatus") {
                rootnode = node
            }
            for node in rootnode.children ?? [] where node.name.lowercaseString.hasSuffix("response") {
                responsetag = node.name
                break
            }
            for responseNode in rootnode[responsetag].all ?? [] {
                if let davResponse = mapNodeToDavResponse(responseNode) {
                    result.append(davResponse)
                }
            }
        } catch _ { 
        }
        return result
    }
    
    private func mapNodeToDavResponse(node: AEXMLElement) -> DavResponse? {
        var hreftag = "href"
        var statustag = "status"
        var propstattag = "propstat"
        for node in node.children ?? [] {
            if node.name.lowercaseString.hasSuffix("href") {
                hreftag = node.name
            }
            if node.name.lowercaseString.hasSuffix("status") {
                statustag = node.name
            }
            if node.name.lowercaseString.hasSuffix("propstat") {
                propstattag = node.name
            }
        }
        let href = node[hreftag].value
        if let href = href, hrefURL = NSURL(string: href) {
            var status: Int?
            let statusDesc = (node[statustag].stringValue).componentsSeparatedByString(" ")
            if statusDesc.count > 2 {
                status = Int(statusDesc[1])
            }
            var propDic = [String: String]()
            let propStatNode = node[propstattag]
            for node in propStatNode.children ?? [] where node.name.lowercaseString.hasSuffix("status"){
                statustag = node.name
                break
            }
            let statusDesc2 = (propStatNode[statustag].stringValue).componentsSeparatedByString(" ")
            if statusDesc2.count > 2 {
                status = Int(statusDesc2[1])
            }
            var proptag = "prop"
            for tnode in propStatNode.children ?? [] where tnode.name.lowercaseString.hasSuffix("prop") {
                proptag = tnode.name
                break
            }
            for propItemNode in propStatNode[proptag].children ?? [] {
                propDic[propItemNode.name.componentsSeparatedByString(":").last!.lowercaseString] = propItemNode.value
                if propItemNode.name.hasSuffix("resourcetype") && propItemNode.xmlString.containsString("collection") {
                    propDic["getcontenttype"] = "httpd/unix-directory"
                }
            }
            return DavResponse(href: hrefURL, hrefString: href, status: status, prop: propDic)
        }
        return nil
    }
    
    private func mapToFileObject(davResponse: DavResponse) -> WebDavFileObject {
        var href = davResponse.href
        if href.baseURL == nil {
            href = absoluteURL(href.path ?? "")
        }
        let name = davResponse.prop["displayname"] ?? (davResponse.hrefString.stringByRemovingPercentEncoding! as NSString).lastPathComponent
        let size = Int64(davResponse.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
        let createdDate = self.resolveDate(davResponse.prop["creationdate"] ?? "")
        let modifiedDate = self.resolveDate(davResponse.prop["getlastmodified"] ?? "")
        let contentType = davResponse.prop["getcontenttype"] ?? "octet/stream"
        let isDirectory = contentType == "httpd/unix-directory"
        let entryTag = davResponse.prop["getetag"]
        return WebDavFileObject(absoluteURL: href, name: name, path: href.path ?? name, size: size, contentType: contentType, createdDate: createdDate, modifiedDate: modifiedDate, fileType: isDirectory ? .Directory : .Regular, isHidden: false, isReadOnly: false, entryTag: entryTag)
    }
    
    private func delegateNotify(operation: FileOperation, error: ErrorType?) {
        dispatch_async(dispatch_get_main_queue(), {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
}

public struct FileProviderWebDavError: ErrorType, CustomStringConvertible {
    public let code: FileProviderHTTPErrorCode
    public let url: NSURL
    
    public var description: String {
        return code.description
    }
}