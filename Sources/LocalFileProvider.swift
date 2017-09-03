//
//  LocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/**
 This provider class allows interacting with local files placed in user disk. It also allows an
 easy way to use `NSFileCoordintaing` to coordinate read and write when neccessary.
 
 it uses `FileManager` foundation class with some additions like searching and reading a portion of file.
 */
open class LocalFileProvider: FileProvider, FileProviderMonitor, FileProvideUndoable {
    open class var type: String { return "Local" }
    open fileprivate(set) var baseURL: URL?
    open var currentPath: String
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue
    open weak var delegate: FileProviderDelegate?
    open var credential: URLCredential?
    
    /// Underlying `FileManager` object for listing and metadata fetching.
    open private(set) var fileManager = FileManager()
    /// Underlying `FileManager` object for operationa like copying, moving, etc.
    open private(set) var opFileManager = FileManager()
    fileprivate var fileProviderManagerDelegate: LocalFileProviderManagerDelegate? = nil
    
    open var undoManager: UndoManager? = nil
    
    /**
     Forces file operations to use `NSFileCoordinating`, should be set `true` if:
     - Files are on ubiquity (iCloud) container.
     - Multiple processes are accessing same file, recommended when accessing a shared/public 
     user document in macOS and when using app extensions in iOS/tvOS (shared container).
     
     By default it's `true` when using iCloud or shared container (App Group) initializers,
     otherwise it's `false` to accelerate operations.
    */
    open var isCoorinating: Bool
    
    /**
     Initializes provider for the specified common directory in the requested domains.
     default values are `directory: .documentDirectory, domainMask: .userDomainMask`.
     
     - Parameters:
     - for: The search path directory. The supported values are described in `FileManager.SearchPathDirectory`.
     - in: Base locations for directory to search. The value for this parameter is one or more of the constants described in `FileManager.SearchPathDomainMask`.
     */
    public convenience init (for directory: FileManager.SearchPathDirectory = .documentDirectory, in domainMask: FileManager.SearchPathDomainMask = .userDomainMask) {
        self.init(baseURL: FileManager.default.urls(for: directory, in: domainMask).first!)
    }
    
    /**
     Failable initializer for the specified shared container directory, allows data and files to be shared among app
     and extensions regarding sandbox requirements. Container ID is same with app group specified in project `Capabilities`
     tab under `App Group` item. If you don't have enough privilage to access container or the app group imply does't exist,
     initialing will fail.
     default values are `directory: .documentDirectory`.
    
     - Parameters:
       - sharedContainerId: Same with `App Group` identifier defined in project settings.
       - directory: The search path directory. The supported values are described in `FileManager.SearchPathDirectory`.
    */
    public convenience init? (sharedContainerId: String, directory: FileManager.SearchPathDirectory = .documentDirectory) {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerId) else {
            return nil
        }
        
        var finalBaseURL = baseURL.absoluteURL
        
        switch directory {
        case .documentDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Documents")
        case .libraryDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Library")
        case .cachesDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Library/Caches")
        case .applicationSupportDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Library/Application support")
        default:
            break
        }
        
        self.init(baseURL: finalBaseURL)
        self.isCoorinating = true
        
        try? fileManager.createDirectory(at: finalBaseURL, withIntermediateDirectories: true)
    }
    
    /// Initializes provider for the specified local URL.
    ///
    /// - Parameter baseURL: Local URL location for base directory.
    public init (baseURL: URL) {
        guard baseURL.isFileURL else {
            fatalError("Cannot initialize a Local provider from remote URL.")
        }
        self.baseURL = (baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")).absoluteURL
        self.currentPath = ""
        self.credential = nil
        self.isCoorinating = false
        
        #if swift(>=3.1)
        let queueLabel = "FileProvider.\(Swift.type(of: self).type)"
        #else
        let queueLabel = "FileProvider.\(type(of: self).type)"
        #endif
        dispatch_queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "\(queueLabel).Operation"
        
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(forKey: "baseURL") as? URL else {
            return nil
        }
        self.init(baseURL: baseURL)
        self.currentPath   = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.isCoorinating = aDecoder.decodeBool(forKey: "isCoorinating")
    }
    
    open func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "currentPath")
        aCoder.encode(self.currentPath, forKey: "currentPath")
        aCoder.encode(self.isCoorinating, forKey: "isCoorinating")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = LocalFileProvider(baseURL: self.baseURL!)
        copy.currentPath = self.currentPath
        copy.undoManager = self.undoManager
        copy.isCoorinating = self.isCoorinating
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        return copy
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.url(of: path), includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants)
                let filesAttributes = contents.flatMap({ (fileURL) -> LocalFileObject? in
                    let path = self.relativePathOf(url: fileURL)
                    return LocalFileObject(fileWithPath: path, relativeTo: self.baseURL)
                })
                completionHandler(filesAttributes, nil)
            } catch {
                completionHandler([], error)
            }
        }
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        dispatch_queue.async {
            completionHandler(LocalFileObject(fileWithPath: path, relativeTo: self.baseURL), nil)
        }
    }
    
    open func storageProperties(completionHandler: (@escaping (_ total: Int64, _ used: Int64) -> Void)) {
        let values = try? baseURL?.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let totalSize = Int64(values??.volumeTotalCapacity ?? -1)
        let freeSize = Int64(values??.volumeAvailableCapacity ?? 0)
        completionHandler(totalSize, totalSize - freeSize)
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) -> Progress? {
        let progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(self.url(of: path), forKey: .fileURLKey)
        
        dispatch_queue.async {
            progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
            let iterator = self.fileManager.enumerator(at: self.url(of: path), includingPropertiesForKeys: nil, options: recursive ? [] : [.skipsSubdirectoryDescendants, .skipsPackageDescendants]) { (url, e) -> Bool in
                completionHandler([], e)
                return true
            }
            var result = [LocalFileObject]()
            while let fileURL = iterator?.nextObject() as? URL {
                if progress.isCancelled {
                    break
                }
                let path = self.relativePathOf(url: fileURL)
                if let fileObject = LocalFileObject(fileWithPath: path, relativeTo: self.baseURL), query.evaluate(with: fileObject.mapPredicate()) {
                    result.append(fileObject)
                    progress.completedUnitCount = Int64(result.count)
                    foundItemHandler?(fileObject)
                }
            }
            completionHandler(result, nil)
        }
        
        return progress
    }
    
    open func isReachable(completionHandler: @escaping (Bool) -> Void) {
        dispatch_queue.async {
            completionHandler(self.fileManager.isReadableFile(atPath: self.baseURL!.path))
        }
    }
    
    open weak var fileOperationDelegate : FileOperationDelegate?
    
    @discardableResult
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.create(path: (atPath as NSString).appendingPathComponent(folderName) + "/")
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.move(source: path, destination: toPath)
        
        let fileExists = ((try? self.url(of: toPath).checkResourceIsReachable()) ?? false) ||
            ((try? self.url(of: toPath).checkPromisedItemIsReachable()) ?? false)
        if !overwrite && fileExists {
            let e = self.throwError(toPath, code: CocoaError.fileWriteFileExists)
            dispatch_queue.async {
                completionHandler?(e)
            }
            self.delegateNotify(operation, error: e)
            return nil
        }
        
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: toPath)
        
        let fileExists = ((try? self.url(of: toPath).checkResourceIsReachable()) ?? false) ||
            ((try? self.url(of: toPath).checkPromisedItemIsReachable()) ?? false)
        if !overwrite && fileExists {
            let e = self.throwError(toPath, code: CocoaError.fileWriteFileExists)
            dispatch_queue.async {
                completionHandler?(e)
            }
            self.delegateNotify(operation, error: e)
            return nil
        }
        
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.remove(path: path)
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        
        let fileExists = ((try? self.url(of: toPath).checkResourceIsReachable()) ?? false) ||
            ((try? self.url(of: toPath).checkPromisedItemIsReachable()) ?? false)
        if !overwrite && fileExists {
            let e = self.throwError(toPath, code: CocoaError.fileWriteFileExists)
            dispatch_queue.async {
                completionHandler?(e)
            }
            self.delegateNotify(operation, error: e)
            return nil
        }
        return self.doOperation(operation, forUploading: true, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @objc dynamic func doSimpleOperation(_ box: UndoBox) {
        guard let _ = self.undoManager else { return }
        _ = self.doOperation(box.undoOperation) { (_) in
            return
        }
    }
    
    @discardableResult
    fileprivate func doOperation(_ operation: FileOperationType, data: Data? = nil, atomically: Bool = false, forUploading: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        let progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.isCancellable = false
        progress.setUserInfoObject(Progress.FileOperationKind.receiving, forKey: .fileOperationKindKey)
        func urlofpath(path: String) -> URL {
            if path.hasPrefix("file://") {
                let removedSchemePath = path.replacingOccurrences(of: "file://", with: "", options: .anchored)
                let pDecodedPath = removedSchemePath.removingPercentEncoding ?? removedSchemePath
                return URL(fileURLWithPath: pDecodedPath)
            } else {
                return self.url(of: path)
            }
        }
        
        let sourcePath = operation.source
        let destPath = operation.destination
        let source: URL = urlofpath(path: sourcePath)
        progress.setUserInfoObject(source, forKey: .fileURLKey)
        
        let dest: URL?
        if let destPath = destPath {
            dest = urlofpath(path: destPath)
        } else {
            dest = nil
        }
        
        if let undoManager = self.undoManager, let undoOp = self.undoOperation(for: operation) {
            let undoBox = UndoBox(provider: self, operation: operation, undoOperation: undoOp)
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self, selector: #selector(LocalFileProvider.doSimpleOperation(_:)), object: undoBox)
            undoManager.setActionName(operation.actionDescription)
            undoManager.endUndoGrouping()
        }
        
        var successfulSecurityScopedResourceAccess = false
        
        let operationHandler: (URL, URL?) -> Void = { source, dest in
            do {
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
                switch operation {
                case .create:
                    if sourcePath.hasSuffix("/") {
                        progress.totalUnitCount = 1
                        try self.opFileManager.createDirectory(at: source, withIntermediateDirectories: true, attributes: [:])
                    } else {
                        progress.totalUnitCount = Int64(data?.count ?? 0)
                        try data?.write(to: source, options: .atomic)
                    }
                case .modify:
                    progress.totalUnitCount = Int64(data?.count ?? 0)
                    try data?.write(to: source, options: atomically ? [.atomic] : [])
                case .copy:
                    guard let dest = dest else { return }
                    progress.setUserInfoObject(Progress.FileOperationKind.copying, forKey: .fileOperationKindKey)
                    progress.totalUnitCount = abs(source.fileSize)
                    try self.opFileManager.copyItem(at: source, to: dest)
                case .move:
                    progress.setUserInfoObject(Progress.FileOperationKind.copying, forKey: .fileOperationKindKey)
                    guard let dest = dest else { return }
                    progress.totalUnitCount = abs(source.fileSize)
                    try self.opFileManager.moveItem(at: source, to: dest)
                case.remove:
                    progress.totalUnitCount = abs(source.fileSize)
                    try self.opFileManager.removeItem(at: source)
                default:
                    return
                }
                if successfulSecurityScopedResourceAccess {
                    source.stopAccessingSecurityScopedResource()
                }

                progress.completedUnitCount = progress.totalUnitCount
                self.dispatch_queue.async {
                    completionHandler?(nil)
                }
                self.delegateNotify(operation)
            } catch {
                if successfulSecurityScopedResourceAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                progress.cancel()
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                self.delegateNotify(operation, error: error)
            }
        }
        
        if isCoorinating {
            successfulSecurityScopedResourceAccess = source.startAccessingSecurityScopedResource()
            var intents = [NSFileAccessIntent]()
            switch operation {
            case .create, .modify:
                intents.append(NSFileAccessIntent.writingIntent(with: source, options: .forReplacing))
            case .copy:
                guard let dest = dest else { return nil }
                intents.append(NSFileAccessIntent.readingIntent(with: source, options: forUploading ? .forUploading : .withoutChanges))
                intents.append(NSFileAccessIntent.writingIntent(with: dest, options: .forReplacing))
            case .move:
                guard let dest = dest else { return nil }
                intents.append(NSFileAccessIntent.writingIntent(with: source, options: .forMoving))
                intents.append(NSFileAccessIntent.writingIntent(with: dest, options: .forReplacing))
            case .remove:
                intents.append(NSFileAccessIntent.writingIntent(with: source, options: .forDeleting))
            default:
                return nil
            }
            self.coordinated(intents: intents, operationHandler: operationHandler, errorHandler: { error in
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                self.delegateNotify(operation, error: error)
            })
        } else {
            operation_queue.addOperation {
                operationHandler(source, dest)
            }
        }
        return progress
    }
    
    @discardableResult
    open func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        let operation = FileOperationType.fetch(path: path)
        let url = self.url(of: path)
        
        let progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.isCancellable = false
        progress.setUserInfoObject(Progress.FileOperationKind.receiving, forKey: .fileOperationKindKey)
        progress.setUserInfoObject(url, forKey: .fileURLKey)
        progress.totalUnitCount = url.fileSize
        
        let operationHandler: (URL) -> Void = { url in
            progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
            do {
                let data = try Data(contentsOf: url)
                progress.completedUnitCount = progress.totalUnitCount
                self.dispatch_queue.async {
                    completionHandler(data, nil)
                }
                self.delegateNotify(operation)
            } catch {
                progress.cancel()
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                self.delegateNotify(operation, error: error)
            }
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.readingIntent(with: url, options: .withoutChanges)
            coordinated(intents: [intent], operationHandler: operationHandler, errorHandler: { error in
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                }
                self.delegateNotify(operation, error: error)
            })
        } else {
            dispatch_queue.async {
                operationHandler(url)
            }
        }

        return progress
    }
    
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
            }
            return nil
        }

        if offset == 0 && length < 0 {
            return self.contents(path: path, completionHandler: completionHandler)
        }

        let operation = FileOperationType.fetch(path: path)
        let url = self.url(of: path)
        
        let progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.isCancellable = false
        progress.setUserInfoObject(url, forKey: .fileURLKey)
        progress.setUserInfoObject(Progress.FileOperationKind.receiving, forKey: .fileOperationKindKey)
        
        let operationHandler: (URL) -> Void = { url in
            do {
                guard let handle = FileHandle(forReadingAtPath: url.path) else {
                    throw self.throwError(path, code: CocoaError.fileNoSuchFile)
                }
                
                defer {
                    handle.closeFile()
                }
                
                let size = LocalFileObject(fileWithURL: url)?.size ?? -1
                progress.totalUnitCount = size
                guard size > offset else {
                    progress.cancel()
                    throw self.throwError(path, code: CocoaError.fileReadTooLarge)
                }
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
                handle.seek(toFileOffset: UInt64(offset))
                guard Int64(handle.offsetInFile) == offset else {
                    progress.cancel()
                    throw self.throwError(path, code: CocoaError.fileReadTooLarge)
                }
                
                let data = handle.readData(ofLength: length)
                progress.completedUnitCount = progress.totalUnitCount
                self.dispatch_queue.async {
                    completionHandler(data, nil)
                    self.delegateNotify(operation)
                }
            }
            catch {
                self.dispatch_queue.async {
                    completionHandler(nil, error)
                    self.delegateNotify(operation, error: error)
                }
            }
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.readingIntent(with: url, options: .withoutChanges)
            coordinated(intents: [intent], operationHandler: operationHandler, errorHandler: { error in
                completionHandler(nil, error)
                self.delegateNotify(operation, error: error)
            })
        } else {
            dispatch_queue.async {
                operationHandler(url)
            }
        }
        
        return progress
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let fileExists = ((try? self.url(of: path).checkResourceIsReachable()) ?? false) ||
            ((try? self.url(of: path).checkPromisedItemIsReachable()) ?? false)
        if !overwrite && fileExists {
            let e = self.throwError(path, code: CocoaError.fileWriteFileExists)
            dispatch_queue.async {
                completionHandler?(e)
            }
            self.delegateNotify(.modify(path: path), error: e)
            return nil
        }
        
        let operation: FileOperationType = fileExists ? .modify(path: path) : .create(path: path)
        return self.doOperation(operation, data: data ?? Data(), atomically: atomically, completionHandler: completionHandler)
    }
    
    fileprivate var monitors = [LocalFolderMonitor]()
    
    open func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        self.unregisterNotifcation(path: path)
        let dirurl = self.url(of: path)
        let isdir = (try? dirurl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isdir {
            return
        }
        let monitor = LocalFolderMonitor(url: dirurl) {
            eventHandler()
        }
        monitor.start()
        monitors.append(monitor)
    }
    
    open func unregisterNotifcation(path: String) {
        var removedMonitor: LocalFolderMonitor?
        for (i, monitor) in monitors.enumerated() {
            if self.relativePathOf(url: monitor.url) == path {
                removedMonitor = monitors.remove(at: i)
                break
            }
        }
        removedMonitor?.stop()
    }
    
    open func isRegisteredForNotification(path: String) -> Bool {
        return monitors.map( { self.relativePathOf(url: $0.url) } ).contains(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    
    /**
     Creates a symbolic link at the specified path that points to an item at the given path.
     This method does not traverse symbolic links contained in destination path, making it possible
     to create symbolic links to locations that do not yet exist.
     Also, if the final path component is a symbolic link, that link is not followed.
    
     - Parameters:
       - symbolicLink: The file path at which to create the new symbolic link. The last component of the path issued as the name of the link.
       - withDestinationPath: The path that contains the item to be pointed to by the link. In other words, this is the destination of the link.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
    */
    open func create(symbolicLink path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        operation_queue.addOperation {
            let operation = FileOperationType.link(link: path, target: destPath)
            do {
                try self.opFileManager.createSymbolicLink(at: self.url(of: path), withDestinationURL: self.url(of: destPath))
                completionHandler?(nil)
                self.delegateNotify(operation)
            } catch {
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
            }
        }
    }
    
    /// Returns the path of the item pointed to by a symbolic link.
    ///
    /// - Parameters:
    ///   - path: The path of a file or directory.
    ///   - completionHandler: Returns destination url of given symbolic link, or an `Error` object if it fails.
    open func destination(ofSymbolicLink path: String, completionHandler: @escaping (_ url: URL?, _ error: Error?) -> Void) {
        dispatch_queue.async {
            do {
                let destPath = try self.opFileManager.destinationOfSymbolicLink(atPath: self.url(of: path).path)
                let destUrl = URL(fileURLWithPath: destPath)
                completionHandler(destUrl, nil)
            } catch {
                completionHandler(nil, error)
            }
        }
    }
}

internal extension LocalFileProvider {
    func coordinated(intents: [NSFileAccessIntent], operationHandler: @escaping (_ url: URL) -> Void, errorHandler: ((_ error: Error) -> Void)? = nil) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(with: intents, queue: operation_queue) { (error) in
            if let error = error {
                errorHandler?(error)
                return
            }
            operationHandler(intents.first!.url)
        }
    }
    
    func coordinated(intents: [NSFileAccessIntent], moving: Bool = false, operationHandler: @escaping (_ sourceUrl: URL, _ destURL: URL?) -> Void, errorHandler:  ((_ error: Error) -> Void)? = nil) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(with: intents, queue: operation_queue) { (error) in
            if let error = error {
                errorHandler?(error)
                return
            }
            guard let newSource: URL = intents.first?.url else { return }
            let newDest: URL? = intents.dropFirst().first?.url
            if moving, let newDest = newDest {
                coordinator.item(at: newSource, willMoveTo: newDest)
            }
            operationHandler(newSource, newDest)
            if moving, let newDest = newDest {
                coordinator.item(at: newSource, didMoveTo: newDest)
            }
        }
    }
}
