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
    open var credential: URLCredential? {
        didSet {
            sessionDelegate?.credential = self.credential
        }
    }
    open private(set) var cache: URLCache?
    public var useCache: Bool
    public var validatingCache: Bool
    
    /// Determine either FTP session is in passive or active mode.
    public let passiveMode: Bool
    
    /// Force to use URLSessionDownloadTask/URLSessionDataTask when possible
    public var useAppleImplementation = true
    
    fileprivate var _session: URLSession?
    internal var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        get {
            if _session == nil {
                self.sessionDelegate = SessionDelegate(fileProvider: self)
                let config = URLSessionConfiguration.default
                config.urlCache = cache
                config.requestCachePolicy = .returnCacheDataElseLoad
                _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: self.operation_queue)
                _session?.sessionDescription = UUID().uuidString
                initEmptySessionHandler(_session!.sessionDescription!)
            }
            return _session!
        }
        
        set {
            assert(newValue.delegate is SessionDelegate, "session instances should have a SessionDelegate instance as delegate.")
            _session = newValue
            if session.sessionDescription?.isEmpty ?? true {
                _session?.sessionDescription = UUID().uuidString
            }
            self.sessionDelegate = newValue.delegate as? SessionDelegate
            initEmptySessionHandler(_session!.sessionDescription!)
        }
    }
    
    /**
     Initializer for FTP provider with given username and password.
     
     - Note: `passive` value should be set according to server settings and firewall presence.
     
     - Parameter baseURL: a url with `ftp://hostaddress/` format.
     - Parameter passive: FTP server data connection, `true` means passive connection (data connection created by client)
         and `false` means active connection (data connection created by server). Default is `true` (passive mode).
     - Parameter credential: a `URLCredential` object contains user and password.
     - Parameter cache: A URLCache to cache downloaded files and contents. (unimplemented for FTP and should be nil)
     */
    public init? (baseURL: URL, passive: Bool = true, credential: URLCredential? = nil, cache: URLCache? = nil) {
        guard (baseURL.scheme ?? "ftp").lowercased().hasPrefix("ftp") else { return nil }
        guard baseURL.host != nil else { return nil }
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        urlComponents.port = urlComponents.port ?? 21
        urlComponents.scheme = urlComponents.scheme ?? "ftp"
        
        self.baseURL =  (urlComponents.url!.path.hasSuffix("/") ? urlComponents.url! : urlComponents.url!.appendingPathComponent("")).absoluteURL
        self.passiveMode = passive
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
        self.init(baseURL: baseURL, passive: aDecoder.decodeBool(forKey: "passiveMode"), credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.currentPath     = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
        self.useAppleImplementation = aDecoder.decodeBool(forKey: "useAppleImplementation")
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.credential, forKey: "credential")
        aCoder.encode(self.currentPath, forKey: "currentPath")
        aCoder.encode(self.useCache, forKey: "useCache")
        aCoder.encode(self.validatingCache, forKey: "validatingCache")
        aCoder.encode(self.useAppleImplementation, forKey: "useAppleImplementation")
        aCoder.encode(self.passiveMode, forKey: "passiveMode")
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
        copy.useAppleImplementation = self.useAppleImplementation
        return copy
    }
    
    deinit {
        if let sessionuuid = _session?.sessionDescription {
            removeSessionHandler(for: sessionuuid)
        }
        
        if fileProviderCancelTasksOnInvalidating {
            _session?.invalidateAndCancel()
        } else {
            _session?.finishTasksAndInvalidate()
        }
    }
    
    internal var serverSupportsRFC3659: Bool = true
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping (([FileObject], Error?) -> Void)) {
        self.contentsOfDirectory(path: path, rfc3659enabled: serverSupportsRFC3659, completionHandler: completionHandler)
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter rfc3659enabled: uses MLST command instead of old LIST to get files attributes, default is `true`.
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
            
            self.ftpList(task, of: self.ftpPath(path), useMLST: rfc3659enabled, completionHandler: { (contents, error) in
                defer {
                    self.ftpQuit(task)
                }
                if let error = error {
                    if ((error as NSError).domain == URLError.errorDomain && (error as NSError).code == URLError.unsupportedURL.rawValue) {
                        self.contentsOfDirectory(path: path, rfc3659enabled: false, completionHandler: completionHandler)
                        return
                    }
                    
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
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((FileObject?, Error?) -> Void)) {
        self.attributesOfItem(path: path, rfc3659enabled: serverSupportsRFC3659, completionHandler: completionHandler)
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
                
                guard let response = response, response.hasPrefix("250") || (response.hasPrefix("50") && rfc3659enabled) else {
                    self.dispatch_queue.async {
                        completionHandler(nil, self.throwError(path, code: URLError.badServerResponse))
                    }
                    return
                }
                
                if response.hasPrefix("500") {
                    self.serverSupportsRFC3659 = false
                    self.attributesOfItem(path: path, rfc3659enabled: false, completionHandler: completionHandler)
                }
                
                let lines = response.components(separatedBy: "\n").flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard lines.count > 2 else {
                    self.dispatch_queue.async {
                        completionHandler(nil, self.throwError(path, code: URLError.badServerResponse))
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
        dispatch_queue.async {
            completionHandler(-1, 0)
        }
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        self.recursiveList(path: path, useMLST: true, foundItemsHandler: { items in
            if let foundItemHandler = foundItemHandler {
                for item in items where query.evaluate(with: item.mapPredicate()) {
                    foundItemHandler(item)
                }
            }
        }, completionHandler: {files, error in
            if let error = error {
                completionHandler([], error)
                return
            }
            
            let foundFiles = files.filter { query.evaluate(with: $0.mapPredicate()) }
            completionHandler(foundFiles, nil)
        })
    }
    
    public func url(of path: String?) -> URL {
        let path = (path ?? self.currentPath).trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? (path ?? self.currentPath)
        
        var baseUrlComponent = URLComponents(url: self.baseURL!, resolvingAgainstBaseURL: true)
        baseUrlComponent?.user = credential?.user
        baseUrlComponent?.password = credential?.password
        return URL(string: path, relativeTo: baseUrlComponent?.url ?? baseURL) ?? baseUrlComponent?.url ?? baseURL!
    }
    
    public func relativePathOf(url: URL) -> String {
        // check if url derieved from current base url
        let relativePath = url.relativePath
        if !relativePath.isEmpty, url.baseURL == self.baseURL {
            return (relativePath.removingPercentEncoding ?? relativePath).replacingOccurrences(of: "/", with: "", options: .anchored)
        }
        
        if !relativePath.isEmpty, self.baseURL == self.url(of: "/") {
            return (relativePath.removingPercentEncoding ?? relativePath).replacingOccurrences(of: "/", with: "", options: .anchored)
        }
        
        return relativePath.replacingOccurrences(of: "/", with: "", options: .anchored)
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
    
    open func moveItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.remove(path: path), completionHandler: completionHandler)
    }
    
    fileprivate func doOperation(_ opType: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        guard let sourcePath = opType.source else { return nil }
        let destPath = opType.destination
        
        let command: String
        switch opType {
        case .create:
            command = "MKD \(ftpPath(sourcePath))"
        case .copy:
            command = "SITE CPFR \(ftpPath(sourcePath))\r\nSITE CPTO \(ftpPath(destPath!))"
        case .move:
            command = "RNFR \(ftpPath(sourcePath))\r\nRNTO \(ftpPath(destPath!))"
        case .remove:
            command = "DELE \(ftpPath(sourcePath))"
        case .link:
            command = "SITE SYMLINK \(ftpPath(sourcePath)) \(ftpPath(destPath!))"
        default: // modify, fetch
            return nil
        }
        let operationHandle = RemoteOperationHandle(operationType: opType, tasks: [])
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            self.execute(command: command, on: task, completionHandler: { (response, error) in
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(opType, error: error)
                    }
                    return
                }
                
                guard let response = response else {
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(opType, error: self.throwError(sourcePath, code: URLError.badServerResponse))
                    }
                    return
                }
                
                let codes: [Int] = response.components(separatedBy: .newlines).flatMap({ $0.isEmpty ? nil : $0})
                .flatMap {
                    let code = $0.components(separatedBy: .whitespaces).flatMap({ $0.isEmpty ? nil : $0}).first
                    return code != nil ? Int(code!) : nil
                }
                
                if codes.filter({ (450..<560).contains($0) }).count > 0 {
                    let errorCode: URLError.Code
                    switch opType {
                    case .create:
                        errorCode = URLError.cannotCreateFile
                    case .modify:
                        errorCode = URLError.cannotWriteToFile
                    case .copy:
                        let opHandle = self.fallbackCopy(opType, completionHandler: completionHandler) as? RemoteOperationHandle
                        operationHandle.tasks = opHandle?.tasks ?? []
                        return
                    case .move:
                        errorCode = URLError.cannotMoveFile
                    case .remove:
                        self.fallbackRemove(opType, on: task, completionHandler: completionHandler)
                        return
                    case .link:
                        errorCode = URLError.cannotWriteToFile
                    default:
                        errorCode = URLError.cannotOpenFile
                    }
                    let error = self.throwError(sourcePath, code: errorCode)
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(opType, error: error)
                    }
                    return
                }
                
                self.dispatch_queue.async {
                    completionHandler?(nil)
                    self.delegateNotify(opType, error: nil)
                }
            })
        }
        
        operationHandle.add(task: task)
        return operationHandle
    }
    
    private func fallbackCopy(_ opType: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let sourcePath = opType.source else { return nil }
        guard let destPath = opType.destination else { return nil }
        
        let localURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
        let operationHandle = RemoteOperationHandle(operationType: opType, tasks: [])
        let firstOp = self.copyItem(path: sourcePath, toLocalURL: localURL, completionHandler: { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            let secondOp = self.copyItem(localFile: localURL, to: destPath, completionHandler: { error in
                completionHandler?(nil)
                self.delegateNotify(opType, error: nil)
            }) as? RemoteOperationHandle
            operationHandle.tasks = secondOp?.tasks ?? []
        }) as? RemoteOperationHandle
        operationHandle.tasks = firstOp?.tasks ?? []
        return operationHandle
    }
    
    private func fallbackRemove(_ opType: FileOperationType, on task: FileProviderStreamTask, completionHandler: SimpleCompletionHandler) {
        guard let sourcePath = opType.source else { return }
        
        self.execute(command: "SITE RMDIR \(ftpPath(sourcePath))", on: task) { (response, error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            guard let response = response else {
                let error = self.throwError(sourcePath, code: URLError.badServerResponse)
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            if response.hasPrefix("50") {
                self.fallbackRecursiveRemove(opType, on: task, completionHandler: completionHandler)
                return
            }
            
            var error: Error?
            if !response.hasPrefix("2") {
                error = self.throwError(sourcePath, code: URLError.cannotRemoveFile)
            }
            self.dispatch_queue.async {
                completionHandler?(error)
                self.delegateNotify(opType, error: error)
            }
        }
    }
    
    private func fallbackRecursiveRemove(_ opType: FileOperationType, on task: FileProviderStreamTask, completionHandler: SimpleCompletionHandler) {
        guard let sourcePath = opType.source else { return }
        
        self.recursiveList(path: sourcePath, useMLST: true, completionHandler: { (contents, error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            let sortedContents = contents.sorted(by: {
                $0.path.localizedStandardCompare($1.path) == .orderedDescending
            })
            var command = ""
            for file in sortedContents {
                command += (file.isDirectory ? "RMD \(self.ftpPath(file.path))" : "DELE \(self.ftpPath(file.path))") + "\r\n"
            }
            command += "RMD \(self.ftpPath(sourcePath))"
            
            self.execute(command: command, on: task, completionHandler: { (response, error) in
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                // TODO: Digest response
            })
        })
    }
    
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // check file is not a folder
        guard (try? localFile.resourceValues(forKeys: [.fileResourceTypeKey]))?.fileResourceType ?? .unknown == .regular else {
            dispatch_queue.async {
                completionHandler?(self.throwError(localFile.path, code: URLError.fileIsDirectory))
            }
            return nil
        }
        
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let operation = RemoteOperationHandle(operationType: opType, tasks: [])
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            self.ftpStore(task, filePath: self.ftpPath(toPath), fromData: nil, fromFile: localFile, onTask: {
                operation.add(task: $0)
            }, onProgress: { bytesSent, totalSent, expectedBytes in
                DispatchQueue.main.async {
                    self.delegate?.fileproviderProgress(self, operation: opType, progress: Float(Double(totalSent) / Double(expectedBytes)))
                }
            }, completionHandler: { (error) in
                self.ftpQuit(task)
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
            })
        }
        
        return operation
    }
    
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let operation = RemoteOperationHandle(operationType: opType, tasks: [])
        
        if self.useAppleImplementation {
            self.attributesOfItem(path: path, completionHandler: { (file, error) in
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(opType, error: error)
                    }
                    return
                }
                
                if file?.isDirectory ?? false {
                    self.dispatch_queue.async {
                        let error = self.throwError(path, code: URLError.fileIsDirectory)
                        completionHandler?(error)
                        self.delegateNotify(opType, error: error)
                    }
                    return
                }
                
                let task = self.session.downloadTask(with: self.url(of: path))
                completionHandlersForTasks[self.session.sessionDescription!]?[task.taskIdentifier] = completionHandler
                downloadCompletionHandlersForTasks[self.session.sessionDescription!]?[task.taskIdentifier] = { tempURL in
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destURL)
                        completionHandler?(nil)
                    } catch let e {
                        completionHandler?(e)
                    }
                }
                operation.add(task: task)
                task.taskDescription = opType.json
                task.resume()
            })
        } else {
            let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
            self.ftpLogin(task) { (error) in
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler?(error)
                    }
                    return
                }
                
                self.ftpRetrieveFile(task, filePath: self.ftpPath(path), onTask: {
                    operation.add(task: $0)
                }, onProgress: { recevied, totalReceived, totalSize in
                    let progress = Double(totalReceived) / Double(totalSize)
                    self.delegate?.fileproviderProgress(self, operation: opType, progress: Float(progress))
                }) { (tmpurl, error) in
                    if let error = error {
                        self.dispatch_queue.async {
                            completionHandler?(error)
                            self.delegateNotify(opType, error: error)
                        }
                        return
                    }
                    
                    if let tmpurl = tmpurl {
                        try? FileManager.default.moveItem(at: tmpurl, to: destURL)
                        self.dispatch_queue.async {
                            completionHandler?(nil)
                            self.delegateNotify(opType, error: nil)
                        }
                    }
                }
            }
        }
        return operation
    }
}

extension FTPFileProvider: FileProviderReadWrite {
    open func contents(path: String, completionHandler: @escaping ((Data?, Error?) -> Void)) -> OperationHandle? {
        let opType = FileOperationType.fetch(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        
        if self.useAppleImplementation {
            let task = session.downloadTask(with: url(of: path))
            completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { error in
                completionHandler(nil, error)
            }
            downloadCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { tempURL in
                do {
                    let data = try Data(contentsOf: tempURL)
                    completionHandler(data, nil)
                } catch let e {
                    completionHandler(nil, e)
                }
            }
            task.taskDescription = opType.json
            task.resume()
            return RemoteOperationHandle(operationType: opType, tasks: [task])
        } else {
            return self.contents(path: path, offset: 0, length: -1, completionHandler: completionHandler)
        }
    }
    
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let opType = FileOperationType.fetch(path: path)
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
                self.delegateNotify(opType, error: nil)
            }
            return nil
        }
        let operation = RemoteOperationHandle(operationType: opType, tasks: [])
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                return
            }
            
            self.ftpRetrieveData(task, filePath: self.ftpPath(path), from: offset, length: length, onTask: {
                operation.add(task: $0)
            }, onProgress: { recevied, totalReceived, totalSize in
                let progress = Double(totalReceived) / Double(totalSize)
                self.delegate?.fileproviderProgress(self, operation: opType, progress: Float(progress))
            }) { (data, error) in
                if let error = error {
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                        self.delegateNotify(opType, error: error)
                    }
                    return
                }
                
                if let data = data {
                    self.dispatch_queue.async {
                        completionHandler(data, nil)
                        self.delegateNotify(opType, error: nil)
                    }
                }
            }
        }
        
        return operation
    }
    
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        
        let operation = RemoteOperationHandle(operationType: opType, tasks: [])
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(opType, error: error)
                }
                return
            }
            
            let storeHandler = {
                self.ftpStore(task, filePath: self.ftpPath(path), fromData: data ?? Data(), fromFile: nil, onTask: {
                    operation.add(task: $0)
                }, onProgress: { bytesSent, totalSent, expectedBytes in
                    DispatchQueue.main.async {
                        self.delegate?.fileproviderProgress(self, operation: opType, progress: Float(Double(totalSent) / Double(expectedBytes)))
                    }
                }, completionHandler: { (error) in
                    self.ftpQuit(task)
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(opType, error: error)
                    }
                })
            }
            
            if overwrite {
                storeHandler()
            } else {
                self.attributesOfItem(path: path, completionHandler: { (file, erroe) in
                    if file == nil {
                        storeHandler()
                    }
                })
            }
        }
        
        return operation
    }
}

public extension FTPFileProvider {
    /**
     Creates a symbolic link at the specified path that points to an item at the given path.
     This method does not traverse symbolic links contained in destination path, making it possible
     to create symbolic links to locations that do not yet exist.
     Also, if the final path component is a symbolic link, that link is not followed.
     
     - Note: Many servers does't support this functionality.
     
     - Parameters:
       - symbolicLink: The file path at which to create the new symbolic link. The last component of the path issued as the name of the link.
       - withDestinationPath: The path that contains the item to be pointed to by the link. In other words, this is the destination of the link.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     */
    public func create(symbolicLink path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        let opType = FileOperationType.link(link: path, target: destPath)
        _=self.doOperation(opType, completionHandler: completionHandler)
    }
}

extension FTPFileProvider: FileProvider { }
