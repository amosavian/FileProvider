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
open class FTPFileProvider: FileProviderBasicRemote, FileProviderOperations, FileProviderReadWrite {
    
    /// FTP data connection mode.
    public enum Mode: String {
        /// Passive mode for FTP and Extended Passive mode for FTP over TLS.
        case `default`
        /// Data connection would establish by client to determined server host/port.
        case passive
        /// Data connection would establish by server to determined client's port.
        case active
        /// Data connection would establish by client to determined server host/port, with IPv6 support. (RFC 2428)
        case extendedPassive
    }
    
    open class var type: String { return "FTP" }
    open let baseURL: URL?
    
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
    public let mode: Mode
    
    fileprivate var _session: URLSession!
    internal var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        get {
            if _session == nil {
                self.sessionDelegate = SessionDelegate(fileProvider: self)
                let config = URLSessionConfiguration.default
                _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: self.operation_queue)
                _session.sessionDescription = UUID().uuidString
                initEmptySessionHandler(_session.sessionDescription!)
            }
            return _session
        }
        
        set {
            assert(newValue.delegate is SessionDelegate, "session instances should have a SessionDelegate instance as delegate.")
            _session = newValue
            if _session.sessionDescription?.isEmpty ?? true {
                _session.sessionDescription = UUID().uuidString
            }
            self.sessionDelegate = newValue.delegate as? SessionDelegate
            initEmptySessionHandler(_session.sessionDescription!)
        }
    }
    
    /**
     Initializer for FTP provider with given username and password.
     
     - Note: `passive` value should be set according to server settings and firewall presence.
     
     - Parameter baseURL: a url with `ftp://hostaddress/` format.
     - Parameter mode: FTP server data connection type.
     - Parameter credential: a `URLCredential` object contains user and password.
     - Parameter cache: A URLCache to cache downloaded files and contents. (unimplemented for FTP and should be nil)
     
     - Important: Extended Passive or Active modes will fallback to normal Passive or Active modes if your server
         does not support extended modes.
     */
    public init? (baseURL: URL, mode: Mode = .default, credential: URLCredential? = nil, cache: URLCache? = nil) {
        guard ["ftp", "ftps", "ftpes"].contains(baseURL.uw_scheme.lowercased()) else {
            return nil
        }
        guard baseURL.host != nil else { return nil }
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        let defaultPort: Int = baseURL.scheme?.lowercased() == "ftps" ? 990 : 21
        urlComponents.port = urlComponents.port ?? defaultPort
        urlComponents.scheme = urlComponents.scheme ?? "ftp"
        urlComponents.path = urlComponents.path.hasSuffix("/") ? urlComponents.path : urlComponents.path + "/"
        
        self.baseURL =  urlComponents.url!.absoluteURL
        self.mode = mode
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        self.supportsRFC3659 = true
        
        #if swift(>=3.1)
        let queueLabel = "FileProvider.\(Swift.type(of: self).type)"
        #else
        let queueLabel = "FileProvider.\(type(of: self).type)"
        #endif
        dispatch_queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "\(queueLabel).Operation"
    }
    
    /**
     **DEPRECATED** Initializer for FTP provider with given username and password.
     
     - Note: `passive` value should be set according to server settings and firewall presence.
     
     - Parameter baseURL: a url with `ftp://hostaddress/` format.
     - Parameter passive: FTP server data connection, `true` means passive connection (data connection created by client)
     and `false` means active connection (data connection created by server). Default is `true` (passive mode).
     - Parameter credential: a `URLCredential` object contains user and password.
     - Parameter cache: A URLCache to cache downloaded files and contents. (unimplemented for FTP and should be nil)
     */
    @available(*, deprecated, renamed: "init(baseURL:mode:credential:cache:)")
    public convenience init? (baseURL: URL, passive: Bool, credential: URLCredential? = nil, cache: URLCache? = nil) {
        self.init(baseURL: baseURL, mode: passive ? .passive : .active, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(forKey: "baseURL") as? URL else { return nil }
        let mode: Mode
        if let modeStr = aDecoder.decodeObject(forKey: "mode") as? String, let mode_v = Mode(rawValue: modeStr) {
            mode = mode_v
        } else {
            let passiveMode = aDecoder.decodeBool(forKey: "passiveMode")
            mode = passiveMode ? .passive : .active
        }
        self.init(baseURL: baseURL, mode: mode, credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.useCache              = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache       = aDecoder.decodeBool(forKey: "validatingCache")
        self.supportsRFC3659       = aDecoder.decodeBool(forKey: "supportsRFC3659")
        self.securedDataConnection = aDecoder.decodeBool(forKey: "securedDataConnection")
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.credential, forKey: "credential")
        aCoder.encode(self.useCache, forKey: "useCache")
        aCoder.encode(self.validatingCache, forKey: "validatingCache")
        aCoder.encode(self.mode.rawValue, forKey: "mode")
        aCoder.encode(self.supportsRFC3659, forKey: "supportsRFC3659")
        aCoder.encode(self.securedDataConnection, forKey: "securedDataConnection")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = FTPFileProvider(baseURL: self.baseURL!, mode: self.mode, credential: self.credential, cache: self.cache)!
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        copy.securedDataConnection = self.securedDataConnection
        copy.supportsRFC3659 = self.supportsRFC3659
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
    
    internal var supportsRFC3659: Bool
    
    /**
     Uploads files in chunk if `true`, Otherwise It will uploads entire file/data as single stream.
     
     - Note: Due to an internal bug in `NSURLSessionStreamTask`, it must be `true` when using Apple's stream task,
         otherwise it will occasionally throw `Assertion failed: (_writeBufferAlreadyWrittenForNextWrite == 0)`
         fatal error. My implementation of `FileProviderStreamTask` doesn't have this bug.
     
     - Note: Disabling this option will increase upload speed.
    */
    public var uploadByREST: Bool = FileProviderStreamTask.defaultUseURLSession
    
    /**
     Determines data connection must TLS or not. `false` value indicates to use `PROT C` and
     `true` value indicates to use `PROT P`. Default is `true`.
    */
    public var securedDataConnection: Bool = true
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ([FileObject], Error?) -> Void) {
        self.contentsOfDirectory(path: path, rfc3659enabled: supportsRFC3659, completionHandler: completionHandler)
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, root will be iterated.
     - Parameter rfc3659enabled: uses MLST command instead of old LIST to get files attributes, default is `true`.
     - Parameter completionHandler: a closure with result of directory entries or error.
     - Parameter contents: An array of `FileObject` identifying the the directory entries.
     - Parameter error: Error returned by system.
     */
    open func contentsOfDirectory(path apath: String, rfc3659enabled: Bool , completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
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
                    if let uerror = error as? URLError, uerror.code == .unsupportedURL {
                        self.contentsOfDirectory(path: path, rfc3659enabled: false, completionHandler: completionHandler)
                        return
                    }
                    
                    self.dispatch_queue.async {
                        completionHandler([], error)
                    }
                    return
                }
                
                
                let files: [FileObject] = contents.flatMap {
                    rfc3659enabled ? self.parseMLST($0, in: path) : (self.parseUnixList($0, in: path) ?? self.parseDOSList($0, in: path))
                }
                
                self.dispatch_queue.async {
                    completionHandler(files, nil)
                }
            })
        }
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping (FileObject?, Error?) -> Void) {
        self.attributesOfItem(path: path, rfc3659enabled: supportsRFC3659, completionHandler: completionHandler)
    }
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameter path: path to target directory. If empty, attributes of root will be returned.
     - Parameter rfc3659enabled: uses MLST command instead of old LIST to get files attributes, default is true.
     - Parameter completionHandler: a closure with result of directory entries or error.
         `attributes`: A `FileObject` containing the attributes of the item.
         `error`: Error returned by system.
     */
    open func attributesOfItem(path apath: String, rfc3659enabled: Bool, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
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
                do {
                    if let error = error {
                        throw error
                    }
                    
                    guard let response = response, response.hasPrefix("250") || (response.hasPrefix("50") && rfc3659enabled) else {
                        throw self.urlError(path, code: .badServerResponse)
                    }
                    
                    if response.hasPrefix("500") {
                        self.supportsRFC3659 = false
                        self.attributesOfItem(path: path, rfc3659enabled: false, completionHandler: completionHandler)
                    }
                    
                    let lines = response.components(separatedBy: "\n").flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard lines.count > 2 else {
                        throw self.urlError(path, code: .badServerResponse)
                    }
                    let dirPath = (path as NSString).deletingLastPathComponent
                    let file: FileObject? = rfc3659enabled ?
                        self.parseMLST(lines[1], in: dirPath) :
                        (self.parseUnixList(lines[1], in: dirPath) ?? self.parseDOSList(lines[1], in: dirPath))
                    self.dispatch_queue.async {
                        completionHandler(file, nil)
                    }
                } catch {
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                    }
                }
            })
        }
    }
    
    open func storageProperties(completionHandler: @escaping (_ volume: VolumeObject?) -> Void) {
        dispatch_queue.async {
            completionHandler(nil)
        }
    }
    
    @discardableResult
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let progress = Progress(totalUnitCount: -1)
        if recursive {
            return self.recursiveList(path: path, useMLST: true, foundItemsHandler: { items in
                if let foundItemHandler = foundItemHandler {
                    for item in items where query.evaluate(with: item.mapPredicate()) {
                        foundItemHandler(item)
                    }
                    progress.totalUnitCount = Int64(items.count)
                }
            }, completionHandler: {files, error in
                if let error = error {
                    completionHandler([], error)
                    return
                }
                
                let foundFiles = files.filter { query.evaluate(with: $0.mapPredicate()) }
                completionHandler(foundFiles, nil)
            })
        } else {
            self.contentsOfDirectory(path: path, completionHandler: { (items, error) in
                if let error = error {
                    completionHandler([], error)
                    return
                }
                
                var result = [FileObject]()
                for item in items where query.evaluate(with: item.mapPredicate()) {
                    foundItemHandler?(item)
                    result.append(item)
                }
                completionHandler(result, nil)
            })
        }
        
        return progress
    }
    
    open func url(of path: String?) -> URL {
        let path = path?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? (path ?? "")
        
        var baseUrlComponent = URLComponents(url: self.baseURL!, resolvingAgainstBaseURL: true)
        baseUrlComponent?.user = credential?.user
        baseUrlComponent?.password = credential?.password
        return URL(string: path, relativeTo: baseUrlComponent?.url ?? baseURL) ?? baseUrlComponent?.url ?? baseURL!
    }
    
    open func relativePathOf(url: URL) -> String {
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
    
    open func isReachable(completionHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        self.attributesOfItem(path: "/") { (file, error) in
            completionHandler(file != nil, error)
        }
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
    
    @discardableResult
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        let path = (atPath as NSString).appendingPathComponent(folderName) + "/"
        return doOperation(.create(path: path), completionHandler: completionHandler)
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.remove(path: path), completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        // check file is not a folder
        guard (try? localFile.resourceValues(forKeys: [.fileResourceTypeKey]))?.fileResourceType ?? .unknown == .regular else {
            dispatch_queue.async {
                completionHandler?(self.urlError(localFile.path, code: .fileIsDirectory))
            }
            return nil
        }
        
        let operation = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        
        let progress = Progress(totalUnitCount: 0)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                }
                return
            }
            
            self.ftpStore(task, filePath: self.ftpPath(toPath), fromData: nil, fromFile: localFile, onTask: { task in
                weak var weakTask = task
                progress.cancellationHandler = {
                    weakTask?.cancel()
                }
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
            }, onProgress: { bytesSent, totalSent, expectedBytes in
                progress.totalUnitCount = expectedBytes
                progress.completedUnitCount = totalSent
                self.delegateNotify(operation, progress: progress.fractionCompleted)
            }, completionHandler: { (error) in
                if error != nil {
                    progress.cancel()
                }
                self.ftpQuit(task)
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                }
            })
        }
        
        return progress
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let progress = Progress(totalUnitCount: 0)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                return
            }
            
            self.ftpDownload(task, filePath: self.ftpPath(path), onTask: { task in
                weak var weakTask = task
                progress.cancellationHandler = {
                    weakTask?.cancel()
                }
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
            }, onProgress: { recevied, totalReceived, totalSize in
                progress.totalUnitCount = totalSize
                progress.completedUnitCount = totalReceived
                self.delegateNotify(operation, progress: progress.fractionCompleted)
            }) { (tmpurl, error) in
                if let error = error {
                    progress.cancel()
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(operation, error: error)
                    }
                    return
                }
                
                if let tmpurl = tmpurl {
                    try? FileManager.default.moveItem(at: tmpurl, to: destURL)
                    self.dispatch_queue.async {
                        completionHandler?(nil)
                        self.delegateNotify(operation)
                    }
                }
            }
        }
        return progress
    }
    
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        let operation = FileOperationType.fetch(path: path)
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
                self.delegateNotify(operation)
            }
            return nil
        }
        let progress = Progress(totalUnitCount: 0)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                return
            }
            
            self.ftpFileData(task, filePath: self.ftpPath(path), from: offset, length: length, onTask: { task in
                weak var weakTask = task
                progress.cancellationHandler = {
                    weakTask?.cancel()
                }
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
            }, onProgress: { recevied, totalReceived, totalSize in
                progress.totalUnitCount = totalSize
                progress.completedUnitCount = totalReceived
                self.delegateNotify(operation, progress: progress.fractionCompleted)
            }) { (data, error) in
                if let error = error {
                    progress.cancel()
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                        self.delegateNotify(operation, error: error)
                    }
                    return
                }
                
                if let data = data {
                    self.dispatch_queue.async {
                        completionHandler(data, nil)
                        self.delegateNotify(operation)
                    }
                }
            }
        }
        
        return progress
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        
        let progress = Progress(totalUnitCount: Int64(data?.count ?? 0))
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                }
                return
            }
            
            let storeHandler = {
                self.ftpStore(task, filePath: self.ftpPath(path), fromData: data ?? Data(), fromFile: nil, onTask: { task in
                    weak var weakTask = task
                    progress.cancellationHandler = {
                        weakTask?.cancel()
                    }
                    progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
                }, onProgress: { bytesSent, totalSent, expectedBytes in
                    progress.completedUnitCount = totalSent
                    self.delegateNotify(operation, progress: progress.fractionCompleted)
                }, completionHandler: { (error) in
                    if error != nil {
                        progress.cancel()
                    }
                    self.ftpQuit(task)
                    self.dispatch_queue.async {
                        completionHandler?(error)
                        self.delegateNotify(operation, error: error)
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
        
        return progress
    }
    
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
    open func create(symbolicLink path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        let operation = FileOperationType.link(link: path, target: destPath)
        _=self.doOperation(operation, completionHandler: completionHandler)
    }
}

extension FTPFileProvider {
    fileprivate func doOperation(_ operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> Progress? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let sourcePath = operation.source
        let destPath = operation.destination
        
        let command: String
        switch operation {
        case .create: command = "MKD \(ftpPath(sourcePath))"
        case .copy: command = "SITE CPFR \(ftpPath(sourcePath))\r\nSITE CPTO \(ftpPath(destPath!))"
        case .move: command = "RNFR \(ftpPath(sourcePath))\r\nRNTO \(ftpPath(destPath!))"
        case .remove: command = "DELE \(ftpPath(sourcePath))"
        case .link: command = "SITE SYMLINK \(ftpPath(sourcePath)) \(ftpPath(destPath!))"
        default: return nil // modify, fetch
        }
        let progress = Progress(totalUnitCount: 1)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.fpstreamTask(withHostName: baseURL!.host!, port: baseURL!.port!)
        self.ftpLogin(task) { (error) in
            if let error = error {
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
                return
            }
            
            self.execute(command: command, on: task, completionHandler: { (response, error) in
                if let error = error {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                    return
                }
                
                guard let response = response else {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: self.urlError(sourcePath, code: .badServerResponse))
                    return
                }
                
                let codes: [Int] = response.components(separatedBy: .newlines).flatMap({ $0.isEmpty ? nil : $0})
                    .flatMap {
                        let code = $0.components(separatedBy: .whitespaces).flatMap({ $0.isEmpty ? nil : $0}).first
                        return code != nil ? Int(code!) : nil
                }
                
                if codes.filter({ (450..<560).contains($0) }).count > 0 {
                    let errorCode: URLError.Code
                    switch operation {
                    case .create: errorCode = .cannotCreateFile
                    case .modify: errorCode = .cannotWriteToFile
                    case .copy:
                        self.fallbackCopy(operation, progress: progress, completionHandler: completionHandler)
                        return
                    case .move: errorCode = .cannotMoveFile
                    case .remove:
                        self.fallbackRemove(operation, progress: progress, on: task, completionHandler: completionHandler)
                        return
                    case .link: errorCode = .cannotWriteToFile
                    default: errorCode = .cannotOpenFile
                    }
                    let error = self.urlError(sourcePath, code: errorCode)
                    progress.cancel()
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                    return
                }
                
                progress.completedUnitCount = progress.totalUnitCount
                completionHandler?(nil)
                self.delegateNotify(operation)
            })
        }
        
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        return progress
    }
    
    private func fallbackCopy(_ operation: FileOperationType, progress: Progress, completionHandler: SimpleCompletionHandler) {
        let sourcePath = operation.source
        guard let destPath = operation.destination else { return }
        
        let localURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
        
        progress.becomeCurrent(withPendingUnitCount: 1)
        _ = self.copyItem(path: sourcePath, toLocalURL: localURL) { (error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                }
                return
            }
            
            progress.becomeCurrent(withPendingUnitCount: 1)
            _ = self.copyItem(localFile: localURL, to: destPath) { error in
                completionHandler?(nil)
                self.delegateNotify(operation)
            }
            progress.resignCurrent()
        }
        progress.resignCurrent()
        return
    }
    
    private func fallbackRemove(_ operation: FileOperationType, progress: Progress, on task: FileProviderStreamTask, completionHandler: SimpleCompletionHandler) {
        let sourcePath = operation.source
        
        self.execute(command: "SITE RMDIR \(ftpPath(sourcePath))", on: task) { (response, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let response = response else {
                    throw  self.urlError(sourcePath, code: .badServerResponse)
                }
                
                if response.hasPrefix("50") {
                    self.fallbackRecursiveRemove(operation, progress: progress, on: task, completionHandler: completionHandler)
                    return
                }
                
                if !response.hasPrefix("2") {
                    throw self.urlError(sourcePath, code: .cannotRemoveFile)
                }
                self.dispatch_queue.async {
                    completionHandler?(nil)
                }
                self.delegateNotify(operation)
            } catch {
                progress.cancel()
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                self.delegateNotify(operation, error: error)
            }
        }
    }
    
    private func fallbackRecursiveRemove(_ operation: FileOperationType, progress: Progress, on task: FileProviderStreamTask, completionHandler: SimpleCompletionHandler) {
        let sourcePath = operation.source
        
        _ = self.recursiveList(path: sourcePath, useMLST: true, completionHandler: { (contents, error) in
            if let error = error {
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                }
                return
            }
            
            progress.becomeCurrent(withPendingUnitCount: 1)
            let recursiveProgress = Progress(totalUnitCount: Int64(contents.count))
            let sortedContents = contents.sorted(by: {
                $0.path.localizedStandardCompare($1.path) == .orderedDescending
            })
            progress.resignCurrent()
            var command = ""
            for file in sortedContents {
                command += (file.isDirectory ? "RMD \(self.ftpPath(file.path))" : "DELE \(self.ftpPath(file.path))") + "\r\n"
            }
            command += "RMD \(self.ftpPath(sourcePath))"
            
            self.execute(command: command, on: task, completionHandler: { (response, error) in
                recursiveProgress.completedUnitCount += 1
                self.dispatch_queue.async {
                    completionHandler?(error)
                    self.delegateNotify(operation, error: error)
                }
                // TODO: Digest response
            })
        })
    }
}

extension FTPFileProvider: FileProvider { }
