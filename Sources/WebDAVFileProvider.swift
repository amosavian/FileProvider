//
//  WebDAVFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public final class WebDavFileObject: FileObject {
    internal init(absoluteURL: URL, name: String, path: String) {
        super.init(absoluteURL: absoluteURL, name: name, path: path)
    }
    
    open internal(set) var contentType: String {
        get {
            return allValues["NSURLContentTypeKey"] as? String ?? ""
        }
        set {
            allValues["NSURLContentTypeKey"] = newValue
        }
    }
    
    open internal(set) var entryTag: String? {
        get {
            return allValues["NSURLEntryTagKey"] as? String
        }
        set {
            allValues["NSURLEntryTagKey"] = newValue
        }
    }
}

/// Because this class uses NSURLSession, it's necessary to disable App Transport Security
/// in case of using this class with unencrypted HTTP connection.

open class WebDAVFileProvider: NSObject,  FileProviderBasicRemote {
    open static let type: String = "WebDAV"
    open let isPathRelative: Bool = true
    open let baseURL: URL?
    open var currentPath: String = ""
    public var dispatch_queue: DispatchQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    public weak var delegate: FileProviderDelegate?
    open let credential: URLCredential?
    open private(set) var cache: URLCache?
    public var useCache: Bool = false
    public var validatingCache: Bool = true
    
    fileprivate var _session: URLSession?
    fileprivate var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        if _session == nil {
            self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
            let queue = OperationQueue()
            //queue.underlyingQueue = dispatch_queue
            let config = URLSessionConfiguration.default
            config.urlCache = cache
            config.requestCachePolicy = .returnCacheDataElseLoad
            _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDownloadDelegate?, delegateQueue: queue)
        }
        return _session!
    }
    
    public init? (baseURL: URL, credential: URLCredential?, cache: URLCache? = nil) {
        if  !["http", "https"].contains(baseURL.uw_scheme.lowercased()) {
            return nil
        }
        self.baseURL = baseURL
        dispatch_queue = DispatchQueue(label: "FileProvider.\(WebDAVFileProvider.type)", attributes: DispatchQueue.Attributes.concurrent)
        //let url = baseURL.uw_absoluteString
        self.credential = credential
        self.cache = cache
    }
    
    deinit {
        _session?.invalidateAndCancel()
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        let opType = FileOperationType.fetch(path: path)
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: .utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        runDataTask(with: request, operationHandle: RemoteOperationHandle(operationType: opType, tasks: []), completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            var fileObjects = [WebDavFileObject]()
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                for attr in xresponse {
                    if attr.href.path == url.path {
                        continue
                    }
                    fileObjects.append(self.mapToFileObject(attr))
                }
            }
            completionHandler(fileObjects, responseError ?? error)
        })
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: .utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        runDataTask(with: request, completionHandler: { (data, response, error) in
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
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop>\n</D:propfind>".data(using: .utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        runDataTask(with: request, completionHandler: { (data, response, error) in
            var totalSize: Int64 = -1
            var usedSize: Int64 = 0
            if let data = data {
                let xresponse = self.parseXMLResponse(data)
                if let attr = xresponse.first {
                    totalSize = Int64(attr.prop["quota-available-bytes"] ?? "") ?? -1
                    usedSize = Int64(attr.prop["quota-used-bytes"] ?? "") ?? 0
                }
            }
            completionHandler(totalSize, usedSize)
        })
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension WebDAVFileProvider: FileProviderOperations {
    @discardableResult
    public func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.create(path: (atPath as NSString).appendingPathComponent(folderName) + "/")
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = absoluteURL((atPath as NSString).appendingPathComponent(folderName) + "/")
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(opType, error: responseError ?? error)
        })
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    @discardableResult
    public func create(file fileName: String, at path: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.create(path: (path as NSString).appendingPathComponent(fileName))
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = absoluteURL(path).appendingPathComponent(fileName)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(opType, error: responseError ?? error)
        })
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    @discardableResult
    public func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.move(source: path, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return self.doOperation(operation: opType, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return self.doOperation(operation: opType, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.remove(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return self.doOperation(operation: opType, completionHandler: completionHandler)
    }
    
    func doOperation(operation opType: FileOperationType, overwrite: Bool? = nil, completionHandler: SimpleCompletionHandler) -> OperationHandle?  {
        let sourceURL = absoluteURL(opType.source!)
        var request = URLRequest(url: sourceURL)
        if let dest = opType.destination {
            request.setValue(absoluteURL(dest).absoluteString, forHTTPHeaderField: "Destination")
        }
        switch opType {
        case .copy:
            request.httpMethod = "COPY"
        case .move:
            request.httpMethod = "MOVE"
        case .remove:
            request.httpMethod = "DELETE"
        default:
            return nil
        }
        
        if let overwrite = overwrite, !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let response = response as? HTTPURLResponse, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                if response.statusCode >= 300  {
                    responseError = FileProviderWebDavError(code: code, url: sourceURL)
                }
                if code == .multiStatus, let data = data {
                    let xresponses = self.parseXMLResponse(data)
                    for xresponse in xresponses where (xresponse.status ?? 0) >= 300 {
                        completionHandler?(FileProviderWebDavError(code: code, url: sourceURL))
                    }
                }
            }
            if (response as? HTTPURLResponse)?.statusCode ?? 0 != FileProviderHTTPErrorCode.multiStatus.rawValue {
                completionHandler?(responseError ?? error)
            }
            
            self.delegateNotify(opType, error: responseError ?? error)
        })
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    @discardableResult
    public func copyItem(localFile: URL, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // TODO: Make use of overwrite parameter
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = absoluteURL(toPath)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let task = session.uploadTask(with: request, fromFile: localFile, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(opType, error: responseError ?? error)
        }) 
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    @discardableResult
    public func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
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
            self.delegateNotify(opType, error: responseError ?? error)
        }) 
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
}

extension WebDAVFileProvider: FileProviderReadWrite {
    @discardableResult
    public func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let opType = FileOperationType.fetch(path: path)
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let handle = RemoteOperationHandle(operationType: opType, tasks: [])
        runDataTask(with: request, operationHandle: handle, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: url)
            }
            completionHandler(data, responseError ?? error)
        })
        return handle
    }
    
    @discardableResult
    public func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        // FIXME: lock destination before writing process
        let url = atomically ? absoluteURL(path).appendingPathExtension("tmp") : absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, url: self.absoluteURL(path))
            }
            defer {
                self.delegateNotify(opType, error: responseError ?? error)
            }
            if let error = error {
                completionHandler?(error)
                return
            }
            if atomically {
                self.moveItem(path: (path as NSString).appendingPathExtension("tmp")!, to: path, completionHandler: completionHandler)
            }
        }) 
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    public func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        let url = absoluteURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        //request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: .utf8)
        runDataTask(with: request, completionHandler: { (data, response, error) in
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

extension WebDAVFileProvider: FileProvider {
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = WebDAVFileProvider(baseURL: self.baseURL!, credential: self.credential, cache: self.cache)!
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
}

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
        let fileObject = WebDavFileObject(absoluteURL: href, name: name, path: href.path)
        fileObject.size = Int64(davResponse.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
        fileObject.creationDate = self.resolve(dateString: davResponse.prop["creationdate"] ?? "")
        fileObject.modifiedDate = self.resolve(dateString: davResponse.prop["getlastmodified"] ?? "")
        fileObject.contentType = davResponse.prop["getcontenttype"] ?? "octet/stream"
        fileObject.fileType = fileObject.contentType == "httpd/unix-directory" ? .directory : .regular
        fileObject.entryTag = davResponse.prop["getetag"]
        return fileObject
    }
    
    fileprivate func delegateNotify(_ operation: FileOperationType, error: Error?) {
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
