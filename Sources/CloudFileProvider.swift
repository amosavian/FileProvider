//
//  CloudFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

open class CloudFileProvider: LocalFileProvider {
    open override class var type: String { return "iCloudDrive" }
    
    /// Forces file operations to use `NSFileCoordinating`,
    /// Actually this is readonly, and value is always true.
    override open var isCoorinating: Bool {
        get {
            return true
        }
        set {
            assert(true, "CloudFileProvider.isCoorinating can't be set")
            return
        }
    }
    
    /// The fully-qualified container identifier for an iCloud container directory.
    open fileprivate(set) var containerId: String?
    
    /// Scope of container, indicates user can manipulate data/files or not.
    open fileprivate(set) var scope: UbiquitousScope
    
    /// Set this property to ignore initiations asserting to be on secondary thread
    static open var asserting: Bool = true
    
    /**
     Initializes the provider for the iCloud container associated with the specified identifier and 
     establishes access to that container.
     
     - Important: Do not call this method from your app’s main thread. Because this method might take a nontrivial amount of time to set up iCloud and return the requested URL, you should always call it from a secondary thread.
     
     - Parameter containerId: The fully-qualified container identifier for an iCloud container directory. The string you specify must not contain wildcards and must be of the form `<TEAMID>.<CONTAINER>`, where `<TEAMID>` is your development team ID and `<CONTAINER>` is the bundle identifier of the container you want to access.\
         The container identifiers for your app must be declared in the `com.apple.developer.ubiquity-container-identifiers` array of the `.entitlements` property list file in your Xcode project.\
         If you specify nil for this parameter, this method uses the first container listed in the `com.apple.developer.ubiquity-container-identifiers` entitlement array.
     - Parameter scope: Use `.documents` (default) to put documents that the user is allowed to access inside a Documents subdirectory. Otherwise use `.data` to store user-related data files that your app needs to share but that are not files you want the user to manipulate directly.
    */
    public init? (containerId: String?, scope: UbiquitousScope = .documents) {
        assert(!CloudFileProvider.asserting || !Thread.isMainThread, "LocalFileProvider.init(containerId:) is not recommended to be executed on Main Thread.")
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return nil
        }
        guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId) else {
            return nil
        }
        self.containerId = containerId
        self.scope = scope
        let baseURL: URL
        if scope == .documents {
            baseURL = ubiquityURL.appendingPathComponent("Documents/")
        } else {
            baseURL = ubiquityURL
        }
        
        super.init(baseURL: baseURL)
        self.isCoorinating = true
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
        
        fileManager.url(forUbiquityContainerIdentifier: containerId)
        opFileManager.url(forUbiquityContainerIdentifier: containerId)
        
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter completionHandler: a block with result of directory entries or error.
         `contents`: An array of `FileObject` identifying the the directory entries.
         `error`: Error returned by system.
     */
    open override func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        // FIXME: create runloop for dispatch_queue, start query on it
        dispatch_queue.async {
            let pathURL = self.url(of: path)
            
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, pathURL.path)
            query.valueListAttributes = [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]
            query.searchScopes = [self.scope.rawValue]
            var finishObserver: NSObjectProtocol?
            finishObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: nil, using: { (notification) in
                defer {
                    query.stop()
                    NotificationCenter.default.removeObserver(finishObserver!)
                }
                
                guard let results = query.results as? [NSMetadataItem] else {
                    return
                }
                
                query.disableUpdates()
                
                var contents = [FileObject]()
                for result in results {
                    guard let attribs = result.values(forAttributes: [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]) else {
                        continue
                    }
                    
                    guard let url = (attribs[NSMetadataItemURLKey] as? URL)?.standardized, url.deletingLastPathComponent().path.trimmingCharacters(in: pathTrimSet) == pathURL.path.trimmingCharacters(in: pathTrimSet) else {
                        continue
                    }
                    
                    if let file = self.mapFileObject(attributes: attribs) {
                        contents.append(file)
                    }
                }
                
                query.stop()
                self.dispatch_queue.async {
                    completionHandler(contents, nil)
                }
                
            })
            DispatchQueue.main.async {
                if !query.start() {
                    self.dispatch_queue.async {
                        completionHandler([], self.throwError(path, code: CocoaError.fileReadNoPermission))
                    }
                }
            }
        }
    }
    
    /// Please don't rely this function to get iCloud drive total and remaining capacity
    /// - Important: iCloud Storage size and free space is unavailable, it returns local space
    open override func storageProperties(completionHandler: (@escaping (_ total: Int64, _ used: Int64) -> Void)) {
        super.storageProperties(completionHandler: completionHandler)
    }
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter completionHandler: a block with result of directory entries or error.
         `attributes`: A `FileObject` containing the attributes of the item.
         `error`: Error returned by system.
     */
    open override func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        dispatch_queue.async {
            let pathURL = self.url(of: path)
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemPathKey, pathURL.path)
            query.valueListAttributes = [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]
            query.searchScopes = [self.scope.rawValue]
            var finishObserver: NSObjectProtocol?
            finishObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: nil, using: { (notification) in
                defer {
                    query.stop()
                    NotificationCenter.default.removeObserver(finishObserver!)
                }
                
                query.disableUpdates()
                
                guard let result = (query.results as? [NSMetadataItem])?.first, let attribs = result.values(forAttributes: [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]) else {
                    let error = self.throwError(path, code: CocoaError.fileNoSuchFile)
                    self.dispatch_queue.async {
                        completionHandler(nil, error)
                    }
                    return
                }
                
                if let file = self.mapFileObject(attributes: attribs) {
                    self.dispatch_queue.async {
                        completionHandler(file, nil)
                    }
                } else {
                    let noFileError = self.throwError(path, code: CocoaError.fileNoSuchFile)
                    self.dispatch_queue.async {
                        completionHandler(nil, noFileError)
                    }
                }
            })
            DispatchQueue.main.async {
                if !query.start() {
                    self.dispatch_queue.async {
                        completionHandler(nil, self.throwError(path, code: CocoaError.fileReadNoPermission))
                    }
                }
            }
        }
    }
    
    /**
     Creates a new directory at the specified path asynchronously.
     This will create any necessary intermediate directories.
     
     - Parameters:
       - folder: Directory name.
       - at: Parent path of new directory.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `CloudFileProvider`.
     */
    @discardableResult
    open override func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let r = super.create(folder: folderName, at: atPath, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Creates an new file with data passed to method asynchronously.
     Returns error via completionHandler if file is already exists.
     
     - Parameters:
       - file: New file name with extension separated by period.
       - at: Parent path of new file.
       - data: Data of new files. Pass nil or `Data()` to create empty file.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `CloudFileProvider`.
     */
    @discardableResult
    open override func create(file fileName: String, at atPath: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let r = super.create(file: fileName, at: atPath, contents: data, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Moves a file or directory from `path` to designated path asynchronously.
     When you want move a file, destination path should also consists of file name.
     Either a new name or the old one.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `CloudFileProvider`.
     */
    @discardableResult
    open override func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let r = super.moveItem(path: path, to: toPath, overwrite: overwrite, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Copies a file or directory from `path` to designated path asynchronously.
     When want copy a file, destination path should also consists of file name.
     Either a new name or the old one.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `CloudFileProvider`.
     */
    @discardableResult
    open override func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let r = super.copyItem(path: path, to: toPath, overwrite: overwrite, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Removes the file or directory at the specified path.
     
     - Important: Due to a bug (race condition?) in Apple API, it takes about 3-5 seconds to update containing folder
       list and triggering notification registered for directory while completion handler will run almost immediately.
       It's your responsibility to workaourd this bug/feature and mark file as deleted in your software.
     
     - Parameters:
       - path: file or directory path.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `CloudFileProvider`.
     
     */
    @discardableResult
    open override func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let r = super.removeItem(path: path, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Uploads a file from local file url to designated path asynchronously.
     Method will fail if source is not a local url with `file://` scheme.
     
     - Parameters:
       - localFile: a file url to file.
       - to: destination path of file, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress.
     */
    @discardableResult
    open override func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // TODO: Make use of overwrite parameter
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        operation_queue.addOperation {
            let tempFolder: URL
            if #available(iOS 10.0, macOS 10.12, tvOS 10.0, *) {
                tempFolder = FileManager.default.temporaryDirectory
            } else {
                tempFolder = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            let tmpFile = tempFolder.appendingPathComponent(UUID().uuidString)
            
            do {
                try self.opFileManager.copyItem(at: localFile, to: tmpFile)
                let toUrl = self.url(of: toPath)
                try self.opFileManager.setUbiquitous(true, itemAt: tmpFile, destinationURL: toUrl)
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e {
                if self.opFileManager.fileExists(atPath: tmpFile.path) {
                    try? self.opFileManager.removeItem(at: tmpFile)
                }
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return CloudOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    /**
     Download a file from `path` to designated local file url asynchronously.
     Method will fail if destination is not a local url with `file://` scheme.
     
     - Parameters:
       - path: original file or directory path.
       - toLocalURL: destination local url of file, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress.
     */
    @discardableResult
    open override func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        
        do {
            try self.opFileManager.startDownloadingUbiquitousItem(at: self.url(of: path))
        } catch let e {
            completionHandler?(e)
            DispatchQueue.main.async(execute: {
                self.delegate?.fileproviderFailed(self, operation: opType)
            })
            return nil
        }
        
        guard let r = super.copyItem(path: path, toLocalURL: toLocalURL, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Retreives a `Data` object with the contents of the file asynchronously vis contents argument of completion handler.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - completionHandler: a block with result of file contents or error.
         `contents`: contents of file in a `Data` object.
         `error`: Error returned by system.
     - Returns: An `OperationHandle` to get progress or cancel progress.
     */
    @discardableResult
    open override func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        guard let r = super.contents(path: path, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Retreives a `Data` object with a portion contents of the file asynchronously vis contents argument of completion handler.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - offset: First byte index which should be read. **Starts from 0.**
       - length: Bytes count of data. Pass `-1` to read until the end of file.
       - completionHandler: a block with result of file contents or error.
         `contents`: contents of file in a `Data` object.
         `error`: Error returned by system.
     - Returns: An `OperationHandle` to get progress or cancel progress.
     */
    @discardableResult
    open override func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        guard let r = super.contents(path: path, offset: offset, length: length, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file.
       - overwrite: Destination file should be overwritten if file is already exists. Default is `false`.
       - atomically: data will be written to a temporary file before writing to final location. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    open override func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard let r = super.writeContents(path: path, contents: data, atomically: atomically, overwrite: overwrite, completionHandler: completionHandler) else { return nil }
        return CloudOperationHandle(operationType: r.operationType, baseURL: self.baseURL)
    }
    
    /**
     Search files inside directory using query asynchronously.
     
     - Note: For now only it's limited to file names. `query` parameter may take `NSPredicate` format in near future.
     
     - Parameters:
       - path: location of directory to start search
       - recursive: Searching subdirectories of path
       - query: Simple string of file name to be search (for now).
       - foundItemHandler: Block which is called when a file is found
     - completionHandler: Block which will be called after finishing search. Returns an arry of `FileObject` or error if occured.
     */
    open override func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            let pathURL = self.url(of: path)
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "(%K BEGINSWITH %@) && (%K LIKE %@)", NSMetadataItemPathKey, pathURL.path, NSMetadataItemFSNameKey, query)
            query.searchScopes = [self.scope.rawValue]
            
            var lastReportedCount = 0
            
            if let foundItemHandler = foundItemHandler {
                var updateObserver: NSObjectProtocol?
                
                // FIXME: Remove this section as it won't work as expected on iCloud
                updateObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryGatheringProgress, object: query, queue: nil, using: { (notification) in
                    
                    query.disableUpdates()
                    
                    guard query.resultCount > lastReportedCount else { return }
                    
                    for index in lastReportedCount..<query.resultCount {
                        guard let attribs = (query.result(at: index) as? NSMetadataItem)?.values(forAttributes: [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]) else {
                            continue
                        }
                        
                        guard let url = (attribs[NSMetadataItemURLKey] as? URL)?.standardized, recursive || url.deletingLastPathComponent().path.trimmingCharacters(in: pathTrimSet) == pathURL.path.trimmingCharacters(in: pathTrimSet) else {
                            continue
                        }
                        
                        if let file = self.mapFileObject(attributes: attribs) {
                            foundItemHandler(file)
                        }
                    }
                    lastReportedCount = query.resultCount
                    
                    query.enableUpdates()
                })
            }
            
            var finishObserver: NSObjectProtocol?
            finishObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil, using: { (notification) in
                defer {
                    query.stop()
                    NotificationCenter.default.removeObserver(finishObserver!)
                }
                
                guard let results = query.results as? [NSMetadataItem] else {
                    return
                }
                
                query.disableUpdates()
                
                var contents = [FileObject]()
                for result in results {
                    guard let attribs = result.values(forAttributes: [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]) else {
                        continue
                    }
                    
                    guard let url = (attribs[NSMetadataItemURLKey] as? URL)?.standardized, recursive || url.deletingLastPathComponent().path.trimmingCharacters(in: pathTrimSet) == pathURL.path.trimmingCharacters(in: pathTrimSet) else {
                        continue
                    }
                    
                    if let file = self.mapFileObject(attributes: attribs) {
                        contents.append(file)
                    }
                }
                self.dispatch_queue.async {
                   completionHandler(contents, nil)
                }
            })
            
            DispatchQueue.main.async {
                if !query.start() {
                    self.dispatch_queue.async {
                        completionHandler([], self.throwError(path, code: CocoaError.fileReadNoPermission))
                    }
                }
            }
        }
    }
    
    fileprivate var monitors = [String: (NSMetadataQuery, NSObjectProtocol)]()
    
    /**
     Starts monitoring a path and its subpaths, including files and folders, for any change,
     including copy, move/rename, content changes, etc.
     To avoid thread congestion, `evetHandler` will be triggered with 0.2 seconds interval,
     and has a 0.25 second delay, to ensure it's called after updates.
     
     - Note: this functionality is available only in `LocalFileProvider` and `CloudFileProvider`.
     - Note: `eventHandler` is not called on main thread, for updating UI. dispatch routine to main thread.
     - Important: `eventHandler` may be called if file is changed in recursive subpaths of registered path.
     This may cause negative impact on performance if a root path is being monitored.
     
     - Parameters:
       - path: path of directory.
       - eventHandler: Block executed after change, on a secondary thread.
     */
    open override func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        self.unregisterNotifcation(path: path)
        let pathURL = self.url(of: path)
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "(%K BEGINSWITH %@)", NSMetadataItemPathKey, pathURL.path)
        query.valueListAttributes = []
        query.searchScopes = [self.scope.rawValue]
        
        let updateObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: nil, using: { (notification) in
            
            query.disableUpdates()
            
            eventHandler()
            
            query.enableUpdates()
        })
        
        DispatchQueue.main.async {
            if query.start() {
                self.monitors[path] = (query, updateObserver)
            }
        }
    }
    
    /// Stops monitoring the path.
    ///
    /// - Parameter path: path of directory.
    open override func unregisterNotifcation(path: String) {
        guard let (query, observer) = monitors[path] else {
            return
        }
        query.disableUpdates()
        query.stop()
        NotificationCenter.default.removeObserver(observer)
        monitors.removeValue(forKey: path)
    }
    
    /// Investigate either the path is registered for change notification or not.
    ///
    /// - Parameter path: path of directory.
    /// - Returns: Directory is being monitored or not.
    open override func isRegisteredForNotification(path: String) -> Bool {
        return monitors[path] != nil
    }
    
    open override func copy(with zone: NSZone? = nil) -> Any {
        let copy = CloudFileProvider(containerId: self.containerId)
        copy?.currentPath = self.currentPath
        copy?.delegate = self.delegate
        copy?.fileOperationDelegate = self.fileOperationDelegate
        copy?.isPathRelative = self.isPathRelative
        return copy as Any
    }
    
    fileprivate func mapFileObject(attributes attribs: [String: Any]) -> FileObject? {
        guard let url = (attribs[NSMetadataItemURLKey] as? URL)?.standardizedFileURL, let name = attribs[NSMetadataItemFSNameKey] as? String else {
            return nil
        }
        
        let path = self.relativePathOf(url: url)
        let rpath = path.hasPrefix("/") ? path.substring(from: path.index(after: path.startIndex)) : path
        let relativeUrl = URL(string: rpath, relativeTo: self.baseURL)
        let file = FileObject(url: relativeUrl ?? url, name: name, path: path)
        
        file.size = (attribs[NSMetadataItemFSSizeKey] as? NSNumber)?.int64Value ?? -1
        file.creationDate = attribs[NSMetadataItemFSCreationDateKey] as? Date
        file.modifiedDate = attribs[NSMetadataItemFSContentChangeDateKey] as? Date
        let isFolder = (attribs[NSMetadataItemContentTypeTreeKey] as? [String])?.contains("public.folder") ?? false
        let isSymbolic = (attribs[NSMetadataItemContentTypeTreeKey] as? [String])?.contains("public.symlink") ?? false
        file.type = isFolder ? .directory : (isSymbolic ? .symbolicLink : .regular)
        
        return file
    }
    
    /// Removes local copy of file, but spares cloud copy/
    /// - Parameter path: Path of file or directory to be remoed from local
    /// - Parameter completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
    open func evictItem(path: String, completionHandler: SimpleCompletionHandler) {
        operation_queue.addOperation {
            do {
                try self.opFileManager.evictUbiquitousItem(at: self.url(of: path))
                completionHandler?(nil)
            } catch let e {
                completionHandler?(e)
            }
        }
    }
    
    /// Returns a pulic url with expiration date, can be shared with other people.
    open func temporaryLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: FileObject?, _ expiration: Date?, _ error: Error?) -> Void)) {
        operation_queue.addOperation {
            do {
                var expiration: NSDate?
                let url = try self.opFileManager.url(forPublishingUbiquitousItemAt: self.url(of: path), expiration: &expiration)
                self.dispatch_queue.async {
                    completionHandler(url, nil, expiration as Date?, nil)
                }
            } catch let e {
                self.dispatch_queue.async {
                    completionHandler(nil, nil, nil, e)
                }
            }
        }
    }
}

public enum UbiquitousScope: RawRepresentable {
    /// Search all files not in the Documents directories of the app’s iCloud container directories.
    /// Use this scope to store user-related data files that your app needs to share 
    /// but that are not files you want the user to manipulate directly.
    case data
    /// Search all files in the Documents directories of the app’s iCloud container directories.
    /// Put documents that the user is allowed to access inside a Documents subdirectory.
    case documents
    
    public typealias RawValue = String
    
    public init? (rawValue: String) {
        switch rawValue {
        case NSMetadataQueryUbiquitousDataScope:
            self = .data
        case NSMetadataQueryUbiquitousDocumentsScope:
            self = .documents
        default:
            return nil
        }
    }
    
    public var rawValue: String {
        switch self {
        case .data:
            return NSMetadataQueryUbiquitousDataScope
        case .documents:
            return NSMetadataQueryUbiquitousDocumentsScope
        }
    }
}

open class CloudOperationHandle: OperationHandle {
    public let baseURL: URL?
    public let operationType: FileOperationType
    
    init (operationType: FileOperationType, baseURL: URL?) {
        self.baseURL = baseURL
        self.operationType = operationType
    }
    
    private var sourceURL: URL? {
        guard let source = operationType.source, let baseURL = baseURL else { return nil }
        return source.hasPrefix("file://") ? URL(fileURLWithPath: source) : baseURL.appendingPathComponent(source)
    }
    
    private var destURL: URL? {
        guard let dest = operationType.destination, let baseURL = baseURL else { return nil }
        return dest.hasPrefix("file://") ? URL(fileURLWithPath: dest) : baseURL.appendingPathComponent(dest)
    }
    
    open var bytesSoFar: Int64 {
        assert(!Thread.isMainThread, "Don't run \(#function) method on main thread")
        
        guard let url = destURL ?? sourceURL, let item = CloudOperationHandle.getMetadataItem(url: url) else { return 0 }
        let downloaded = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
        let uploaded = item.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double ?? 0
        guard let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64 else { return -1 }
        if (downloaded == 0 || downloaded == 100) && (uploaded > 0 && uploaded < 100) {
            return Int64(uploaded * (Double(size) / 100))
        } else if (uploaded == 0 || uploaded == 100) && (downloaded > 0 && downloaded < 100) {
            return Int64(downloaded * (Double(size) / 100))
        } else if uploaded == 100 || downloaded == 100 {
            return size
        }
        return 0
    }
    
    open var totalBytes: Int64 {
        assert(!Thread.isMainThread, "Don't run \(#function) method on main thread")
        guard let url = destURL ?? sourceURL, let item = CloudOperationHandle.getMetadataItem(url: url) else { return -1 }
        return item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64 ?? -1
    }
    
    open var inProgress: Bool {
        guard let url = destURL ?? sourceURL, let item = CloudOperationHandle.getMetadataItem(url: url) else { return false }
        let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String ?? NSMetadataUbiquitousItemDownloadingStatusNotDownloaded
        let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool ?? false
        return downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent || isUploading
    }
    
    /// Not usable in local provider
    open func cancel() -> Bool {
        return false
    }
    
    fileprivate static func getMetadataItem(url: URL) -> NSMetadataItem? {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "(%K LIKE %@)", NSMetadataItemPathKey, url.path)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryUbiquitousDataScope]
        
        var item: NSMetadataItem?
        
        let group = DispatchGroup()
        group.enter()
        var finishObserver: NSObjectProtocol?
        finishObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil, using: { (notification) in
            defer {
                query.stop()
                group.leave()
                NotificationCenter.default.removeObserver(finishObserver!)
            }
            
            if query.resultCount > 0 {
                item = query.result(at: 0) as? NSMetadataItem
            }
            
            query.disableUpdates()
            
        })
        
        DispatchQueue.main.async {
            query.start()
        }
        _ = group.wait(timeout: DispatchTime.now() + 30)
        return item
    }
}
