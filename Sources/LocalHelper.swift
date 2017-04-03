//
//  LocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/// Containts path, url and attributes of a local file or resource.
public final class LocalFileObject: FileObject {
    internal override init(url: URL, name: String, path: String) {
        super.init(url: url, name: name, path: path)
    }
    
    /// Initiates a `LocalFileObject` with attributes of file in path.
    public convenience init? (fileWithPath path: String, relativeTo relativeURL: URL?) {
        var fileURL: URL?
        var rpath = path.replacingOccurrences(of: relativeURL?.path ?? "", with: "", options: .anchored)
        if relativeURL != nil && rpath.hasPrefix("/") {
            rpath.remove(at: rpath.startIndex)
        }
        if #available(iOS 9.0, macOS 10.11, tvOS 9.0, *) {
            fileURL = URL(fileURLWithPath: rpath, relativeTo: relativeURL)
        } else {
            fileURL = URL(string: rpath.isEmpty ? "./" : rpath, relativeTo: relativeURL)
        }
        
        if let fileURL = fileURL {
            self.init(fileWithURL: fileURL)
        } else {
            return nil
        }
    }
    
    /// Initiates a `LocalFileObject` with attributes of file in url.
    public convenience init?(fileWithURL fileURL: URL) {
        do {
            let values = try fileURL.resourceValues(forKeys: [.nameKey, .fileSizeKey, .totalFileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey, .fileResourceTypeKey, .isHiddenKey, .isWritableKey, .typeIdentifierKey, .generationIdentifierKey, .documentIdentifierKey])
            let path = fileURL.relativePath.hasPrefix("/") ? fileURL.relativePath : "/" + fileURL.relativePath
            
            self.init(url: fileURL, name: values.name ?? fileURL.lastPathComponent, path: path)
            for (key, value) in values.allValues {
                self.allValues[key] = value
            }
        } catch {
            return nil
        }
    }
    
    /// The total size allocated on disk for the file
    open internal(set) var allocatedSize: Int64 {
        get {
            return allValues[.fileAllocatedSizeKey] as? Int64 ?? 0
        }
        set {
            allValues[.fileAllocatedSizeKey] = Int(exactly: newValue) ?? Int.max
        }
    }
    
    /// The document identifier is a value assigned by the kernel/system to a file or directory. 
    /// This value is used to identify the document regardless of where it is moved on a volume. 
    /// The identifier persists across system restarts.
    open internal(set) var id: Int? {
        get {
            return allValues[.documentIdentifierKey] as? Int
        }
        set {
            allValues[.documentIdentifierKey] = newValue
        }
    }
    
    /// The revision of file, which changes when a file contents are modified. 
    /// Changes to attributes or other file metadata do not change the identifier.
    open var rev: String? {
        get {
            let data = allValues[.generationIdentifierKey] as? Data
            return data?.map { String(format: "%02hhx", $0) }.joined()
        }
    }
}

internal final class LocalFolderMonitor {
    fileprivate let source: DispatchSourceFileSystemObject
    fileprivate let descriptor: CInt
    fileprivate let qq: DispatchQueue = DispatchQueue.global(qos: .default)
    fileprivate var state: Bool = false
    fileprivate var monitoredTime: TimeInterval = Date().timeIntervalSinceReferenceDate
    var url: URL
    
    /// Creates a folder monitor object with monitoring enabled.
    init(url: URL, handler: @escaping ()->Void) {
        self.url = url
        descriptor = open((url as NSURL).fileSystemRepresentation, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: qq)
        // Folder monitoring is recursive and deep. Monitoring a root folder may be very costly
        // We have a 0.2 second delay to ensure we wont call handler 1000s times when there is
        // a huge file operation. This ensures app will work smoothly while this 250 milisec won't
        // affect user experince much
        let main_handler: ()->Void = { [weak self] in
            guard let `self` = self else { return }
            if Date().timeIntervalSinceReferenceDate < self.monitoredTime + 0.2 {
                return
            }
            self.monitoredTime = Date().timeIntervalSinceReferenceDate
            self.source.suspend()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
                handler()
                self.source.resume()
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

/// - Note: Local operation handling is limited. Please don't use as much as possible.
open class LocalOperationHandle: OperationHandle {
    /// Url of file which operation is doing on
    public let baseURL: URL
    /// Type of operation
    public let operationType: FileOperationType
    
    init (operationType: FileOperationType, baseURL: URL?) {
        self.baseURL = baseURL ?? URL(fileURLWithPath: "/")
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
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
            let isdir = values.isDirectory ?? false
            let size = Int64(values.fileSize ?? 0)
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

class UndoBox: NSObject {
    weak var provider: FileProvideUndoable?
    let operation: FileOperationType
    let undoOperation: FileOperationType
    
    init(provider: FileProvideUndoable, operation: FileOperationType, undoOperation: FileOperationType) {
        self.provider = provider
        self.operation = operation
        self.undoOperation = undoOperation
    }
}
