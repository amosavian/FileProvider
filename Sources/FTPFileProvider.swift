//
//  FTPFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

/**
 Allows accessing to FTP files and directories. This provider doesn't cache or save files internally.
 It's a complete reimplementation and doesn't use CFNetwork deprecated API.
 */
open class FTPFileProvider: FileProviderBasicRemote {
    open class var type: String { return "FTP" }
    open let baseURL: URL?
    open var currentPath: String
    
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    
    open weak var delegate: FileProviderDelegate?
    open var credential: URLCredential?
    open private(set) var cache: URLCache?
    public var useCache: Bool
    public var validatingCache: Bool
    
    public let passiveMode = true // TODO: Implement active mode
    
    fileprivate var _session: URLSession?
    internal var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        if _session == nil {
            self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
            let config = URLSessionConfiguration.default
            config.urlCache = cache
            config.requestCachePolicy = .returnCacheDataElseLoad
            _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: self.operation_queue)
        }
        return _session!
    }
    
    /**
     Initializer for FTP provider with given username and password.
     
     - Parameter baseURL: a url with `ftp://hostaddress/` format.
     - Parameter credential: a `URLCredential` object contains user and password.
     - Parameter cache: A URLCache to cache downloaded files and contents. (unimplemented for FTP and should be nil)
     */
    public init? (baseURL: URL, credential: URLCredential?, cache: URLCache? = nil) {
        guard (baseURL.scheme ?? "ftp").lowercased() == "ftp" else { return nil }
        guard baseURL.host != nil else { return nil }
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        urlComponents.port = urlComponents.port ?? 21
        
        self.baseURL = urlComponents.url!
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: [])
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(forKey: "baseURL") as? URL else { return nil }
        self.init(baseURL: baseURL, credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.currentPath     = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.credential, forKey: "credential")
        aCoder.encode(self.currentPath, forKey: "currentPath")
        aCoder.encode(self.useCache, forKey: "useCache")
        aCoder.encode(self.validatingCache, forKey: "validatingCache")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = FTPFileProvider(baseURL: self.baseURL!, credential: self.credential, cache: self.cache)!
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
        self.contentsOfDirectory(path: path, rfc3659enabled: true, completionHandler: completionHandler)
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter rfc3659enabled: uses MLST command instead of old LIST to get files attributes, default is true.
     - Parameter completionHandler: a closure with result of directory entries or error.
         `contents`: An array of `FileObject` identifying the the directory entries.
         `error`: Error returned by system.
     */
    
    open func contentsOfDirectory(path apath: String, rfc3659enabled: Bool , completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        let path = ftpPath(apath)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler([], error)
                }
                return
            }
            
            self.ftpList(task, of: path, useMLST: rfc3659enabled, completionHandler: { (contents, error) in
                defer {
                    self.ftpQuit(task)
                }
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler([], error)
                    }
                    return
                }
                
                
                let files: [FileObject] = contents.flatMap {
                    rfc3659enabled ? self.parseMLST($0, in: path) : self.parseUnixList($0, in: path)
                }
                
                self.dispatch_queue.async {
                    completionHandler(files, nil)
                }
            })
        }
    }
    
    public func attributesOfItem(path: String, completionHandler: @escaping ((FileObject?, Error?) -> Void)) {
        self.attributesOfItem(path: path, rfc3659enabled: true, completionHandler: completionHandler)
    }
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter rfc3659enabled: uses MLST command instead of old LIST to get files attributes, default is true.
     - Parameter completionHandler: a closure with result of directory entries or error.
         `attributes`: A `FileObject` containing the attributes of the item.
         `error`: Error returned by system.
     */
    open func attributesOfItem(path apath: String, rfc3659enabled: Bool, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        let path = ftpPath(apath)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                return
            }
            
            let command = rfc3659enabled ? "MLST \(path)" : "LIST \(path)"
            self.execute(command: command, on: task, completionHandler: { (response, error) in
                defer {
                    self.ftpQuit(task)
                }
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                    }
                    return
                }
                
                guard let response = response, response.hasPrefix("250") else {
                    let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                    }
                    return
                }
                
                let lines = response.components(separatedBy: "\n").flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard lines.count > 2 else {
                    let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                    }
                    return
                }
                let file = rfc3659enabled ? self.parseMLST(lines[1], in: path) : self.parseUnixList(lines[1], in: path)
                self.dispatch_queue.async {
                    completionHandler(file, nil)
                }
            })
        }
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        // TODO: implement SITE CPFR/CPTO extension
        dispatch_queue.async {
            completionHandler(-1, 0)
        }
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        NotImplemented()
    }
    
    open func isReachable(completionHandler: @escaping (Bool) -> Void) {
        self.attributesOfItem(path: "/") { (file, error) in
            completionHandler(file != nil)
        }
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension FTPFileProvider: FileProviderOperations {
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let path = (atPath as NSString).appendingPathComponent(folderName) + "/"
        return doOperation(.create(path: path), completionHandler: completionHandler)
    }
    
    open func create(file fileName: String, at path: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let filePath = (path as NSString).appendingPathComponent(fileName)
        return self.writeContents(path: filePath, contents: data ?? Data(), completionHandler: completionHandler)
    }
    
    open func moveItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.remove(path: path), completionHandler: completionHandler)
    }
    
    fileprivate func doOperation(_ operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let command: String
        guard let sourcePath = operation.source else { return nil }
        let destPath = operation.destination
        switch operation {
        case .create:
            command = "MKD \(ftpPath(sourcePath))"
        case .copy:
            // FTP doesn't support copy command Intrinsically, a dirty workaround is
            // to download file and upload again!
            // TODO: implement SITE CPFR/CPTO extension and use dirty workaround as fallback
            NotImplemented()
            command = ""
        case .move:
            command = "RNFR \(ftpPath(sourcePath))\r\nRNTO \(ftpPath(destPath!))"
        case .remove:
            command = "DELE \(ftpPath(sourcePath))"
            // TODO: Remove folder using SITE RMDIR and recursive as fallback
        case .link:
            command = "SITE SYMLINK \(ftpPath(sourcePath)) \(ftpPath(destPath!))"
        default: // modify, link, fetch
            return nil
        }
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                return
            }
            
            self.execute(command: command, on: task, completionHandler: { (response, error) in
                //TODO : Implement return code error return
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
            })
        }
        
        return RemoteOperationHandle(operationType: operation, tasks: [])
    }
    
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                return
            }
            
            let path = self.ftpPath(toPath)
            self.ftpStore(task, filePath: path, fromData: nil, fromFile: localFile, completionHandler: { (error) in
                self.ftpQuit(task)
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
            })
        }
        
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        
        guard let url = URL(string: path, relativeTo: baseURL!) else {
            self.dispatch_queue.async {
                let error = NSError(domain: URLError.errorDomain, code: URLError.unsupportedURL.rawValue, userInfo: nil)
                completionHandler?(error)
            }
            return nil
        }
        let task = session.downloadTask(with: url) { (tempDest, response, error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                return
            }
            
            if let tempDest = tempDest {
                do {
                    try FileManager.default.moveItem(at: tempDest, to: destURL)
                    self.dispatch_queue.async {
                        completionHandler?(nil)
                    }
                } catch let error {
                    self.dispatch_queue.async {
                        completionHandler?(error)
                    }
                }
            }
        }
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
}

extension FTPFileProvider: FileProviderReadWrite {
    public func contents(path: String, completionHandler: @escaping ((Data?, Error?) -> Void)) -> OperationHandle? {
        let opType = FileOperationType.fetch(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        
        var baseUrlComponent = URLComponents(url: self.baseURL!, resolvingAgainstBaseURL: true)
        baseUrlComponent?.user = credential?.user
        baseUrlComponent?.password = credential?.password
        guard let baseURL = baseUrlComponent?.url else {
            let error = NSError(domain: URLError.errorDomain, code: URLError.badURL.rawValue, userInfo: nil)
            self.dispatch_queue.async {
                completionHandler(nil, error)
            }
            return nil
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            self.dispatch_queue.async {
                let error = NSError(domain: URLError.errorDomain, code: URLError.unsupportedURL.rawValue, userInfo: nil)
                completionHandler(nil, error)
            }
            return nil
        }
        let task = session.dataTask(with: url) { (data, response, error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                return
            }
            
            if let data = data {
                self.dispatch_queue.async {
                    completionHandler(data, nil)
                }
            }
        }
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    open func contents(path apath: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
            }
            return nil
        }
        let path = ftpPath(apath)
        let opType = FileOperationType.fetch(path: path)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                return
            }
            
            self.ftpRetrieve(task, filePath: path, from: offset, length: length, completionHandler: { (data, error) in
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                    }
                    return
                }
                
                if let data = data {
                    self.dispatch_queue.async {
                        completionHandler(data, nil)
                    }
                }
            })
        }
        
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    public func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                return
            }
            
            self.ftpStore(task, filePath: path, fromData: data, fromFile: nil, completionHandler: { (error) in
                self.ftpQuit(task)
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
            })
        }
        
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    /*
     fileprivate func registerNotifcation(path: String, eventHandler: (() -> Void)) {
     /* 
      * There is no ways to monitor folders changing in FTP.
     */
     NotImplemented()
     }
     fileprivate func unregisterNotifcation(path: String) {
     NotImplemented()
     }
     */
}

extension FTPFileProvider {
    /**
     Creates a symbolic link at the specified path that points to an item at the given path.
     This method does not traverse symbolic links contained in destURL, making it possible
     to create symbolic links to locations that do not yet exist.
     Also, if the final path component in url is a symbolic link, that link is not followed.
     
     - Parameters:
       - path: The file path at which to create the new symbolic link. The last component of the path issued as the name of the link.
       - destPath: The path that contains the item to be pointed to by the link. In other words, this is the destination of the link.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     */
    public func create(symbolicLink path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        let opType = FileOperationType.link(link: path, target: destPath)
        _=self.doOperation(opType, completionHandler: completionHandler)
    }
}

extension FTPFileProvider: FileProvider { }
