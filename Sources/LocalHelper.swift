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
    internal override init(url: URL?, name: String, path: String) {
        super.init(url: url, name: name, path: path)
    }
    
    /// Initiates a `LocalFileObject` with attributes of file in path.
    public convenience init? (fileWithPath path: String, relativeTo relativeURL: URL?) {
        var fileURL: URL?
        var rpath = path.replacingOccurrences(of: relativeURL?.path ?? "", with: "", options: .anchored).replacingOccurrences(of: "/", with: "", options: .anchored)
        if #available(iOS 9.0, macOS 10.11, *) {
            fileURL = URL(fileURLWithPath: rpath, relativeTo: relativeURL)
        } else {
            rpath = rpath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rpath
            fileURL = URL(string: rpath, relativeTo: relativeURL) ?? relativeURL
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
    
    /// Count of children items of a driectory. It costs disk access for local directories.
    open public(set) override var childrensCount: Int? {
        get {
            return try? FileManager.default.contentsOfDirectory(atPath: self.url.path).count
        }
        set {
            //
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

#if os(macOS) || os(iOS) || os(tvOS)
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
#endif
