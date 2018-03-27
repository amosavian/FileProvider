//
//  HTTPFileProvider.swift
//  FilesProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

/**
 The abstract base class for all REST/Web based providers such as WebDAV, Dropbox, OneDrive, Google Drive, etc. and encapsulates basic
 functionalitis such as downloading/uploading.
 
 No instance of this class should (and can) be created. Use derived classes instead. It leads to a crash with `fatalError()`.
 */
open class HTTPFileProvider: FileProviderBasicRemote, FileProviderOperations, FileProviderReadWrite {
    open class var type: String { fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.") }
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
    
    fileprivate var _session: URLSession!
    internal fileprivate(set) var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        get {
            if _session == nil {
                self.sessionDelegate = SessionDelegate(fileProvider: self)
                let config = URLSessionConfiguration.default
                config.urlCache = cache
                config.requestCachePolicy = .returnCacheDataElseLoad
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
     - baseURL: Location of server.
     - credential: An `URLCredential` object with `user` and `password`.
     - cache: A URLCache to cache downloaded files and contents.
     */
    public init(baseURL: URL?, credential: URLCredential?, cache: URLCache?) {
        // Make base url absolute and path as directory
        let urlStr = baseURL?.absoluteString
        self.baseURL = urlStr.flatMap { $0.hasSuffix("/") ? URL(string: $0) : URL(string: $0 + "/") }
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
    
    deinit {
        if let sessionuuid = _session?.sessionDescription {
            removeSessionHandler(for: sessionuuid)
        }
        
        if fileProviderCancelTasksOnInvalidating {
            _session?.invalidateAndCancel()
        } else {
            _session?.finishTasksAndInvalidate()
        }
        longpollSession.invalidateAndCancel()
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.credential, forKey: "credential")
        aCoder.encode(self.useCache, forKey: "useCache")
        aCoder.encode(self.validatingCache, forKey: "validatingCache")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func storageProperties(completionHandler: @escaping (_ volumeInfo: VolumeObject?) -> Void) {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    @discardableResult
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        fatalError("HTTPFileProvider is an abstract class. Please implement \(#function) in subclass.")
    }
    
    open func isReachable(completionHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        self.storageProperties { volume in
            if volume != nil {
                completionHandler(volume != nil, nil)
                return
            } else {
                self.contentsOfDirectory(path: "", completionHandler: { (files, error) in
                    completionHandler(false, error)
                })
            }
        }
    }
    
    // Nothing special for these two funcs, just reimplemented to workaround a bug in swift to allow override in subclasses!
    open func url(of path: String) -> URL {
        var rpath: String = path
        rpath = rpath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? rpath
        if let baseURL = baseURL {
            if rpath.hasPrefix("/") {
                rpath.remove(at: rpath.startIndex)
            }
            return URL(string: rpath, relativeTo: baseURL) ?? baseURL
        } else {
            return URL(string: rpath) ?? URL(string: "/")!
        }
    }
    
    open func relativePathOf(url: URL) -> String {
        // check if url derieved from current base url
        let relativePath = url.relativePath
        if !relativePath.isEmpty, url.baseURL == self.baseURL {
            return (relativePath.removingPercentEncoding ?? relativePath).replacingOccurrences(of: "/", with: "", options: .anchored)
        }
        
        // resolve url string against baseurl
        guard let baseURL = self.baseURL else { return url.absoluteString }
        let standardRelativePath = url.absoluteString.replacingOccurrences(of: baseURL.absoluteString, with: "/").replacingOccurrences(of: "/", with: "", options: .anchored)
        if URLComponents(string: standardRelativePath)?.host?.isEmpty ?? true {
            return standardRelativePath.removingPercentEncoding ?? standardRelativePath
        } else {
            return relativePath.replacingOccurrences(of: "/", with: "", options: .anchored)
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
        return doOperation(.move(source: path, destination: toPath), overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return doOperation(.copy(source: path, destination: toPath), overwrite: overwrite, completionHandler: completionHandler)
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
        let request = self.request(for: operation, overwrite: overwrite)
        return upload_file(toPath, request: request, localFile: localFile, operation: operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        let request = self.request(for: operation)
        let cantLoadError = urlError(path, code: .cannotLoadFromNetwork)
        return self.download_simple(path: path, request: request, operation: operation, completionHandler: { [weak self] (tempURL, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let tempURL = tempURL else {
                    throw cantLoadError
                }
                
                var coordError: NSError?
                NSFileCoordinator().coordinate(writingItemAt: tempURL, options: .forMoving, writingItemAt: destURL, options: .forReplacing, error: &coordError, byAccessor: { (tempURL, destURL) in
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destURL)
                        
                        completionHandler?(nil)
                        self?.delegateNotify(operation)
                    } catch {
                        completionHandler?(error)
                        self?.delegateNotify(operation, error: error)
                    }
                })
                
                if let error = coordError {
                    throw error
                }
            } catch {
                completionHandler?(error)
                self?.delegateNotify(operation, error: error)
            }
        })
    }
    
    /**
     Progressively fetch data of file and returns fetched data in `progressHandler`.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - progressHandler: a closure called every time a new `Data` is available.
       - position: start position of data fetched.
       - data: a portion of contents of file in a `Data` object.
       - completionHandler: a closure with result of file contents or error.
       - error: `Error` returned by system if occured.
     - Returns: An `Progress` to get progress or cancel progress.
     */
    @discardableResult
    open func contents(path: String, offset: Int64 = 0, responseHandler: ((_ response: URLResponse) -> Void)? = nil, progressHandler: @escaping (_ position: Int64, _ data: Data) -> Void, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.fetch(path: path)
        var request = self.request(for: operation)
        if offset > 0 {
            request.addValue("bytes \(offset)-", forHTTPHeaderField: "Range")
        }
        var position: Int64 = offset
        return download_progressive(path: path, request: request, operation: operation, responseHandler: responseHandler, progressHandler: { data in
            progressHandler(position, data)
            position += Int64(data.count)
        }, completionHandler: (completionHandler ?? { _ in return }))
    }
    
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
            }
            return nil
        }
        
        let operation = FileOperationType.fetch(path: path)
        var request = self.request(for: operation)
        let cantLoadError = urlError(path, code: .cannotLoadFromNetwork)
        request.setValue(rangeWithOffset: offset, length: length)
        return self.download_simple(path: path, request: request, operation: operation, completionHandler: { (tempURL, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let tempURL = tempURL else {
                    throw cantLoadError
                }
                
                let data = try Data(contentsOf: tempURL)
                completionHandler(data, nil)
            } catch {
                completionHandler(nil, error)
            }
        })
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let request = self.request(for: operation, overwrite: overwrite, attributes: [.contentModificationDateKey: Date()])
        return upload_data(path, request: request, data: data ?? Data(), operation: operation, completionHandler: completionHandler)
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
    
    /**
     This is the main function to init urlsession task for specified file operation.
     
     You won't need to override this function unless another network request must be done before intended operation,
     such as retrieving file id from file path. Then you must call `super.doOperation()`
     
     In case you have to call super method asyncronously, create a `Progress` object and pass ot to `progress` parameter.
    */
    @discardableResult
    internal func doOperation(_ operation: FileOperationType, overwrite: Bool = false, progress: Progress? = nil,
                              completionHandler: SimpleCompletionHandler) -> Progress? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        
        let progress = progress ?? Progress(totalUnitCount: 1)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let request = self.request(for: operation, overwrite: overwrite)
        
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            if let response = response as? HTTPURLResponse {
                if response.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                    serverError = self.serverError(with: code, path: operation.source, data: data)
                }
                
                if FileProviderHTTPErrorCode(rawValue: response.statusCode) == .multiStatus, let data = data {
                    self.multiStatusHandler(source: operation.source, data: data, completionHandler: completionHandler)
                }
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
    
    // codebeat:disable[ARITY]
    
    /**
     This method should be used in subclasses to fetch directory content from servers which support paginated results.
     Almost all HTTP based provider, except WebDAV, supports this method.
    
     - Important: Please use `[weak self]` when implementing handlers to prevent retain cycles. In these cases,
         return `nil` as the result of handler as the operation will be aborted.
    
     - Parameters:
        - path: path of directory which enqueued for listing, for informational use like errpr reporting.
        - requestHandler: Get token of next page and returns appropriate `URLRequest` to be sent to server.
            handler can return `nil` to cancel entire operation.
        - token: Token of the page which `URLRequest` is needed, token will be `nil` for initial page.
        - pageHandler: Handler which is called after fetching results of a page to parse data. will return parse result as
            array of `FileObject` or error if data is nil or parsing is failed. Method will not continue to next page if
            `error` is returned, otherwise `nextToken` will be used for next page. `nil` value for `newToken` will indicate
            last page of directory contents.
        - data: Raw data returned from server. Handler should parse them and return files.
        - progress: `Progress` object that `completedUnits` will be increased when a new `FileObject` is parsed in method.
        - completionHandler: All file objects returned by `pageHandler` will be passed to this handler, or error if occured.
            This handler will be called when `pageHandler` returns `nil for `newToken`.
        - contents: all files parsed via `pageHandler` will be return aggregated.
        - error: `Error` returned by server. `nil` means success. If exists, it means `contents` are incomplete.
    */
    internal func paginated(_ path: String, requestHandler: @escaping (_ token: String?) -> URLRequest?,
                            pageHandler: @escaping (_ data: Data?, _ progress: Progress) -> (files: [FileObject], error: Error?, newToken: String?),
                            completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: -1)
        self.paginated(path, startToken: nil, currentProgress: progress, previousResult: [], requestHandler: requestHandler, pageHandler: pageHandler, completionHandler: completionHandler)
        return progress
    }
    
    private func paginated(_ path: String, startToken: String?, currentProgress progress: Progress,
                           previousResult: [FileObject], requestHandler: @escaping (_ token: String?) -> URLRequest?,
                           pageHandler: @escaping (_ data: Data?, _ progress: Progress) -> (files: [FileObject], error: Error?, newToken: String?),
                           completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        guard !progress.isCancelled, let request = requestHandler(startToken) else {
            return
        }
        
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let error = error {
                completionHandler(previousResult, error)
                return
            }
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                let responseError = self.serverError(with: rCode, path: path, data: data)
                completionHandler(previousResult, responseError)
                return
            }
            
            let (newFiles, err, newToken) = pageHandler(data, progress)
            if let error = err {
                completionHandler(previousResult, error)
                return
            }
            let files = previousResult + newFiles
            if let newToken = newToken, !progress.isCancelled {
                _ = self.paginated(path, startToken: newToken, currentProgress: progress, previousResult: files, requestHandler: requestHandler, pageHandler: pageHandler, completionHandler: completionHandler)
            } else {
                completionHandler(files, nil)
            }
            
        })
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
    }
    // codebeat:enable[ARITY]
 
    internal var maxUploadSimpleSupported: Int64 { return Int64.max }
    
    func upload_task(_ targetPath: String, progress: Progress, task: URLSessionTask, operation: FileOperationType,
                     completionHandler: SimpleCompletionHandler) -> Void {
        var progress = progress
        
        var allData = Data()
        dataCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { data in
            allData.append(data)
        }
        
        completionHandlersForTasks[self.session.sessionDescription!]?[task.taskIdentifier] = { [weak self] error in
            var responseError: FileProviderHTTPError?
            if let code = (task.response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = self?.serverError(with: rCode, path: targetPath, data: allData)
            }
            if !(responseError == nil && error == nil) {
                progress.cancel()
            }
            completionHandler?(responseError ?? error)
            self?.delegateNotify(operation, error: responseError ?? error)
        }
        task.taskDescription = operation.json
        task.addObserver(self.sessionDelegate!, forKeyPath: #keyPath(URLSessionTask.countOfBytesSent), options: .new, context: &progress)
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
    }
    
    func upload_data(_ targetPath: String, request: URLRequest, data: Data, operation: FileOperationType,
                     completionHandler: SimpleCompletionHandler) -> Progress? {
        let size: Int64 = Int64(data.count)
        if size > maxUploadSimpleSupported {
            let error = self.serverError(with: .payloadTooLarge, path: targetPath, data: nil)
            completionHandler?(error)
            self.delegateNotify(operation, error: error)
            return nil
        }
        
        let progress = Progress(totalUnitCount: size)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.uploadTask(with: request, from: data)
        self.upload_task(targetPath, progress: progress, task: task, operation: operation, completionHandler: completionHandler)
        
        return progress
    }
    
    func upload_file(_ targetPath: String, request: URLRequest, localFile: URL, operation: FileOperationType,
                     completionHandler: SimpleCompletionHandler) -> Progress? {
        let fSize = (try? localFile.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let size = Int64(fSize ?? -1)
        if size > maxUploadSimpleSupported {
            let error = self.serverError(with: .payloadTooLarge, path: targetPath, data: nil)
            completionHandler?(error)
            self.delegateNotify(operation, error: error)
            return nil
        }
        
        let progress = Progress(totalUnitCount: size)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: localFile, options: .forUploading, error: &error, byAccessor: { (url) in
            let task = self.session.uploadTask(with: request, fromFile: localFile)
            self.upload_task(targetPath, progress: progress, task: task, operation: operation, completionHandler: completionHandler)
        })
        if let error = error {
            completionHandler?(error)
        }
        
        return progress
    }
    
    internal func download_progressive(path: String, request: URLRequest, operation: FileOperationType,
                                       responseHandler: ((_ response: URLResponse) -> Void)? = nil,
                                       progressHandler: @escaping (_ data: Data) -> Void,
                                       completionHandler: @escaping (_ error: Error?) -> Void) -> Progress? {
        var progress = Progress(totalUnitCount: -1)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.dataTask(with: request)
        if let responseHandler = responseHandler {
            responseCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { response in
                responseHandler(response)
            }
        }
        
        dataCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { [weak task, weak self] data in
            task.flatMap { self?.delegateNotify(operation, progress: Double($0.countOfBytesReceived) / Double($0.countOfBytesExpectedToReceive)) }
            progressHandler(data)
        }
        
        completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { error in
            if error != nil {
                progress.cancel()
            }
            completionHandler(error)
            self.delegateNotify(operation, error: error)
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
    
    internal func download_simple(path: String, request: URLRequest, operation: FileOperationType,
                                  completionHandler: @escaping ((_ tempURL: URL?, _ error: Error?) -> Void)) -> Progress? {
        var progress = Progress(totalUnitCount: -1)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let task = session.downloadTask(with: request)
        completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { error in
            if error != nil {
                progress.cancel()
            }
            completionHandler(nil, error)
            self.delegateNotify(operation, error: error)
        }
        downloadCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { tempURL in
            guard let httpResponse = task.response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (task.response as? HTTPURLResponse)?.statusCode ?? -1)
                let errorData : Data? = try? Data(contentsOf: tempURL)
                let serverError = code.flatMap { self.serverError(with: $0, path: path, data: errorData) }
                if serverError != nil {
                    progress.cancel()
                }
                completionHandler(nil, serverError)
                self.delegateNotify(operation)
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

extension HTTPFileProvider: FileProvider { }
