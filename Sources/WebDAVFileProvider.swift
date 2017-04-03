//
//  WebDAVFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/**
 Allows accessing to WebDAV server files. This provider doesn't cache or save files internally, however you can
 set `useCache` and `cache` properties to use Foundation `NSURLCache` system.
 
 WebDAV system supported by many cloud services including [Box.net](https://www.box.com/home) 
 and [Yandex disk](https://disk.yandex.com) and [ownCloud](https://owncloud.org).
 
 - Important: Because this class uses `URLSession`, it's necessary to disable App Transport Security
     in case of using this class with unencrypted HTTP connection.
     [Read this to know how](http://iosdevtips.co/post/121756573323/ios-9-xcode-7-http-connect-server-error).
*/
open class WebDAVFileProvider: FileProviderBasicRemote {
    open class var type: String { return "WebDAV" }
    open let baseURL: URL?
    open var currentPath: String
    
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    
    public weak var delegate: FileProviderDelegate?
    open var credential: URLCredential? {
        didSet {
            sessionDelegate?.credential = credential
        }
    }
    open private(set) var cache: URLCache?
    public var useCache: Bool
    public var validatingCache: Bool
    
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
    
    /**
     Initializes WebDAV provider.
     
     - Parameters:
       - baseURL: Location of WebDAV server.
       - credential: An `URLCredential` object with `user` and `password`.
       - cache: A URLCache to cache downloaded files and contents.
    */
    public init? (baseURL: URL, credential: URLCredential?, cache: URLCache? = nil) {
        if  !["http", "https"].contains(baseURL.uw_scheme.lowercased()) {
            return nil
        }
        self.baseURL = (baseURL.path.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")).absoluteURL
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(forKey: "baseURL") as? URL else {
            return nil
        }
        self.init(baseURL: baseURL,
                  credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.currentPath   = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    open func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.credential, forKey: "credential")
        aCoder.encode(self.currentPath, forKey: "currentPath")
        aCoder.encode(self.useCache, forKey: "isCoorinating")
        aCoder.encode(self.validatingCache, forKey: "undoManager")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = WebDAVFileProvider(baseURL: self.baseURL!, credential: self.credential, cache: self.cache)!
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    deinit {
        if fileProviderCancelTasksOnInvalidating {
            _session?.invalidateAndCancel()
        } else {
            _session?.finishTasksAndInvalidate()
        }
    }
    
    public func contentsOfDirectory(path: String, completionHandler: @escaping (([FileObject], Error?) -> Void)) {
        self.contentsOfDirectory(path: path, including: [], completionHandler: completionHandler)
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter including: An array which determines which file properties should be considered to fetch.
     - Parameter completionHandler: a closure with result of directory entries or error.
         - `contents`: An array of `FileObject` identifying the the directory entries.
         - `error`: Error returned by system.
     */
    open func contentsOfDirectory(path: String, including: [URLResourceKey], completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        let opType = FileOperationType.fetch(path: path)
        let url = self.url(of: path).appendingPathComponent("")
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n\(WebDavFileObject.propString(including))\n</D:propfind>".data(using: .utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        runDataTask(with: request, operationHandle: RemoteOperationHandle(operationType: opType, tasks: []), completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8), url: url)
            }
            var fileObjects = [WebDavFileObject]()
            if let data = data {
                let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                for attr in xresponse where attr.href != url {
                    if attr.href.path == url.path {
                        continue
                    }
                    fileObjects.append(WebDavFileObject(attr))
                }
            }
            completionHandler(fileObjects, responseError ?? error)
        })
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        self.attributesOfItem(path: path, including: [], completionHandler: completionHandler)
    }
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter including: An array which determines which file properties should be considered to fetch.
     - Parameter completionHandler: a closure with result of directory entries or error.
         - `attributes`: A `FileObject` containing the attributes of the item.
         - `error`: Error returned by system.
     */
    open func attributesOfItem(path: String, including: [URLResourceKey], completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n\(WebDavFileObject.propString(including))\n</D:propfind>".data(using: .utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        runDataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode, code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8), url: url)
            }
            if let data = data {
                let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                if let attr = xresponse.first {
                    completionHandler(WebDavFileObject(attr), responseError ?? error)
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
                let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                if let attr = xresponse.first {
                    totalSize = Int64(attr.prop["quota-available-bytes"] ?? "") ?? -1
                    usedSize = Int64(attr.prop["quota-used-bytes"] ?? "") ?? 0
                }
            }
            completionHandler(totalSize, usedSize)
        })
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        //request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:allprop/></D:propfind>".data(using: .utf8)
        runDataTask(with: request, completionHandler: { (data, response, error) in
            // FIXME: paginating results
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8), url: url)
            }
            if let data = data {
                let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                var fileObjects = [WebDavFileObject]()
                for attr in xresponse {
                    let fileObject = WebDavFileObject(attr)
                    if !query.evaluate(with: fileObject.mapPredicate()) {
                        continue
                    }
                    
                    fileObjects.append(fileObject)
                    foundItemHandler?(fileObject)
                }
                completionHandler(fileObjects, responseError ?? error)
                return
            }
            completionHandler([], responseError ?? error)
        })
    }
    
    open func isReachable(completionHandler: @escaping (Bool) -> Void) {
        var request = URLRequest(url: baseURL!)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n<D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop>\n</D:propfind>".data(using: .utf8)
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        runDataTask(with: request, completionHandler: { (data, response, error) in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            completionHandler(status < 300)
        })
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension WebDAVFileProvider: FileProviderOperations {
    @discardableResult
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.create(path: (atPath as NSString).appendingPathComponent(folderName) + "/")
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = self.url(of: atPath).appendingPathComponent(folderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderName, isDirectory: true)
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, path: url.relativePath, errorDescription: String(data: data ?? Data(), encoding: .utf8), url: url)
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(opType, error: responseError ?? error)
        })
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.move(source: path, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return self.doOperation(operation: opType, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return self.doOperation(operation: opType, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.remove(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return self.doOperation(operation: opType, completionHandler: completionHandler)
    }
    
    func doOperation(operation opType: FileOperationType, overwrite: Bool? = nil, completionHandler: SimpleCompletionHandler) -> OperationHandle?  {
        let source = opType.source!
        let sourceURL = self.url(of: source)
        var request = URLRequest(url: sourceURL)
        if let dest = opType.destination {
            request.setValue(url(of:dest).absoluteString, forHTTPHeaderField: "Destination")
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
                    responseError = FileProviderWebDavError(code: code, path: source, errorDescription: String(data: data ?? Data(), encoding: .utf8), url: sourceURL)
                }
                if code == .multiStatus, let data = data {
                    let xresponses = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                    for xresponse in xresponses where (xresponse.status ?? 0) >= 300 {
                        let error = FileProviderWebDavError(code: code, path: source, errorDescription: String(data: data, encoding: .utf8), url: sourceURL)
                        completionHandler?(error)
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
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = self.url(of:toPath)
        var request = URLRequest(url: url)
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        request.httpMethod = "PUT"
        let task = session.uploadTask(with: request, fromFile: localFile)
        completionHandlersForTasks[task.taskIdentifier] = { [weak self] error in
            var responseError: FileProviderWebDavError?
            if let code = (task.response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                // We can't fetch server result from delegate!
                responseError = FileProviderWebDavError(code: rCode, path: toPath, errorDescription: nil, url: url)
            }
            completionHandler?(responseError ?? error)
            self?.delegateNotify(.create(path: toPath), error: responseError ?? error)
        }
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = self.url(of:path)
        let request = URLRequest(url: url)
        let task = session.downloadTask(with: request)
        completionHandlersForTasks[task.taskIdentifier] = completionHandler
        downloadCompletionHandlersForTasks[task.taskIdentifier] = { tempURL in
            guard let httpResponse = task.response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (task.response as? HTTPURLResponse)?.statusCode ?? -1)
                let serverError : FileProviderWebDavError? = code != nil ? FileProviderWebDavError(code: code!, path: path, errorDescription: code?.description, url: url) : nil
                completionHandler?(serverError)
                return
            }
            do {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                completionHandler?(nil)
            } catch let e {
                completionHandler?(e)
            }
        }
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
}

extension WebDAVFileProvider: FileProviderReadWrite {
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
            }
            return nil
        }
        
        let opType = FileOperationType.fetch(path: path)
        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let handle = RemoteOperationHandle(operationType: opType, tasks: [])
        runDataTask(with: request, operationHandle: handle, completionHandler: { (data, response, error) in
            var responseError: FileProviderWebDavError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderWebDavError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8), url: url)
            }
            completionHandler(data, responseError ?? error)
        })
        return handle
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        // FIXME: lock destination before writing process
        let url = atomically ? self.url(of: path).appendingPathExtension("tmp") : self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if !overwrite {
            request.setValue("F", forHTTPHeaderField: "Overwrite")
        }
        let task = session.uploadTask(with: request, from: data ?? Data())
        completionHandlersForTasks[task.taskIdentifier] = { [weak self] error in
            var responseError: FileProviderWebDavError?
            if let code = (task.response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                // We can't fetch server result from delegate!
                responseError = FileProviderWebDavError(code: rCode, path: path, errorDescription: nil, url: url)
            }
            completionHandler?(responseError ?? error)
            self?.delegateNotify(.create(path: path), error: responseError ?? error)
        }
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    /*
    fileprivate func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is no unified api for monitoring WebDAV server content change/update
         * Microsoft Exchange uses SUBSCRIBE method, Apple uses push notification system.
         * while both is unavailable in a mobile platform.
         * A messy approach is listing a directory with an interval period and compare
         * with previous results
         */
        NotImplemented()
    }
    fileprivate func unregisterNotifcation(path: String) {
        NotImplemented()
    }*/
    // TODO: implements methods for lock mechanism
}

extension WebDAVFileProvider: FileProvider { }

// MARK: WEBDAV XML response implementation

internal extension WebDAVFileProvider {
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

struct DavResponse {
    let href: URL
    let hrefString: String
    let status: Int?
    let prop: [String: String]
    
    init? (_ node: AEXMLElement, baseURL: URL?) {
        
        func standardizePath(_ str: String) -> String {
            let trimmedStr = str.hasPrefix("/") ? str.substring(from: str.index(after: str.startIndex)) : str
            return trimmedStr.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? str
        }
        
        // find node names with namespace
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
        
        guard let hrefString = node[hreftag].value else { return nil }
        
        // trying to figure out relative path out of href
        let hrefAbsolute = URL(string: hrefString, relativeTo: baseURL)?.absoluteURL
        let relativePath: String
        if hrefAbsolute?.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) == baseURL?.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) {
            relativePath = hrefAbsolute?.path.replacingOccurrences(of: baseURL?.absoluteURL.path ?? "", with: "", options: .anchored, range: nil) ?? hrefString
        } else {
            relativePath = hrefAbsolute?.absoluteString.replacingOccurrences(of: baseURL?.absoluteString ?? "", with: "", options: .anchored, range: nil) ?? hrefString
        }
        let hrefURL = URL(string: standardizePath(relativePath), relativeTo: baseURL) ?? baseURL
        
        guard let href = hrefURL?.standardized else { return nil }
        
        // reading status and properties
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
        self.href = href
        self.hrefString = hrefString
        self.status = status
        self.prop = propDic
    }
    
    static func parse(xmlResponse: Data, baseURL: URL?) -> [DavResponse] {
        guard let xml = try? AEXMLDocument(xml: xmlResponse) else { return [] }
        var result = [DavResponse]()
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
            if let davResponse = DavResponse(responseNode, baseURL: baseURL) {
                result.append(davResponse)
            }
        }
        return result
    }
}

/// Containts path, url and attributes of a WebDAV file or resource.
public final class WebDavFileObject: FileObject {
    internal init(_ davResponse: DavResponse) {
        let href = davResponse.href
        let name = davResponse.prop["displayname"] ?? davResponse.href.lastPathComponent
        let relativePath = href.relativePath
        let path = relativePath.hasPrefix("/") ? relativePath : ("/" + relativePath)
        super.init(url: href, name: name, path: path)
        self.size = Int64(davResponse.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
        self.creationDate = Date(rfcString: davResponse.prop["creationdate"] ?? "")
        self.modifiedDate = Date(rfcString: davResponse.prop["getlastmodified"] ?? "")
        self.contentType = davResponse.prop["getcontenttype"] ?? "octet/stream"
        self.isHidden = (Int(davResponse.prop["ishidden"] ?? "0") ?? 0) > 0
        self.type = self.contentType == "httpd/unix-directory" ? .directory : .regular
        self.entryTag = davResponse.prop["getetag"]
    }
    
    /// MIME type of the file.
    open internal(set) var contentType: String {
        get {
            return allValues[.mimeType] as? String ?? ""
        }
        set {
            allValues[.mimeType] = newValue
        }
    }
    
    /// HTTP E-Tag, can be used to mark changed files.
    open internal(set) var entryTag: String? {
        get {
            return allValues[.entryTag] as? String
        }
        set {
            allValues[.entryTag] = newValue
        }
    }
    
    internal class func resourceKeyToDAVProp(_ key: URLResourceKey) -> String? {
        switch key {
        case URLResourceKey.fileSizeKey:
            return "getcontentlength"
        case URLResourceKey.creationDateKey:
            return "creationdate"
        case URLResourceKey.contentModificationDateKey:
            return "getlastmodified"
        case URLResourceKey.fileResourceTypeKey, URLResourceKey.mimeType:
            return "getcontenttype"
        case URLResourceKey.isHiddenKey:
            return "ishidden"
        case URLResourceKey.entryTag:
            return "getetag"
        default:
            return nil
        }
    }
    
    internal class func propString(_ keys: [URLResourceKey]) -> String {
        var propKeys = ""
        for item in keys {
            if let prop = WebDavFileObject.resourceKeyToDAVProp(item) {
                propKeys += "<D:prop><D:\(prop)/></D:prop>"
            }
        }
        if propKeys.isEmpty {
            propKeys = "<D:allprop/>"
        }
        return propKeys
    }
}

/// Error returned by WebDAV server when trying to access or do operations on a file or folder.
public struct FileProviderWebDavError: FileProviderHTTPError {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let errorDescription: String?
    /// URL of resource caused error.
    public let url: URL
}
