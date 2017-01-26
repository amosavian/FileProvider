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
    open var operation_queue: DispatchQueue
    open weak var delegate: FileProviderDelegate?
    open fileprivate(set) var credential: URLCredential?
        
    open private(set) var fileManager = FileManager()
    open private(set) var opFileManager = FileManager()
    fileprivate var fileProviderManagerDelegate: LocalFileProviderManagerDelegate? = nil
    
    /// default values are `directory: .documentDirectory, domainMask: .userDomainMask`
    public convenience init (directory: FileManager.SearchPathDirectory = .documentDirectory, domainMask: FileManager.SearchPathDomainMask = .userDomainMask) {
        self.init(baseURL: FileManager.default.urls(for: directory, in: domainMask).first!)
    }
    
    public init (baseURL: URL) {
        self.baseURL = baseURL
        self.isPathRelative = true
        self.currentPath = ""
        self.credential = nil
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(LocalFileProvider.type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = DispatchQueue(label: "FileProvider.\(LocalFileProvider.type).Operation", attributes: [])
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    open class func defaultBaseURL() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.absoluteURL(path), includingPropertiesForKeys: [.nameKey, .fileSizeKey, .fileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey, .isHiddenKey, .volumeIsReadOnlyKey], options: .skipsSubdirectoryDescendants)
                let filesAttributes = contents.flatMap({ (fileURL) -> LocalFileObject? in
                    let path = self.relativePathOf(url: fileURL)
                    return LocalFileObject(fileWithPath: path, relativeTo: self.baseURL)
                })
                completionHandler(filesAttributes, nil)
            } catch let e as NSError {
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
        operation_queue.async {
            do {
                try self.opFileManager.createDirectory(at: self.absoluteURL(atPath).appendingPathComponent(folderName), withIntermediateDirectories: true, attributes: [:])
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func create(file fileName: String, at atPath: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.create(path: (atPath as NSString).appendingPathComponent(fileName))
        operation_queue.async {
            let fileURL = self.absoluteURL(atPath).appendingPathComponent(fileName)
            let success = self.opFileManager.createFile(atPath: fileURL.path, contents: data, attributes: nil)
            if success {
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } else {
                completionHandler?(self.throwError(atPath, code: URLError.cannotCreateFile as FoundationErrorEnum))
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.move(source: path, destination: toPath)
        operation_queue.async {
            if !overwrite && self.fileManager.fileExists(atPath: self.absoluteURL(toPath).path) {
                completionHandler?(self.throwError(toPath, code: URLError.cannotMoveFile as FoundationErrorEnum))
                return
            }
            do {
                try self.opFileManager.moveItem(at: self.absoluteURL(path), to: self.absoluteURL(toPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toPath)
        operation_queue.async {
            if !overwrite && self.fileManager.fileExists(atPath: self.absoluteURL(toPath).path) {
                completionHandler?(self.throwError(toPath, code: URLError.cannotWriteToFile as FoundationErrorEnum))
                return
            }
            do {
                try self.opFileManager.copyItem(at: self.absoluteURL(path), to: self.absoluteURL(toPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.remove(path: path)
        operation_queue.async {
            do {
                try self.opFileManager.removeItem(at: self.absoluteURL(path))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // TODO: Make use of overwrite parameter
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        operation_queue.async {
            do {
                try self.opFileManager.copyItem(at: localFile, to: self.absoluteURL(toPath))
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        operation_queue.async {
            do {
                try self.opFileManager.copyItem(at: self.absoluteURL(path), to: toLocalURL)
                completionHandler?(nil)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderSucceed(self, operation: opType)
                })
            } catch let e as NSError {
                completionHandler?(e)
                DispatchQueue.main.async(execute: {
                    self.delegate?.fileproviderFailed(self, operation: opType)
                })
            }
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
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
        if length < 0 {
            return self.contents(path: path, completionHandler: completionHandler)
        }
        let opType = FileOperationType.fetch(path: path)
        dispatch_queue.async {
            let aPath = self.absoluteURL(path).path
            guard self.fileManager.fileExists(atPath: aPath) && !self.absoluteURL(path).fileIsDirectory else {
                completionHandler(nil, self.throwError(path, code: URLError.cannotOpenFile as FoundationErrorEnum))
                return
            }
            guard let handle = FileHandle(forReadingAtPath: aPath) else {
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
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        var options: Data.WritingOptions = []
        if atomically {
            options.insert(.atomic)
        }
        if overwrite {
            options.insert(.withoutOverwriting)
        }
        operation_queue.async {
            try? data.write(to: self.absoluteURL(path), options: atomically ? [.atomic] : [])
            DispatchQueue.main.async(execute: {
                self.delegate?.fileproviderSucceed(self, operation: opType)
            })
        }
        return LocalOperationHandle(operationType: opType, baseURL: self.baseURL)
    }
    
    open func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async { 
            let iterator = self.fileManager.enumerator(at: self.absoluteURL(path), includingPropertiesForKeys: nil, options: recursive ? [] : [.skipsSubdirectoryDescendants, .skipsPackageDescendants]) { (url, e) -> Bool in
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
        let absurl = self.absoluteURL(path)
        let isdir = (try? absurl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false) ?? false
        if !isdir {
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

class CloudFileProvider: LocalFileProvider {
    // FIXME: convert static var type to class var in next Swift version
    
    open var type: String { return "iCloudDrive" }
    
    public init? (containerId: String?) {
        assert(!Thread.isMainThread, "LocalFileProvider.init(containerId:) is not recommended to be executed on Main Thread.")
        guard FileManager.default.ubiquityIdentityToken == nil else {
            return nil
        }
        guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId) else {
            return nil
        }
        super.init(baseURL: ubiquityURL.appendingPathComponent("Documents"))
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(self.type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = DispatchQueue(label: "FileProvider.\(self.type).Operation", attributes: [])
        
        fileManager.url(forUbiquityContainerIdentifier: containerId)
        opFileManager.url(forUbiquityContainerIdentifier: containerId)
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    open override static func defaultBaseURL() -> URL {
        return FileManager.default.url(forUbiquityContainerIdentifier: nil) ?? super.defaultBaseURL()
    }

}
