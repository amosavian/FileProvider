//
//  CloudFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

open class CloudFileProvider: LocalFileProvider {
    
    public var type: String {
        return "iCloudDrive"
    }
    
    /// Actually is readonly
    override open var isCoorinating: Bool {
        get {
            return true
        }
        set {
            return
        }
    }
    
    open var containerId: String?
    
    public init? (containerId: String?) {
        assert(!Thread.isMainThread, "LocalFileProvider.init(containerId:) is not recommended to be executed on Main Thread.")
        guard FileManager.default.ubiquityIdentityToken == nil else {
            return nil
        }
        guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId) else {
            return nil
        }
        self.containerId = containerId
        let baseURL = ubiquityURL.standardized.appendingPathComponent("Documents")
        super.init(baseURL: baseURL)
        self.isCoorinating = true
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(self.type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(self.type).Operation"
        
        fileManager.url(forUbiquityContainerIdentifier: containerId)
        opFileManager.url(forUbiquityContainerIdentifier: containerId)
        
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
    
    open override func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            let pathURL = self.absoluteURL(path)
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, pathURL.path)
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
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
                
                completionHandler(contents, nil)
            })
            query.start()
        }
    }
    
    /// iCloud Storage size and free space is unavailable, it returns local space
    open override func storageProperties(completionHandler: (@escaping (_ total: Int64, _ used: Int64) -> Void)) {
        super.storageProperties(completionHandler: completionHandler)
    }
    
    open override func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        dispatch_queue.async {
            let pathURL = self.absoluteURL(path)
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemPathKey, pathURL.path)
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            var finishObserver: NSObjectProtocol?
            finishObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: nil, using: { (notification) in
                defer {
                    query.stop()
                    NotificationCenter.default.removeObserver(finishObserver!)
                }
                
                query.disableUpdates()
                
                guard let result = (query.results as? [NSMetadataItem])?.first, let attribs = result.values(forAttributes: [NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, NSMetadataItemFSSizeKey, NSMetadataItemContentTypeTreeKey, NSMetadataItemFSCreationDateKey, NSMetadataItemFSContentChangeDateKey]) else {
                    let error = self.throwError(path, code: CocoaError.fileNoSuchFile)
                    completionHandler(nil, error)
                    return
                }
                
                if let file = self.mapFileObject(attributes: attribs) {
                    completionHandler(file, nil)
                } else {
                    let noFileError = self.throwError(path, code: CocoaError.fileNoSuchFile)
                    completionHandler(nil, noFileError)
                }
            })
            query.start()
        }
    }
    
    @discardableResult
    open override func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let r = super.create(folder: folderName, at: atPath, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func create(file fileName: String, at atPath: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let r = super.create(file: fileName, at: atPath, contents: data, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let r = super.moveItem(path: path, to: toPath, overwrite: overwrite, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let r = super.copyItem(path: path, to: toPath, overwrite: overwrite, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let r = super.removeItem(path: path, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        // TODO: Make use of overwrite parameter
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        operation_queue.addOperation {
            let tempFolder: URL
            if #available(iOS 10.0, *) {
                tempFolder = FileManager.default.temporaryDirectory
            } else {
                tempFolder = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            let tmpFile = tempFolder.appendingPathComponent(UUID().uuidString)
            
            do {
                try self.opFileManager.copyItem(at: localFile, to: tmpFile)
                let toUrl = self.absoluteURL(toPath)
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
    
    @discardableResult
    open override func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: toLocalURL.absoluteString)
        
        do {
            try self.opFileManager.startDownloadingUbiquitousItem(at: self.absoluteURL(path))
        } catch let e {
            completionHandler?(e)
            DispatchQueue.main.async(execute: {
                self.delegate?.fileproviderFailed(self, operation: opType)
            })
            return nil
        }
        
        let r = super.copyItem(path: path, toLocalURL: toLocalURL, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let r = super.contents(path: path, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let r = super.contents(path: path, offset: offset, length: length, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    @discardableResult
    open override func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let r = super.writeContents(path: path, contents: data, atomically: atomically, overwrite: overwrite, completionHandler: completionHandler)
        return CloudOperationHandle(operationType: r!.operationType, baseURL: self.baseURL)
    }
    
    open override func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        dispatch_queue.async {
            let pathURL = self.absoluteURL(path)
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "(%K BEGINSWITH %@) && (%K LIKE %@)", NSMetadataItemPathKey, pathURL.path, NSMetadataItemFSNameKey, query)
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            
            var lastReportedCount = 0
            
            if let foundItemHandler = foundItemHandler {
                var updateObserver: NSObjectProtocol?
                
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
                
                completionHandler(contents, nil)
            })
            
            query.start()
        }
    }
    
    fileprivate var monitors = [URL: (NSMetadataQuery, NSObjectProtocol)]()
    //
    open override func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        self.unregisterNotifcation(path: path)
        let pathURL = self.absoluteURL(path)
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "(%K BEGINSWITH %@)", NSMetadataItemPathKey, pathURL.path)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        
        let updateObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: nil, using: { (notification) in
            
            query.disableUpdates()
            
            eventHandler()
            
            query.enableUpdates()
        })
        
        query.start()
        
        monitors[pathURL] = (query, updateObserver)
    }
    
    open override func unregisterNotifcation(path: String) {
        let key = absoluteURL(path)
        guard let (query, observer) = monitors[key] else {
            return
        }
        query.disableUpdates()
        query.stop()
        monitors.removeValue(forKey: key)
        NotificationCenter.default.removeObserver(observer)
    }
    
    open override func isRegisteredForNotification(path: String) -> Bool {
        return monitors[absoluteURL(path)] != nil
    }
    
    /// may return nil
    open override func copy(with zone: NSZone? = nil) -> Any {
        let copy = CloudFileProvider(containerId: self.containerId)
        copy?.currentPath = self.currentPath
        copy?.delegate = self.delegate
        copy?.fileOperationDelegate = self.fileOperationDelegate
        copy?.isPathRelative = self.isPathRelative
        return copy as Any
    }
    
    fileprivate func mapFileObject(attributes attribs: [String: Any]) -> FileObject? {
        guard let url = (attribs[NSMetadataItemURLKey] as? URL)?.standardized, let name = attribs[NSMetadataItemFSNameKey] as? String else {
            return nil
        }
        
        let path = self.relativePathOf(url: url)
        
        let file = FileObject(absoluteURL: url, name: name, path: path)
        
        file.size = (attribs[NSMetadataItemFSSizeKey] as? NSNumber)?.int64Value ?? -1
        file.creationDate = attribs[NSMetadataItemFSCreationDateKey] as? Date
        file.modifiedDate = attribs[NSMetadataItemFSContentChangeDateKey] as? Date
        let isFolder = (attribs[NSMetadataItemContentTypeTreeKey] as? [String])?.contains("public.folder") ?? false
        let isSymbolic = (attribs[NSMetadataItemContentTypeTreeKey] as? [String])?.contains("public.symlink") ?? false
        file.type = isFolder ? .directory : (isSymbolic ? .symbolicLink : .regular)
        
        return file
    }
    
    /// Removes local copy of file, but spares cloud copy
    open func evictItem(path: String, completionHandler: SimpleCompletionHandler) {
        operation_queue.addOperation {
            do {
                try self.opFileManager.evictUbiquitousItem(at: self.absoluteURL(path))
                completionHandler?(nil)
            } catch let e {
                completionHandler?(e)
            }
        }
    }
    
    open func temporaryLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: FileObject?, _ expiration: Date?, _ error: Error?) -> Void)) {
        operation_queue.addOperation {
            do {
                var expiration: NSDate?
                let url = try self.opFileManager.url(forPublishingUbiquitousItemAt: self.absoluteURL(path), expiration: &expiration)
                completionHandler(url, nil, expiration as Date?, nil)
            } catch let e {
                completionHandler(nil, nil, nil, e)
            }
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
    
    /// Caution: may put pressure on CPU, may have latency
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
    
    /// Caution: may put pressure on CPU, may have latency
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
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        
        var item: NSMetadataItem?
        
        let group = DispatchGroup()
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
        
        group.enter()
        query.start()
        _ = group.wait(timeout: DispatchTime.now() + 30)
        return item
    }
}
