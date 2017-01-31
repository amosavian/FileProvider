//
//  LocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public final class LocalFileObject: FileObject {
    internal override init(url: URL, name: String, path: String) {
        super.init(url: url, name: name, path: path)
    }
    
    public convenience init? (fileWithPath path: String, relativeTo relativeURL: URL?) {
        let fileURL: URL
        var rpath = path.replacingOccurrences(of: relativeURL?.absoluteString  ?? "", with: "")
        if path.hasPrefix("/") {
            rpath.remove(at: rpath.startIndex)
        }
        if rpath.isEmpty {
            fileURL = relativeURL ?? URL(fileURLWithPath: path)
        } else {
            if #available(iOS 9.0, macOS 10.11, tvOS 9.0, *) {
                fileURL = URL(fileURLWithPath: rpath, relativeTo: relativeURL)
            } else {
                fileURL = relativeURL?.appendingPathComponent(path) ?? URL(fileURLWithPath: path)
            }
        }
        self.init(fileWithURL: fileURL)
    }
    
    public convenience init?(fileWithURL fileURL: URL) {
        do {
            let values = try fileURL.resourceValues(forKeys: [.nameKey, .fileSizeKey, .fileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey, .fileResourceTypeKey, .isHiddenKey, .isWritableKey, .typeIdentifierKey])
            self.init(url: fileURL, name: values.name ?? fileURL.lastPathComponent, path: fileURL.path)
            for (key, value) in values.allValues {
                self.allValues[key.rawValue] = value
            }
        } catch {
            return nil
        }
    }
    
    open internal(set) var allocatedSize: Int64 {
        get {
            return allValues[URLResourceKey.fileAllocatedSizeKey.rawValue] as? Int64 ?? 0
        }
        set {
            allValues[URLResourceKey.fileAllocatedSizeKey.rawValue] = Int(exactly: newValue) ?? Int.max
        }
    }
}

internal class LocalFolderMonitor {
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

open class LocalOperationHandle: OperationHandle {
    public let baseURL: URL
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
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isdir = values.isDirectory ?? false
                let size = Int64(values.fileSize ?? 0)
                if isdir {
                    folders += 1
                } else {
                    files += 1
                }
                totalsize += size
            } catch _ {
            }
        }
        
        return (folders, files, totalsize)
        
    }
}

internal extension URL {
    var fileIsDirectory: Bool {
        return (try? self.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
    
    var fileSize: Int64 {
        return Int64((try? self.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1)
    }
    
    var fileExists: Bool {
        return self.isFileURL && FileManager.default.fileExists(atPath: self.path)
    }
}
