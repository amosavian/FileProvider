//
//  HTTPFileProvider.swift
//  FilesProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

/**
 Allows accessing to Dropbox stored files. This provider doesn't cache or save files internally, however you can
 set `useCache` and `cache` properties to use Foundation `NSURLCache` system.
 
 - Note: Uploading files and data are limited to 150MB, for now.
 */
open class HTTPFileProvider: FileProviderBasicRemote, FileProviderOperations, FileProviderReadWrite {
    open class var type: String { fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.") }
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
    
    fileprivate var _session: URLSession?
    internal fileprivate(set) var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        get {
            if _session == nil {
                self.sessionDelegate = SessionDelegate(fileProvider: self)
                let config = URLSessionConfiguration.default
                config.urlCache = cache
                config.requestCachePolicy = .returnCacheDataElseLoad
                _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: self.operation_queue)
                _session!.sessionDescription = UUID().uuidString
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
    
    fileprivate var _longpollSession: URLSession?
    /// This session has extended timeout up to 10 minutes, suitable for monitoring.
    internal var longpollSession: URLSession {
        if _longpollSession == nil {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600
            _longpollSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        }
        return _longpollSession!
    }
    
    /**
     This is parent initializer for subclasses. Using this method on `HTTPFileProvider` will fail as `type` is not implemented.
     
     - Parameters:
     - baseURL: Location of WebDAV server.
     - credential: An `URLCredential` object with `user` and `password`.
     - cache: A URLCache to cache downloaded files and contents.
     */
    public init(baseURL: URL?, credential: URLCredential?, cache: URLCache?) {
        self.baseURL = baseURL
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        
        #if swift(>=3.1)
            let queueLabel = "FileProvider.\(Swift.type(of: self).type)"
        #else
            let queueLabel = "FileProvider.\(type(of: self).type)"
        #endif
        dispatch_queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "\(queueLabel).Operation"
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
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
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
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
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) -> Progress? {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func isReachable(completionHandler: @escaping (Bool) -> Void) {
        self.storageProperties { total, _ in
            completionHandler(total > 0)
        }
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
    
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        let path = (atPath as NSString).appendingPathComponent(folderName) + "/"
        return doOperation(.create(path: path), completionHandler: completionHandler)
    }
    
    open func moveItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.remove(path: path), completionHandler: completionHandler)
    }
    
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        // check file is not a folder
        guard (try? localFile.resourceValues(forKeys: [.fileResourceTypeKey]))?.fileResourceType ?? .unknown == .regular else {
            dispatch_queue.async {
                completionHandler?(self.throwError(localFile.path, code: URLError.fileIsDirectory))
            }
            return nil
        }
        
        let operation = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let request = self.request(for: operation, overwrite: overwrite)
        return upload_simple(toPath, request: request, localFile: localFile, operation: operation, completionHandler: completionHandler)
    }
    
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        let request = self.request(for: operation)
        return self.download_simple(path: path, request: request, operation: operation, completionHandler: { [weak self] (tempURL, error) in
            if let error = error {
                completionHandler?(error)
                self?.delegateNotify(operation, error: error)
                return
            }
            
            guard let tempURL = tempURL else {
                completionHandler?(error)
                self?.delegateNotify(operation, error: error)
                return
            }
            
            do {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                completionHandler?(nil)
                self?.delegateNotify(operation, error: nil)
            } catch let e {
                completionHandler?(e)
                self?.delegateNotify(operation, error: e)
            }
        })
    }
    
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
            }
            return nil
        }
        
        let operation = FileOperationType.fetch(path: path)
        var request = self.request(for: operation)
        request.set(rangeWithOffset: offset, length: length)
        return self.download_simple(path: path, request: request, operation: operation, completionHandler: { (tempURL, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            guard let tempURL = tempURL else {
                completionHandler(nil, error)
                return
            }
            
            do {
                let data = try Data(contentsOf: tempURL)
                completionHandler(data, nil)
            } catch let e {
                completionHandler(nil, e)
            }
        })
    }
    
    public func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let request = self.request(for: operation, overwrite: overwrite, attributes: [.contentModificationDateKey: Date()])
        return upload_simple(path, request: request, data: data ?? Data(), operation: operation, completionHandler: completionHandler)
    }
    
    internal func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey: Any] = [:]) -> URLRequest {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    internal func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    internal func multiStatusHandler(source: String, data: Data, completionHandler: SimpleCompletionHandler) -> Void {
        // WebDAV will override this function
    }
    
    fileprivate func doOperation(_ operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> Progress? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        
        let progress = Progress(totalUnitCount: 1)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let request = self.request(for: operation)
        
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            if let response = response as? HTTPURLResponse, response.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                serverError = self.serverError(with: code, path: operation.source, data: data)
            }
            
            if let response = response as? HTTPURLResponse, FileProviderHTTPErrorCode(rawValue: response.statusCode) == .multiStatus, let data = data {
                self.multiStatusHandler(source: operation.source, data: data, completionHandler: completionHandler)
            }
            
            if serverError == nil && error == nil {
                progress.completedUnitCount = 1
            } else {
                progress.cancel()
            }
            completionHandler?(serverError ?? error)
            self.delegateNotify(operation, error: serverError ?? error)
        })
        task.taskDescription = operation.json
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
        return progress
    }
    
    internal func upload_simple(_ targetPath: String, request: URLRequest, data: Data? = nil, localFile: URL? = nil, operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> Progress? {
        let size = data?.count ?? Int((try? localFile?.resourceValues(forKeys: [.fileSizeKey]))??.fileSize ?? -1)
        
        var progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        progress.totalUnitCount = Int64(size)
        
        let task: URLSessionUploadTask
        if let data = data {
            task = session.uploadTask(with: request, from: data)
        } else if let localFile = localFile {
            task = session.uploadTask(with: request, fromFile: localFile)
        } else {
            return nil
        }
        
        completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { [weak self] error in
            var responseError: FileProviderHTTPError?
            if let code = (task.response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                // We can't fetch server result from delegate!
                responseError = self?.serverError(with: rCode, path: targetPath, data: nil)
            }
            if !(responseError == nil && error == nil) {
                progress.cancel()
            }
            completionHandler?(responseError ?? error)
            self?.delegateNotify(operation, error: responseError ?? error)
        }
        task.taskDescription = operation.json
        task.addObserver(sessionDelegate!, forKeyPath: #keyPath(URLSessionTask.countOfBytesSent), options: .new, context: &progress)
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
        return progress
    }
    
    internal func download_simple(path: String, request: URLRequest, operation: FileOperationType, completionHandler: @escaping ((_ tempURL: URL?, _ error: Error?) -> Void)) -> Progress? {
        var progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.downloadTask(with: request)
        completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { error in
            if error != nil {
                progress.cancel()
            }
            completionHandler(nil, error)
        }
        downloadCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { tempURL in
            guard let httpResponse = task.response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (task.response as? HTTPURLResponse)?.statusCode ?? -1)
                let errorData : Data? = nil //Data(contentsOf:cacheURL) // TODO: Figure out how to get error response data for the error description
                let serverError : FileProviderHTTPError? = code != nil ? self.serverError(with: code!, path: path, data: errorData) : nil
                if serverError != nil {
                    progress.cancel()
                }
                completionHandler(nil, serverError)
                return
            }
            
            completionHandler(tempURL, nil)
        }
        task.taskDescription = operation.json
        task.addObserver(sessionDelegate!, forKeyPath: #keyPath(URLSessionTask.countOfBytesReceived), options: .new, context: &progress)
        task.addObserver(sessionDelegate!, forKeyPath: #keyPath(URLSessionTask.countOfBytesExpectedToReceive), options: .new, context: &progress)
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
        return progress
    }
}

extension HTTPFileProvider {
    internal func delegateNotify(_ operation: FileOperationType, error: Error?) {
        DispatchQueue.main.async(execute: {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
}

extension HTTPFileProvider: FileProvider { }
