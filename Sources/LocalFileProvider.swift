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
open class LocalFileProvider: NSObject, FileProvider, FileProviderMonitor, FileProviderSymbolicLink {
    open class var type: String { return "Local" }
    open fileprivate(set) var baseURL: URL?
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue
    open weak var delegate: FileProviderDelegate?
    open var credential: URLCredential?
    
    /// Underlying `FileManager` object for listing and metadata fetching.
    open private(set) var fileManager = FileManager()
    /// Underlying `FileManager` object for operationa like copying, moving, etc.
    open private(set) var opFileManager = FileManager()
    fileprivate var fileProviderManagerDelegate: LocalFileProviderManagerDelegate? = nil
    
    #if os(macOS) || os(iOS) || os(tvOS)
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
    #endif
    
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
    
    #if os(macOS) || os(iOS) || os(tvOS)
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
    #endif
    
    /// Initializes provider for the specified local URL.
    ///
    /// - Parameter baseURL: Local URL location for base directory.
    public init (baseURL: URL) {
        guard baseURL.isFileURL else {
            fatalError("Cannot initialize a Local provider from remote URL.")
        }
        self.baseURL = URL(fileURLWithPath: baseURL.path, isDirectory: true)
        self.credential = nil
        self.isCoorinating = false
        
        let queueLabel = "FileProvider.\(Swift.type(of: self).type)"
        dispatch_queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "\(queueLabel).Operation"
        
        super.init()
        
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(of: NSURL.self, forKey: "baseURL") as URL? else {
            if #available(macOS 10.11, iOS 9.0, tvOS 9.0, *) {
                aDecoder.failWithError(CocoaError(.coderValueNotFound,
                                                  userInfo: [NSLocalizedDescriptionKey: "Base URL is not set."]))
            }
            return nil
        }
        self.init(baseURL: baseURL)
        self.isCoorinating = aDecoder.decodeBool(forKey: "isCoorinating")
    }
    
    deinit {
        let monitors = self.monitors
        self.monitors = []
        for monitor in monitors {
            monitor.stop()
        }
    }
    
    open func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.isCoorinating, forKey: "isCoorinating")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = LocalFileProvider(baseURL: self.baseURL!)
        copy.undoManager = self.undoManager
        #if os(macOS) || os(iOS) || os(tvOS)
        copy.isCoorinating = self.isCoorinating
        #endif
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        return copy
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        dispatch_queue.async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.url(of: path), includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants)
                let filesAttributes = contents.compactMap({ (fileURL) -> LocalFileObject? in
                    let path = self.relativePathOf(url: fileURL)
                    return LocalFileObject(fileWithPath: path, relativeTo: self.baseURL)
                })
                completionHandler(filesAttributes, nil)
            } catch {
                completionHandler([], error)
            }
        }
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
        dispatch_queue.async {
            completionHandler(LocalFileObject(fileWithPath: path, relativeTo: self.baseURL), nil)
        }
    }
    
    public func storageProperties(completionHandler: @escaping (_ volumeInfo: VolumeObject?) -> Void) {
        dispatch_queue.async {
            var keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeURLKey, .volumeNameKey, .volumeIsReadOnlyKey, .volumeCreationDateKey]
            if #available(iOS 10.0, macOS 10.12, tvOS 10.0, *) {
                keys.insert(.isEncryptedKey)
            }
            let values: URLResourceValues? = self.baseURL.flatMap { try? $0.resourceValues(forKeys: keys) }
            completionHandler(values.flatMap({ VolumeObject(allValues: $0.allValues) }))
        }
    }
    
    @discardableResult
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let progress = Progress(totalUnitCount: -1)
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
    
    open func isReachable(completionHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        dispatch_queue.async {
            do {
                let isReachable = try self.baseURL!.checkResourceIsReachable()
                completionHandler(isReachable, nil)
            } catch {
                completionHandler(false, error)
            }
        }
    }
    
    open func relativePathOf(url: URL) -> String {
        // check if url derieved from current base url
        let relativePath = url.relativePath
        if !relativePath.isEmpty, url.baseURL == self.baseURL {
            return (relativePath.removingPercentEncoding ?? relativePath).replacingOccurrences(of: "/", with: "", options: .anchored)
        }
        
        guard let baseURL = self.baseURL?.standardizedFileURL else { return url.absoluteString }
        let standardPath = url.absoluteString.replacingOccurrences(of: "file:///private/var/", with: "file:///var/", options: .anchored)
        let standardBase = baseURL.absoluteString.replacingOccurrences(of: "file:///private/var/", with: "file:///var/", options: .anchored)
        let standardRelativePath = standardPath.replacingOccurrences(of: standardBase, with: "/").replacingOccurrences(of: "/", with: "", options: .anchored)
        return standardRelativePath.removingPercentEncoding ?? standardRelativePath
    }
    
    open weak var fileOperationDelegate : FileOperationDelegate?
    
    @discardableResult
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.create(path: atPath.appendingPathComponent(folderName) + "/")
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.move(source: path, destination: toPath)
        return self.doOperation(operation, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: toPath)
        return self.doOperation(operation, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.remove(path: path)
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        return self.doOperation(operation, overwrite: overwrite, forUploading: true, completionHandler: completionHandler)
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        return self.doOperation(operation, completionHandler: completionHandler)
    }
    
    @discardableResult
    fileprivate func doOperation(_ operation: FileOperationType, data: Data? = nil, overwrite: Bool = true, atomically: Bool = false, forUploading: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        let progress = Progress(totalUnitCount: -1)
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
        
        let dest = destPath.map(urlofpath(path:))
        
        if !overwrite, let dest = dest, /* fileExists */ ((try? dest.checkResourceIsReachable()) ?? false) ||
            ((try? dest.checkPromisedItemIsReachable()) ?? false) {
            let e = CocoaError(.fileWriteFileExists, path: destPath!)
            dispatch_queue.async {
                completionHandler?(e)
            }
            self.delegateNotify(operation, error: e)
            return nil
        }
        
        #if os(macOS) || os(iOS) || os(tvOS)
        var successfulSecurityScopedResourceAccess = false
        #endif
        
        let operationHandler: (URL, URL?) -> Void = { source, dest in
            do {
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
                switch operation {
                case .create:
                    if sourcePath.hasSuffix("/") {
                        progress.totalUnitCount = 1
                        try self.opFileManager.createDirectory(at: source, withIntermediateDirectories: true, attributes: [:])
                    } else {
                        progress.totalUnitCount = Int64(data?.count ?? -1)
                        try data?.write(to: source, options: .atomic)
                    }
                case .modify:
                    progress.totalUnitCount = Int64(data?.count ?? -1)
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
                #if os(macOS) || os(iOS) || os(tvOS)
                if successfulSecurityScopedResourceAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                #endif
                
                #if os(macOS) || os(iOS) || os(tvOS)
                self._registerUndo(operation)
                #endif
                progress.completedUnitCount = progress.totalUnitCount
                self.dispatch_queue.async {
                    completionHandler?(nil)
                }
                self.delegateNotify(operation)
            } catch {
                #if os(macOS) || os(iOS) || os(tvOS)
                if successfulSecurityScopedResourceAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                #endif
                progress.cancel()
                self.dispatch_queue.async {
                    completionHandler?(error)
                }
                self.delegateNotify(operation, error: error)
            }
        }
        
        #if os(macOS) || os(iOS) || os(tvOS)
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
            self.coordinated(intents: intents, moving: true, operationHandler: operationHandler, errorHandler: { error in
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
        #else
        operation_queue.addOperation {
            operationHandler(source, dest)
        }
        #endif
        return progress
    }
    
    @discardableResult
    open func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        let operation = FileOperationType.fetch(path: path)
        let url = self.url(of: path)
        
        let progress = Progress(totalUnitCount: url.fileSize)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.isCancellable = false
        progress.setUserInfoObject(Progress.FileOperationKind.receiving, forKey: .fileOperationKindKey)
        progress.setUserInfoObject(url, forKey: .fileURLKey)
        
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
        
        #if os(macOS) || os(iOS) || os(tvOS)
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
        #else
        dispatch_queue.async {
            operationHandler(url)
        }
        #endif

        return progress
    }
    
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping (_ contents: Data?, _ error: Error?) -> Void) -> Progress? {
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
        
        let progress = Progress(totalUnitCount: -1)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.isCancellable = false
        progress.setUserInfoObject(url, forKey: .fileURLKey)
        progress.setUserInfoObject(Progress.FileOperationKind.receiving, forKey: .fileOperationKindKey)
        
        let operationHandler: (URL) -> Void = { url in
            do {
                guard let handle = FileHandle(forReadingAtPath: url.path) else {
                    throw CocoaError(.fileNoSuchFile, path: path)
                }
                
                defer {
                    handle.closeFile()
                }
                
                let size = LocalFileObject(fileWithURL: url)?.size ?? -1
                progress.totalUnitCount = size
                guard size > offset else {
                    progress.cancel()
                    throw CocoaError(.fileReadTooLarge, path: path)
                }
                progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
                handle.seek(toFileOffset: UInt64(offset))
                guard Int64(handle.offsetInFile) == offset else {
                    progress.cancel()
                    throw CocoaError(.fileReadTooLarge, path: path)
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
        
        #if os(macOS) || os(iOS) || os(tvOS)
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
        #else
        dispatch_queue.async {
            operationHandler(url)
        }
        #endif
        return progress
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let fileExists = ((try? self.url(of: path).checkResourceIsReachable()) ?? false) ||
            ((try? self.url(of: path).checkPromisedItemIsReachable()) ?? false)
        if !overwrite && fileExists {
            let e = CocoaError(.fileWriteFileExists, path: path)
            dispatch_queue.async {
                completionHandler?(e)
            }
            self.delegateNotify(.modify(path: path), error: e)
            return nil
        }
        
        let operation: FileOperationType = fileExists ? .modify(path: path) : .create(path: path)
        return self.doOperation(operation, data: data ?? Data(), atomically: atomically, completionHandler: completionHandler)
    }
    
    fileprivate var monitors = [LocalFileMonitor]()
    
    open func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        self.unregisterNotifcation(path: path)
        let url = self.url(of: path)
        if let monitor = LocalFileMonitor(url: url, handler: eventHandler) {
            monitor.start()
            monitors.append(monitor)
        }
    }
    
    open func unregisterNotifcation(path: String) {
        var removedMonitor: LocalFileMonitor?
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
    
    open func create(symbolicLink path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        operation_queue.addOperation {
            let operation = FileOperationType.link(link: path, target: destPath)
            do {
                let url = self.url(of: path)
                let destURL = self.url(of: destPath)
                let homePath = NSHomeDirectory()
                if destURL.path.hasPrefix(homePath) {
                    let canonicalHomePath = "/" + homePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let destRelativePath = destURL.path.replacingOccurrences(of: canonicalHomePath, with: "~", options: .anchored)
                    try self.opFileManager.createSymbolicLink(atPath: url.path, withDestinationPath: destRelativePath)
                } else {
                    try self.opFileManager.createSymbolicLink(at: url, withDestinationURL: destURL)
                }
                completionHandler?(nil)
                self.delegateNotify(operation)
            } catch {
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
            }
        }
    }
    
    open func destination(ofSymbolicLink path: String, completionHandler: @escaping (_ file: FileObject?, _ error: Error?) -> Void) {
        dispatch_queue.async {
            do {
                let destPath = try self.opFileManager.destinationOfSymbolicLink(atPath: self.url(of: path).path)
                let absoluteDestPath = (destPath as NSString).expandingTildeInPath
                let file = LocalFileObject(fileWithPath: absoluteDestPath, relativeTo: self.baseURL)
                completionHandler(file, nil)
            } catch {
                completionHandler(nil, error)
            }
        }
    }
}

#if os(macOS) || os(iOS) || os(tvOS)
extension LocalFileProvider: FileProvideUndoable { }

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
#endif

