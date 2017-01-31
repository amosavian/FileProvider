//
//  LocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

open class LocalFileProvider: FileProvider, FileProviderMonitor {
    open static let type: String = "Local"
    open var isPathRelative: Bool
    open fileprivate(set) var baseURL: URL?
    open var currentPath: String
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue
    open weak var delegate: FileProviderDelegate?
    open internal(set) var credential: URLCredential?
        
    open private(set) var fileManager = FileManager()
    open private(set) var opFileManager = FileManager()
    fileprivate var fileProviderManagerDelegate: LocalFileProviderManagerDelegate? = nil
    
    /// Forces file operations to use NSFileCoordinating, should be set true if:
    /// - Files are on ubiquity(iCloud) container
    /// - Multiple processes are accessing same file, recommended always in macOS and when using app extensions in iOS/tvOS (shared container)
    open var isCoorinating: Bool
    
    /// default values are `directory: .documentDirectory, domainMask: .userDomainMask`
    public convenience init (directory: FileManager.SearchPathDirectory = .documentDirectory, domainMask: FileManager.SearchPathDomainMask = .userDomainMask) {
        self.init(baseURL: FileManager.default.urls(for: directory, in: domainMask).first!)
    }
    
    public convenience init ? (sharedContainerId: String, directory: FileManager.SearchPathDirectory = .userDirectory) {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerId) else {
            return nil
        }
        
        var finalBaseURL = baseURL
        
        switch directory {
        case .documentDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Documents")
        case .libraryDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Library")
        case .cachesDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Library/Caches")
        case .applicationSupportDirectory:
            finalBaseURL = baseURL.appendingPathComponent("Library/Application%20support")
        default:
            break
        }
        
        self.init(baseURL: finalBaseURL)
        
        try? fileManager.createDirectory(at: finalBaseURL, withIntermediateDirectories: true)
    }
    
    public init (baseURL: URL) {
        self.baseURL = baseURL
        self.isPathRelative = true
        self.currentPath = ""
        self.credential = nil
        self.isCoorinating = false
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
        
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
        
    }
    
    @available(*, deprecated, message: "Overriding this method has no effect anymore.")
    open class func defaultBaseURL() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.url(of: path), includingPropertiesForKeys: [.nameKey, .fileSizeKey, .fileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey, .isHiddenKey, .volumeIsReadOnlyKey], options: .skipsSubdirectoryDescendants)
                let filesAttributes = contents.flatMap({ (fileURL) -> LocalFileObject? in
                    let path = self.relativePathOf(url: fileURL)
                    return LocalFileObject(fileWithPath: path, relativeTo: self.baseURL)
                })
                completionHandler(filesAttributes, nil)
            } catch let e {
                completionHandler([], e)
            }
        }
    }
    
    open func storageProperties(completionHandler: (@escaping (_ total: Int64, _ used: Int64) -> Void)) {
        let dict = (try? FileManager.default.attributesOfFileSystem(forPath: baseURL?.path ?? "/"))
        let totalSize = (dict?[.systemSize] as? NSNumber)?.int64Value ?? -1;
        let freeSize = (dict?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0;
        completionHandler(totalSize, totalSize - freeSize)
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        dispatch_queue.async {
            completionHandler(LocalFileObject(fileWithPath: path, relativeTo: self.baseURL), nil)
        }
    }
    
    open weak var fileOperationDelegate : FileOperationDelegate?
    
    @discardableResult
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.create(path: (atPath as NSString).appendingPathComponent(folderName) + "/")
        let url = self.url(of: atPath).appendingPathComponent(folderName)
        
        let operationHandler: (URL) -> Void = { url in
            do {
                try self.opFileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [:])
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.writingIntent(with: url, options: .forReplacing)
            self.coordinated(intents: [intent], completionHandler: operationHandler, errorHandler: { error in
                completionHandler?(error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            })
        } else {
            operation_queue.addOperation {
                operationHandler(url)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func create(file fileName: String, at atPath: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.create(path: (atPath as NSString).appendingPathComponent(fileName))
        let url = self.url(of: atPath).appendingPathComponent(fileName, isDirectory: false)
        
        let operationHandler: (URL) -> Void = { url in
            let success = self.opFileManager.createFile(atPath: url.path, contents: data, attributes: nil)
            if success {
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } else {
                completionHandler?(self.throwError(atPath, code: URLError.cannotCreateFile as FoundationErrorEnum))
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.writingIntent(with:url, options: .forReplacing)
            self.coordinated(intents: [intent], completionHandler: operationHandler, errorHandler: { error in
                completionHandler?(error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            })
        } else {
            operation_queue.addOperation {
                operationHandler(url)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.move(source: path, destination: toPath)
        let sourceUrl = self.url(of: path)
        let destUrl = self.url(of: toPath)
        
        let sourceIntent = NSFileAccessIntent.writingIntent(with: sourceUrl, options: .forDeleting)
        let destIntent = NSFileAccessIntent.writingIntent(with: destUrl, options: .forReplacing)
        
        let operationHandler: (URL, URL) -> Void = { sourceUrl, destUrl in
            if !overwrite && self.fileManager.fileExists(atPath: destUrl.path) {
                completionHandler?(self.throwError(toPath, code: URLError.cannotMoveFile as FoundationErrorEnum))
                return
            }
            do {
                try self.opFileManager.moveItem(at: sourceUrl, to: destUrl)
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        
        if isCoorinating {
            coordinated(intents: [sourceIntent, destIntent], completionHandler: operationHandler) { (error) in
                completionHandler?(error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        } else {
            operation_queue.addOperation {
                operationHandler(sourceUrl, destUrl)
            }
        }
        
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toPath)
        let sourceUrl = self.url(of: path)
        let destUrl = self.url(of: toPath)
        
        let sourceIntent = NSFileAccessIntent.readingIntent(with: sourceUrl, options: .withoutChanges)
        let destIntent = NSFileAccessIntent.writingIntent(with: destUrl, options: .forDeleting)
        
        let operationHandler: (URL, URL) -> Void = { sourceUrl, destUrl in
            if !overwrite && self.fileManager.fileExists(atPath: destUrl.path) {
                completionHandler?(self.throwError(toPath, code: URLError.cannotMoveFile as FoundationErrorEnum))
                return
            }
            do {
                try self.opFileManager.copyItem(at: sourceUrl, to: destUrl)
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        
        if isCoorinating {
            coordinated(intents: [sourceIntent, destIntent], moving: true, completionHandler: operationHandler) { (error) in
                completionHandler?(error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        } else {
            operation_queue.addOperation {
                operationHandler(sourceUrl, destUrl)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.remove(path: path)
        let url = self.url(of: path)
        
        let operationHandler: (URL) -> Void = { url in
            do {
                let successfulSecurityScopedResourceAccess = url.startAccessingSecurityScopedResource()
                try self.opFileManager.removeItem(at: url)
                if successfulSecurityScopedResourceAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.writingIntent(with:url, options: .forReplacing)
            self.coordinated(intents: [intent], completionHandler: operationHandler, errorHandler: { error in
                completionHandler?(error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            })
        } else {
            operation_queue.addOperation {
                operationHandler(url)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // TODO: Make use of overwrite parameter
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        operation_queue.addOperation {
            do {
                try self.opFileManager.copyItem(at: localFile, to: self.url(of: toPath))
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        operation_queue.addOperation {
            do {
                try self.opFileManager.copyItem(at: self.url(of: path), to: toLocalURL)
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let opType = FileOperationType.fetch(path: path)
        let url = self.url(of: path)
        
        let operationHandler: (URL) -> Void = { url in
            let data = self.fileManager.contents(atPath: url.path)
            completionHandler(data, nil)
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.readingIntent(with: url, options: .withoutChanges)
            coordinated(intents: [intent], completionHandler: operationHandler, errorHandler: { error in
                completionHandler(nil, error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            })
        } else {
            dispatch_queue.async {
                operationHandler(url)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        if length < 0 {
            return self.contents(path: path, completionHandler: completionHandler)
        }
        
        let opType = FileOperationType.fetch(path: path)
        let url = self.url(of: path)
        
        let operationHandler: (URL) -> Void = { url in
            guard self.fileManager.fileExists(atPath: url.path) && !url.fileIsDirectory else {
                completionHandler(nil, self.throwError(path, code: URLError.cannotOpenFile as FoundationErrorEnum))
                return
            }
            guard let handle = FileHandle(forReadingAtPath: url.path) else {
                completionHandler(nil, self.throwError(path, code: URLError.cannotOpenFile as FoundationErrorEnum))
                return
            }
            defer {
                handle.closeFile()
            }
            handle.seek(toFileOffset: UInt64(offset))
            let data = handle.readData(ofLength: length)
            completionHandler(data, nil)
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.readingIntent(with: url, options: .withoutChanges)
            coordinated(intents: [intent], completionHandler: operationHandler, errorHandler: { error in
                completionHandler(nil, error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            })
        } else {
            dispatch_queue.async {
                operationHandler(url)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        let url = self.url(of: path)
        var options: Data.WritingOptions = []
        if atomically {
            options.insert(.atomic)
        }
        if overwrite {
            options.insert(.withoutOverwriting)
        }
        
        let operationHandler: (URL) -> Void = { url in
            do {
                try data.write(to: url, options: atomically ? [.atomic] : [])
                completionHandler?(nil)
                DispatchQueue.main.async{
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            }
        }
        
        if isCoorinating {
            let intent = NSFileAccessIntent.writingIntent(with: url, options: .forReplacing)
            coordinated(intents: [intent], completionHandler: operationHandler, errorHandler: { error in
                completionHandler?(error)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                }
            })
        } else {
            operation_queue.addOperation {
                operationHandler(url)
            }
        }
        
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    open func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async { 
            let iterator = self.fileManager.enumerator(at: self.url(of: path), includingPropertiesForKeys: nil, options: recursive ? [] : [.skipsSubdirectoryDescendants, .skipsPackageDescendants]) { (url, e) -> Bool in
                completionHandler([], e)
                return true
            }
            var result = [LocalFileObject]()
            while let fileURL = iterator?.nextObject() as? URL {
                if fileURL.lastPathComponent.lowercased().contains(query.lowercased()) {
                    let path = self.relativePathOf(url: fileURL)
                    if let fileObject = LocalFileObject(fileWithPath: path, relativeTo: self.baseURL) {
                        result.append(fileObject)
                        foundItemHandler?(fileObject)
                    }
                }
            }
            completionHandler(result, nil)
        }
    }
    
    fileprivate var monitors = [LocalFolderMonitor]()
    
    open func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        self.unregisterNotifcation(path: path)
        let dirurl = self.url(of: path)
        let isdir = (try? dirurl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false) ?? false
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
        return monitors.map( { self.relativePathOf(url: $0.url) } ).contains(path)
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = LocalFileProvider(baseURL: self.baseURL!)
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.isPathRelative = self.isPathRelative
        return copy
    }
}

public extension LocalFileProvider {
    public func create(symbolicLink path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        operation_queue.addOperation {
            do {
                try self.opFileManager.createSymbolicLink(at: self.url(of: path), withDestinationURL: self.url(of: destPath))
                completionHandler?(nil)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderSucceed(self, operation: .link(link: path, target: destPath))
                }
            } catch let e {
                completionHandler?(e)
                DispatchQueue.main.async {
                    self.delegate?.fileproviderFailed(self, operation: .link(link: path, target: destPath))
                }
            }
        }
    }
    
    public func destination(ofSymbolicLink path: String, completionHandler: @escaping (_ url: URL?, _ error: Error?) -> Void) {
        dispatch_queue.async {
            do {
                let destPath = try self.opFileManager.destinationOfSymbolicLink(atPath: self.url(of: path).path)
                let destUrl = URL(fileURLWithPath: destPath)
                completionHandler(destUrl, nil)
            } catch let e{
                completionHandler(nil, e)
            }
        }
    }
}

internal extension LocalFileProvider {
    func coordinated(intents: [NSFileAccessIntent], completionHandler: @escaping (_ url: URL) -> Void, errorHandler: ((_ error: Error) -> Void)? = nil) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(with: intents, queue: operation_queue) { (error) in
            if let error = error {
                errorHandler?(error)
                return
            }
            completionHandler(intents[0].url)
        }
    }
    
    func coordinated(intents: [NSFileAccessIntent], moving: Bool = false, completionHandler: @escaping (_ sourceUrl: URL, _ destURL: URL) -> Void, errorHandler:  ((_ error: Error) -> Void)? = nil) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(with: intents, queue: operation_queue) { (error) in
            if let error = error {
                errorHandler?(error)
                return
            }
            if moving {
                coordinator.item(at: intents[0].url, willMoveTo: intents[1].url)
            }
            completionHandler(intents[0].url, intents[1].url)
            if moving {
                coordinator.item(at: intents[0].url, didMoveTo: intents[1].url)
            }
        }
    }
}
