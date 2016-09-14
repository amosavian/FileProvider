//
//  WebDAVFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func >= <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l >= r
  default:
    return !(lhs < rhs)
  }
}


public final class WebDavFileObject: FileObject {
    public let contentType: String
    public let entryTag: String?
    
    // codebeat:disable[ARITY]
    public init(absoluteURL: URL, name: String, path: String, size: Int64 = -1, contentType: String = "", createdDate: Date? = nil, modifiedDate: Date? = nil, fileType: FileType = .regular, isHidden: Bool = false, isReadOnly: Bool = false, entryTag: String? = nil) {
        self.contentType = contentType
        self.entryTag = entryTag
        super.init(absoluteURL: absoluteURL, name: name, path: path, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
    // codebeat:enable[ARITY]
}

// Because this class uses NSURLSession, it's necessary to disable App Transport Security
// in case of using this class with unencrypted HTTP connection.

open class WebDAVFileProvider: NSObject,  FileProviderBasic {
    open let type: String = "WebDAV"
    open let isPathRelative: Bool = true
    open let baseURL: URL?
    open var currentPath: String = ""
    open var dispatch_queue: DispatchQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    open weak var delegate: FileProviderDelegate?
    open let credential: URLCredential?
    
    fileprivate var _session: URLSession?
    fileprivate var sessionDelegate: SessionDelegate?
    fileprivate var session: URLSession {
        if _session == nil {
            self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
            let queue = OperationQueue()
            //queue.underlyingQueue = dispatch_queue
            _session = URLSession(configuration: URLSessionConfiguration.default, delegate: sessionDelegate as URLSessionDownloadDelegate?, delegateQueue: queue)
        }
        return _session!
    }
    
    public init? (baseURL: URL, credential: URLCredential?) {
        if  !["http", "https"].contains(baseURL.uw_scheme.lowercased()) {
            return nil
        }
        self.baseURL = baseURL
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type)", attributes: DispatchQueue.Attributes.concurrent)
        //let url = baseURL.uw_absoluteString
        self.credential = credential
    }
    
    deinit {
        _session?.invalidateAndCancel()
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: String.Encoding.utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
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
                completionHandler(fileObjects, responseError ?? error)
                return
            }
            completionHandler([], responseError ?? error)
        }) 
        task.resume()
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: String.Encoding.utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode, code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                if let attr = xresponse.first {
                    completionHandler(self.mapToFileObject(attr), responseError ?? error)
                    return
                }
            }
            completionHandler(nil, responseError ?? error)
        })
        task.resume()
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        // Not all WebDAV clients implements RFC2518 which allows geting storage quota.
        // In this case you won't get error. totalSize is NSURLSessionTransferSizeUnknown
        // and used space is zero.
        guard let baseURL = baseURL else {
            return
        }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop>\n</D:propfind>".data(using: String.Encoding.utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                if let attr = xresponse.first {
                    let totalSize = Int64(attr.prop["quota-available-bytes"] ?? "")
                    let usedSize = Int64(attr.prop["quota-used-bytes"] ?? "")
                    completionHandler(totalSize ?? -1, usedSize ?? 0)
                    return
                }
            }
            completionHandler(-1, 0)
        }) 
        task.resume()
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension WebDAVFileProvider: FileProviderOperations {
    public func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL((atPath as NSString).appendingPathComponent(folderName) + "/")
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let response = response as? HTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) , code != .ok {
                completionHandler?(FileProviderWebDavError(code: code, url: url))
                return
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.create(path: (atPath as NSString).appendingPathComponent(folderName) + "/"), error: responseError ?? error)
        }) 
        task.resume()
    }
    
    public func create(file fileAttribs: FileObject, at path: String, contents data: Data?, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.create(path: (path as NSString).appendingPathComponent(fileAttribs.name)), error: responseError ?? error)
        }) 
        task.taskDescription = dictionaryToJSON(["type": "Create" as NSString, "source": (path as NSString).appendingPathComponent(fileAttribs.name) as NSString])
        task.resume()
    }
    
    public func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        self.copyMoveItem(move: true, path: path, toPath: toPath, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    public func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        self.copyMoveItem(move: false, path: path, toPath: toPath, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    fileprivate func copyMoveItem(move:Bool, path: String, toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        if move {
            request.httpMethod = "MOVE"
        } else {
            request.httpMethod = "COPY"
        }
        request.setValue(absoluteURL(path).uw_absoluteString, forHTTPHeaderField: "Destination")
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let response = response as? HTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                defer {
                    let op = move ? FileOperation.move(source: path, destination: toPath) : .copy(source: path, destination: toPath)
                    self.delegateNotify(op, error: error)
                }
                if code == .multiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses where xresponse.status >= 300 {
                        completionHandler?(FileProviderWebDavError(code: code, url: url))
                    }
                } else {
                    completionHandler?(FileProviderWebDavError(code: code, url: url))
                }
                return
            }
            completionHandler?(error)
        }) 
        task.resume()
    }
    
    public func removeItem(path: String, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let response = response as? HTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                defer {
                    self.delegateNotify(.remove(path: path), error: error)
                }
                if code == .multiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses where xresponse.status >= 300 {
                        completionHandler?(FileProviderWebDavError(code: code, url: url))
                    }
                } else {
                    completionHandler?(FileProviderWebDavError(code: code, url: url))
                }
                return
            }
            completionHandler?(error)
        }) 
        task.resume()
    }
    
    public func copyItem(localFile: URL, to toPath: String, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(toPath)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let task = session.uploadTask(with: request, fromFile: localFile, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.move(source: localFile.uw_absoluteString, destination: toPath), error: responseError ?? error)
        }) 
        task.taskDescription = dictionaryToJSON(["type": "Copy" as NSString, "source": localFile.uw_absoluteString as NSString, "dest": toPath as NSString])
        task.resume()
    }
    
    public func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) {
        let url = absoluteURL(path)
        let request = URLRequest(url: url)
        let task = session.downloadTask(with: request, completionHandler: { (sourceFileURL, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let sourceFileURL = sourceFileURL {
                do {
                    try FileManager.default.copyItem(at: sourceFileURL, to: toLocalURL)
                } catch let e {
                    completionHandler?(e)
                    return
                }
            }
            completionHandler?(responseError ?? error)
        }) 
        task.taskDescription = dictionaryToJSON(["type": "Copy" as NSString, "source": path as NSString, "dest": toLocalURL.uw_absoluteString as NSString])
        task.resume()
    }
}

extension WebDAVFileProvider: FileProviderReadWrite {
    public func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) {
        self.contents(path: path, offset: 0, length: -1, completionHandler: completionHandler)
    }
    
    public func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler(data, responseError ?? error)
        }) 
        task.resume()
    }
    
    public func writeContents(path: String, contents data: Data, atomically: Bool = false, completionHandler: SimpleCompletionHandler) {
        // FIXME: lock destination before writing process
        let url = atomically ? absoluteURL(path).uw_URLByAppendingPathExtension("tmp") : absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: self.absoluteURL(path))
            }
            defer {
                self.delegateNotify(.modify(path: path), error: responseError ?? error)
            }
            if let error = error {
                completionHandler?(error)
                return
            }
            if atomically {
                self.moveItem(path: (path as NSString).appendingPathExtension("tmp")!, to: path, completionHandler: completionHandler)
            }
        }) 
        task.taskDescription = dictionaryToJSON(["type": "Modify" as NSString, "source": path as NSString])
        task.resume()
    }
    
    public func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        //request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: String.Encoding.utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            // FIXME: paginating results
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                var fileObjects = [WebDavFileObject]()
                for attr in xresponse {
                    let path = attr.href.path
                    if !((path as NSString).lastPathComponent.contains(query)) {
                        continue
                    }
                    let fileObject = self.mapToFileObject(attr)
                    fileObjects.append(fileObject)
                    foundItemHandler?(fileObject)
                }
                completionHandler(fileObjects, responseError ?? error)
                return
            }
            completionHandler([], responseError ?? error)
        }) 
        task.resume()
    }
    
    fileprivate func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is no unified api for monitoring WebDAV server content change/update
         * Microsoft Exchange uses SUBSCRIBE method, Apple uses push notification system.
         * while both is unavailable in a mobile platform.
         * A messy approach is listing a directory with an interval period and compare
         * with previous results
         */
    }
    fileprivate func unregisterNotifcation(path: String) {
        
    }
    // TODO: implements methods for lock mechanism
}

extension WebDAVFileProvider: FileProvider {}

// MARK: WEBDAV XML response implementation

internal extension WebDAVFileProvider {
    struct DavResponse {
        let href: URL
        let hrefString: String
        let status: Int?
        let prop: [String: String]
    }
    
    fileprivate func parseXMLResponse(_ response: Data) -> [DavResponse] {
        var result = [DavResponse]()
        do {
            let xml = try AEXMLDocument(xml: response)
            var rootnode = xml.root
            var responsetag = "response"
            for node in rootnode.all ?? [] where node.name.lowercased().hasSuffix("multistatus") {
                rootnode = node
            }
            for node in rootnode.children where node.name.lowercased().hasSuffix("response") {
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
    
    fileprivate func mapNodeToDavResponse(_ node: AEXMLElement) -> DavResponse? {
        var hreftag = "href"
        var statustag = "status"
        var propstattag = "propstat"
        for node in node.children {
            if node.name.lowercased().hasSuffix("href") {
                hreftag = node.name
            }
            if node.name.lowercased().hasSuffix("status") {
                statustag = node.name
            }
            if node.name.lowercased().hasSuffix("propstat") {
                propstattag = node.name
            }
        }
        let href = node[hreftag].value
        if let href = href, let hrefURL = URL(string: href) {
            var status: Int?
            let statusDesc = (node[statustag].string).components(separatedBy: " ")
            if statusDesc.count > 2 {
                status = Int(statusDesc[1])
            }
            var propDic = [String: String]()
            let propStatNode = node[propstattag]
            for node in propStatNode.children where node.name.lowercased().hasSuffix("status"){
                statustag = node.name
                break
            }
            let statusDesc2 = (propStatNode[statustag].string).components(separatedBy: " ")
            if statusDesc2.count > 2 {
                status = Int(statusDesc2[1])
            }
            var proptag = "prop"
            for tnode in propStatNode.children where tnode.name.lowercased().hasSuffix("prop") {
                proptag = tnode.name
                break
            }
            for propItemNode in propStatNode[proptag].children {
                propDic[propItemNode.name.components(separatedBy: ":").last!.lowercased()] = propItemNode.value
                if propItemNode.name.hasSuffix("resourcetype") && propItemNode.xml.contains("collection") {
                    propDic["getcontenttype"] = "httpd/unix-directory"
                }
            }
            return DavResponse(href: hrefURL, hrefString: href, status: status, prop: propDic)
        }
        return nil
    }
    
    fileprivate func mapToFileObject(_ davResponse: DavResponse) -> WebDavFileObject {
        var href = davResponse.href
        if href.baseURL == nil {
            href = absoluteURL(href.path)
        }
        let name = davResponse.prop["displayname"] ?? (davResponse.hrefString.removingPercentEncoding! as NSString).lastPathComponent
        let size = Int64(davResponse.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
        let createdDate = self.resolve(dateString: davResponse.prop["creationdate"] ?? "")
        let modifiedDate = self.resolve(dateString: davResponse.prop["getlastmodified"] ?? "")
        let contentType = davResponse.prop["getcontenttype"] ?? "octet/stream"
        let isDirectory = contentType == "httpd/unix-directory"
        let entryTag = davResponse.prop["getetag"]
        return WebDavFileObject(absoluteURL: href, name: name, path: href.path, size: size, contentType: contentType, createdDate: createdDate, modifiedDate: modifiedDate, fileType: isDirectory ? .directory : .regular, isHidden: false, isReadOnly: false, entryTag: entryTag)
    }
    
    fileprivate func delegateNotify(_ operation: FileOperation, error: Error?) {
        DispatchQueue.main.async(execute: {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
}

public struct FileProviderWebDavError: Error, CustomStringConvertible {
    public let code: FileProviderHTTPErrorCode
    public let url: URL
    
    public var description: String {
        return code.description
    }
}
