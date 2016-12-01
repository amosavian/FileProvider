//
//  LocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public final class LocalFileObject: FileObject {
    public let allocatedSize: Int64
    // codebeat:disable[ARITY]
    public init(absoluteURL: URL, name: String, path: String, size: Int64 = -1, allocatedSize: Int64 = 0, createdDate: Date? = nil, modifiedDate: Date? = nil, fileType: FileType = .regular, isHidden: Bool = false, isReadOnly: Bool = false) {
        self.allocatedSize = allocatedSize
        super.init(absoluteURL: absoluteURL, name: name, path: path, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
    // codebeat:enable[ARITY]
}

open class LocalFileProvider: FileProvider, FileProviderMonitor {
    open static let type = "Local"
    open var isPathRelative: Bool = true
    open var baseURL: URL? = LocalFileProvider.defaultBaseURL()
    open var currentPath: String = ""
    open var dispatch_queue: DispatchQueue
    open var operation_queue: DispatchQueue
    open weak var delegate: FileProviderDelegate?
    open let credential: URLCredential? = nil
        
    open private(set) var fileManager = FileManager()
    open private(set) var opFileManager = FileManager()
    fileprivate var fileProviderManagerDelegate: LocalFileProviderManagerDelegate? = nil
    
    public init () {
        dispatch_queue = DispatchQueue(label: "FileProvider.\(LocalFileProvider.type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = DispatchQueue(label: "FileProvider.\(LocalFileProvider.type).Operation", attributes: [])
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    public init (baseURL: URL) {
        self.baseURL = baseURL
        dispatch_queue = DispatchQueue(label: "FileProvider.\(LocalFileProvider.type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = DispatchQueue(label: "FileProvider.\(LocalFileProvider.type).Operation", attributes: [])
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    fileprivate static func defaultBaseURL() -> URL {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true);
        return URL(fileURLWithPath: paths[0])
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.absoluteURL(path), includingPropertiesForKeys: [URLResourceKey.nameKey, URLResourceKey.fileSizeKey, URLResourceKey.fileAllocatedSizeKey, URLResourceKey.creationDateKey, URLResourceKey.contentModificationDateKey, URLResourceKey.isHiddenKey, URLResourceKey.volumeIsReadOnlyKey], options: FileManager.DirectoryEnumerationOptions.skipsSubdirectoryDescendants)
                let filesAttributes = contents.map({ (fileURL) -> LocalFileObject in
                    return self.attributesOfItem(url: fileURL)
                })
                completionHandler(filesAttributes, nil)
            } catch let e as NSError {
                completionHandler([], e)
            }
        }
    }
    
    internal func attributesOfItem(url fileURL: URL) -> LocalFileObject {
        var namev, sizev, allocated, filetypev, creationDatev, modifiedDatev, hiddenv, readonlyv: AnyObject?
        _ = try? (fileURL as NSURL).getResourceValue(&namev, forKey: URLResourceKey.nameKey)
        _ = try? (fileURL as NSURL).getResourceValue(&sizev, forKey: URLResourceKey.fileSizeKey)
        _ = try? (fileURL as NSURL).getResourceValue(&allocated, forKey: URLResourceKey.fileAllocatedSizeKey)
        _ = try? (fileURL as NSURL).getResourceValue(&creationDatev, forKey: URLResourceKey.creationDateKey)
        _ = try? (fileURL as NSURL).getResourceValue(&modifiedDatev, forKey: URLResourceKey.contentModificationDateKey)
        _ = try? (fileURL as NSURL).getResourceValue(&filetypev, forKey: URLResourceKey.fileResourceTypeKey)
        _ = try? (fileURL as NSURL).getResourceValue(&hiddenv, forKey: URLResourceKey.isHiddenKey)
        _ = try? (fileURL as NSURL).getResourceValue(&readonlyv, forKey: URLResourceKey.volumeIsReadOnlyKey)
        let path: String
        if isPathRelative {
            path = self.relativePathOf(url: fileURL)
        } else {
            path = fileURL.path
        }
        let filetype = URLFileResourceType(rawValue: filetypev as? String ?? "")
        let fileAttr = LocalFileObject(absoluteURL: fileURL, name: namev as! String, path: path, size: sizev?.int64Value ?? -1, allocatedSize: allocated?.int64Value ?? -1, createdDate: creationDatev as? Date, modifiedDate: modifiedDatev as? Date, fileType: FileType(urlResourceTypeValue: filetype), isHidden: hiddenv?.boolValue ?? false, isReadOnly: readonlyv?.boolValue ?? false)
        return fileAttr
    }
    
    open func storageProperties(completionHandler: (@escaping (_ total: Int64, _ used: Int64) -> Void)) {
        let dict = (try? FileManager.default.attributesOfFileSystem(forPath: baseURL?.path ?? "/"))
        let totalSize = (dict?[FileAttributeKey.systemSize] as? NSNumber)?.int64Value ?? -1;
        let freeSize = (dict?[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value ?? 0;
        completionHandler(totalSize, totalSize - freeSize)
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        dispatch_queue.async {
            completionHandler(self.attributesOfItem(url: self.absoluteURL(path)), nil)
        }
    }
    
    open weak var fileOperationDelegate : FileOperationDelegate?
    
    @discardableResult
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        operation_queue.async {
            do {
                try self.opFileManager.createDirectory(at: self.absoluteURL(atPath).appendingPathComponent(folderName), withIntermediateDirectories: true, attributes: [:])
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .create(path: (atPath as NSString).appendingPathComponent(folderName) + "/"))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .create(path: (atPath as NSString).appendingPathComponent(folderName) + "/"))
                })
            }
        }
        return LocalOperationHandle(operationType: .create(path: (atPath as NSString).appendingPathComponent(folderName)), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func create(file fileAttribs: FileObject, at atPath: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        operation_queue.async {
            let fileURL = self.absoluteURL(atPath).appendingPathComponent(fileAttribs.name)
            var attributes = [String : Any]()
            if let createdDate = fileAttribs.createdDate {
                attributes[FileAttributeKey.creationDate.rawValue] = createdDate as NSDate
            }
            if let modDate = fileAttribs.modifiedDate {
                attributes[FileAttributeKey.modificationDate.rawValue] = modDate as NSDate
            }
            if fileAttribs.isReadOnly {
                attributes[FileAttributeKey.posixPermissions.rawValue] = NSNumber(value: 365 as Int16)
            }
            let success = self.opFileManager.createFile(atPath: fileURL.path, contents: data, attributes: attributes)
            if success {
                do {
                    try (fileURL as NSURL).setResourceValue(fileAttribs.isHidden, forKey: URLResourceKey.isHiddenKey)
                } catch _ {}
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .create(path: (atPath as NSString).appendingPathComponent(fileAttribs.name)))
                })
            } else {
                completionHandler?(self.throwError(atPath, code: URLError.cannotCreateFile as FoundationErrorEnum))
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .create(path: (atPath as NSString).appendingPathComponent(fileAttribs.name)))
                })
            }
        }
        return LocalOperationHandle(operationType: .create(path: (atPath as NSString).appendingPathComponent(fileAttribs.name)), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // FIXME: progress
        operation_queue.async {
            if !overwrite && self.fileManager.fileExists(atPath: self.absoluteURL(toPath).path) {
                completionHandler?(self.throwError(toPath, code: URLError.cannotMoveFile as FoundationErrorEnum))
                return
            }
            do {
                try self.opFileManager.moveItem(at: self.absoluteURL(path), to: self.absoluteURL(toPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .move(source: path, destination: toPath))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .move(source: path, destination: toPath))
                })
            }
        }
        return LocalOperationHandle(operationType: .move(source: path, destination: toPath), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // FIXME: progress, for files > 100mb, monitor file by another thread, for dirs check copied items count
        operation_queue.async {
            if !overwrite && self.fileManager.fileExists(atPath: self.absoluteURL(toPath).path) {
                completionHandler?(self.throwError(toPath, code: URLError.cannotWriteToFile as FoundationErrorEnum))
                return
            }
            do {
                try self.opFileManager.copyItem(at: self.absoluteURL(path), to: self.absoluteURL(toPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .copy(source: path, destination: toPath))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .copy(source: path, destination: toPath))
                })
            }
        }
        return LocalOperationHandle(operationType: .copy(source: path, destination: toPath), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        operation_queue.async {
            do {
                try self.opFileManager.removeItem(at: self.absoluteURL(path))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .remove(path: path))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .remove(path: path))
                })
            }
        }
        return LocalOperationHandle(operationType: .remove(path: path), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(localFile: URL, to toPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        operation_queue.async {
            do {
                try self.opFileManager.copyItem(at: localFile, to: self.absoluteURL(toPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .copy(source: localFile.absoluteString, destination: toPath))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .copy(source: localFile.absoluteString, destination: toPath))
                })
            }
        }
        return LocalOperationHandle(operationType: .move(source: localFile.absoluteString, destination: toPath), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        operation_queue.async {
            do {
                try self.opFileManager.copyItem(at: self.absoluteURL(path), to: toLocalURL)
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .copy(source: path, destination: toLocalURL.absoluteString))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .copy(source: path, destination: toLocalURL.absoluteString))
                })
            }
        }
        return LocalOperationHandle(operationType: .move(source: path, destination: toLocalURL.absoluteString), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        dispatch_queue.async {
            let data = self.fileManager.contents(atPath: self.absoluteURL(path).path)
            completionHandler(data, nil)
        }
        return nil
    }
    
    @discardableResult
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        // Unfortunatlely there is no method provided in NSFileManager to read a segment of file.
        // So we have to fallback to POSIX provided methods
        dispatch_queue.async {
            let aPath = self.absoluteURL(path).path
            guard !self.attributesOfItem(url: self.absoluteURL(path)).isDirectory && self.fileManager.fileExists(atPath: aPath) else {
                completionHandler(nil, self.throwError(path, code: URLError.cannotOpenFile as FoundationErrorEnum))
                return
            }
            let fd_from = open(aPath, O_RDONLY)
            if fd_from < 0 {
                completionHandler(nil, self.throwError(path, code: URLError.cannotOpenFile as FoundationErrorEnum))
                return
            }
            defer { precondition(close(fd_from) >= 0) }
            lseek(fd_from, offset, SEEK_SET)
            var buf = [UInt8](repeating: 0, count: length)
            let nread = read(fd_from, &buf, buf.count)
            if nread < 0 {
                completionHandler(nil, self.throwError(path, code: URLError.noPermissionsToReadFile as FoundationErrorEnum))
            } else if nread == 0 {
                completionHandler(nil, nil)
            } else {
                let data = Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(&buf), count: nread, deallocator: .free)
                completionHandler(data, nil)
            }
        }
        return LocalOperationHandle(operationType: .fetch(path: path), baseURL: self.baseURL)
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data, atomically: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        operation_queue.async {
            try? data.write(to: self.absoluteURL(path), options: atomically ? [.atomic] : [])
            DispatchQueue.main.async(execute: {
                self.delegate?.fileproviderSucceed(self, operation: .modify(path: path))
            })
        }
        return LocalOperationHandle(operationType: .modify(path: path), baseURL: self.baseURL)
    }
    
    open func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async { 
            let iterator = self.fileManager.enumerator(at: self.absoluteURL(path), includingPropertiesForKeys: nil, options: recursive ? FileManager.DirectoryEnumerationOptions() : .skipsSubdirectoryDescendants) { (url, e) -> Bool in
                completionHandler([], e)
                return true
            }
            var result = [LocalFileObject]()
            while let fileURL = iterator?.nextObject() as? URL {
                if fileURL.lastPathComponent.lowercased().contains(query.lowercased()) {
                    let fileObject = self.attributesOfItem(url: fileURL)
                    result.append(self.attributesOfItem(url: fileURL))
                    foundItemHandler?(fileObject)
                }
            }
            completionHandler(result, nil)
        }
    }
    
    fileprivate var monitors = [LocalFolderMonitor]()
    
    open func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        self.unregisterNotifcation(path: path)
        let absurl = self.absoluteURL(path)
        var isdirv: AnyObject?
        do {
            try (absurl as NSURL).getResourceValue(&isdirv, forKey: URLResourceKey.isDirectoryKey)
        } catch _ {
        }
        if !(isdirv?.boolValue ?? false) {
            return
        }
        let monitor = LocalFolderMonitor(url: absurl) {
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
        operation_queue.async {
            do {
                try self.opFileManager.createSymbolicLink(at: self.absoluteURL(path), withDestinationURL: self.absoluteURL(destPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: .link(link: path, target: destPath))
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: .link(link: path, target: destPath))
                })
            }
        }
    }
}

internal class LocalFileProviderManagerDelegate: NSObject, FileManagerDelegate {
    weak var provider: LocalFileProvider?
    
    init(provider: LocalFileProvider) {
        self.provider = provider
    }
    
    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return true
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldDoOperation: .copy(source: srcPath, destination: dstPath))
    }
    
    func fileManager(_ fileManager: FileManager, shouldMoveItemAt srcURL: URL, to dstURL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return true
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldDoOperation: .move(source: srcPath, destination: dstPath))
    }
    
    func fileManager(_ fileManager: FileManager, shouldRemoveItemAt URL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return true
        }
        let path = provider.relativePathOf(url: URL)
        return delegate.fileProvider(provider, shouldDoOperation: .remove(path: path))
    }
    
    func fileManager(_ fileManager: FileManager, shouldLinkItemAt srcURL: URL, to dstURL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return true
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldDoOperation: .link(link: srcPath, target: dstPath))
    }
    
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, copyingItemAt srcURL: URL, to dstURL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return false
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .copy(source: srcPath, destination: dstPath))
    }
    
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, movingItemAt srcURL: URL, to dstURL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return false
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .move(source: srcPath, destination: dstPath))
    }
    
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, removingItemAt URL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return false
        }
        let path = provider.relativePathOf(url: URL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .remove(path: path))
    }
    
    func fileManager(_ fileManager: FileManager, shouldProceedAfterError error: Error, linkingItemAt srcURL: URL, to dstURL: URL) -> Bool {
        guard let provider = self.provider, let delegate = provider.fileOperationDelegate else {
            return false
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .link(link: srcPath, target: dstPath))
    }
}

internal class LocalFolderMonitor {
    fileprivate let source: DispatchSourceFileSystemObject
    fileprivate let descriptor: CInt
    fileprivate let qq: DispatchQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.default)
    fileprivate var state: Bool = false
    fileprivate var monitoredTime: TimeInterval = Date().timeIntervalSinceReferenceDate
    var url: URL
    
    /// Creates a folder monitor object with monitoring enabled.
    init(url: URL, handler: @escaping ()->Void) {
        self.url = url
        descriptor = open((url as NSURL).fileSystemRepresentation, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: DispatchSource.FileSystemEvent.write, queue: qq)
        // Folder monitoring is recursive and deep. Monitoring a root folder may be very costly
        // We have a 0.2 second delay to ensure we wont call handler 1000s times when there is
        // a huge file operation. This ensures app will work smoothly while this 250 milisec won't
        // affect user experince much
        let main_handler: ()->Void = {
            if Date().timeIntervalSinceReferenceDate < self.monitoredTime + 0.2 {
                return
            }
            self.monitoredTime = Date().timeIntervalSinceReferenceDate
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.25, execute: {
                handler()
            })
        }
        source.setEventHandler(handler: main_handler)
        source.setCancelHandler {
            close(self.descriptor)
        }
        start()
    }
    
    /// Starts sending notifications if currently stopped
    func start() {
        if !state {
            state = true
            source.resume()
        }
    }
    
    /// Stops sending notifications if currently enabled
    func stop() {
        if state {
            state = false
            source.suspend()
        }
    }
    
    deinit {
        source.cancel()
    }
}

open class LocalOperationHandle: OperationHandle {
    public let baseURL: URL
    public let operationType: FileOperationType
    
    init (operationType: FileOperationType, baseURL: URL?) {
        self.baseURL = baseURL ?? LocalFileProvider.defaultBaseURL()
        self.operationType = operationType
    }
    
    private var sourceURL: URL? {
        guard let source = operationType.source else { return nil }
        return source.hasPrefix("file://") ? URL(fileURLWithPath: source) : baseURL.appendingPathComponent(source)
    }
    
    private var destURL: URL? {
        guard let dest = operationType.destination else { return nil }
        return dest.hasPrefix("file://") ? URL(fileURLWithPath: dest) : baseURL.appendingPathComponent(dest)
    }

    /// Caution: may put pressure on CPU, may have latency
    open var bytesSoFar: Int64 {
        assert(!Thread.isMainThread, "Don't run \(#function) method on main thread")
        switch operationType {
        case .modify:
            guard let url = sourceURL, url.isFileURL else { return 0 }
            if url.fileIsDirectory {
                return iterateDirectory(url, deep: true).totalsize
            } else {
                return url.fileSize
            }
        case .copy, .move:
            guard let url = destURL, url.isFileURL else { return 0 }
            if url.fileIsDirectory {
                return iterateDirectory(url, deep: true).totalsize
            } else {
                return url.fileSize
            }
        default:
            return 0
        }

    }
    
    /// Caution: may put pressure on CPU, may have latency
    open var totalBytes: Int64 {
        assert(!Thread.isMainThread, "Don't run \(#function) method on main thread")
        switch operationType {
        case .copy, .move:
            guard let url = sourceURL, url.isFileURL else { return 0 }
            if url.fileIsDirectory {
                return iterateDirectory(url, deep: true).totalsize
            } else {
                return url.fileSize
            }
        default:
            return 0
        }
    }
    
    /// Not usable in local provider
    open var inProgress: Bool {
        return false
    }
    
    /// Not usable in local provider
    open func cancel() -> Bool{
        return false
    }
    
    func iterateDirectory(_ pathURL: URL, deep: Bool) -> (folders: Int, files: Int, totalsize: Int64) {
        var folders = 0
        var files = 0
        var totalsize: Int64 = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let enumOpt: FileManager.DirectoryEnumerationOptions = !deep ? [.skipsSubdirectoryDescendants, .skipsPackageDescendants] : []

        let fp = FileManager()
        let filesList = fp.enumerator(at: pathURL, includingPropertiesForKeys: keys, options: enumOpt, errorHandler: nil)
        while let fileURL = filesList?.nextObject() as? URL {
            var isdirv, sizev: AnyObject?
            do {
                try (fileURL as NSURL).getResourceValue(&isdirv, forKey: URLResourceKey.isDirectoryKey)
            } catch _ {
            }
            do {
                try (fileURL as NSURL).getResourceValue(&sizev, forKey: URLResourceKey.fileSizeKey)
            } catch _ {
            }
            let isdir = isdirv?.boolValue ?? false
            let size = sizev?.int64Value ?? 0
            if isdir {
                folders += 1
            } else {
                files += 1
            }
            totalsize += size
        }
        
        return (folders, files, totalsize)

    }
}

internal extension URL {
    var fileIsDirectory: Bool {
        var isdirv: AnyObject?
        do {
            try (self as NSURL).getResourceValue(&isdirv, forKey: URLResourceKey.isDirectoryKey)
        } catch _ {
        }
        return isdirv?.boolValue ?? false
    }
    
    var fileSize: Int64 {
        var sizev: AnyObject?
        do {
            try (self as NSURL).getResourceValue(&sizev, forKey: URLResourceKey.fileSizeKey)
        } catch _ {
        }
        return sizev?.int64Value ?? -1
    }
    
    var fileExists: Bool {
        if self.isFileURL {
            return FileManager.default.fileExists(atPath: self.path)
        }
        return false
    }
}
