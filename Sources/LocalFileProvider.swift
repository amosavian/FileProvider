//
//  LocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public final class LocalFileObject: FileObject {
    let allocatedSize: Int64
    
    init(absoluteURL: NSURL, name: String, path: String, size: Int64, allocatedSize: Int64, createdDate: NSDate?, modifiedDate: NSDate?, fileType: FileType, isHidden: Bool, isReadOnly: Bool) {
        self.allocatedSize = allocatedSize
        super.init(absoluteURL: absoluteURL, name: name, path: path, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
}

public class LocalFileProvider: FileProvider, FileProviderMonitor {
    public let type = "Local"
    public var isPathRelative: Bool = true
    public var baseURL: NSURL? = LocalFileProvider.defaultBaseURL()
    public var currentPath: String = ""
    public var dispatch_queue: dispatch_queue_t
    public var operation_queue: dispatch_queue_t
    public weak var delegate: FileProviderDelegate?
    public let credential: NSURLCredential? = nil
        
    public let fileManager = NSFileManager()
    public let opFileManager = NSFileManager()
    private var fileProviderManagerDelegate: LocalFileProviderManagerDelegate? = nil
    
    init () {
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        operation_queue = dispatch_queue_create("FileProvider.\(type).Operation", DISPATCH_QUEUE_SERIAL)
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    init (baseURL: NSURL) {
        self.baseURL = baseURL
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        operation_queue = dispatch_queue_create("FileProvider.\(type).Operation", DISPATCH_QUEUE_SERIAL)
        fileProviderManagerDelegate = LocalFileProviderManagerDelegate(provider: self)
        opFileManager.delegate = fileProviderManagerDelegate
    }
    
    private static func defaultBaseURL() -> NSURL {
        let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true);
        return NSURL(fileURLWithPath: paths[0])
    }
    
    public func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObject], error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            do {
                let contents = try self.fileManager.contentsOfDirectoryAtURL(self.absoluteURL(path), includingPropertiesForKeys: [NSURLNameKey, NSURLFileSizeKey, NSURLFileAllocatedSizeKey, NSURLCreationDateKey, NSURLContentModificationDateKey, NSURLIsHiddenKey, NSURLVolumeIsReadOnlyKey, NSFileGroupOwnerAccountName], options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants)
                let filesAttributes = contents.map({ (fileURL) -> LocalFileObject in
                    return self.attributesOfItemAtURL(fileURL)
                })
                completionHandler(contents: filesAttributes, error: nil)
            } catch let e as NSError {
                completionHandler(contents: [], error: e)
            }
        }
    }
    
    internal func attributesOfItemAtURL(fileURL: NSURL) -> LocalFileObject {
        var namev, sizev, allocated, filetypev, creationDatev, modifiedDatev, hiddenv, readonlyv: AnyObject?
        _ = try? fileURL.getResourceValue(&namev, forKey: NSURLNameKey)
        _ = try? fileURL.getResourceValue(&sizev, forKey: NSURLFileSizeKey)
        _ = try? fileURL.getResourceValue(&allocated, forKey: NSURLFileAllocatedSizeKey)
        _ = try? fileURL.getResourceValue(&creationDatev, forKey: NSURLCreationDateKey)
        _ = try? fileURL.getResourceValue(&modifiedDatev, forKey: NSURLContentModificationDateKey)
        _ = try? fileURL.getResourceValue(&filetypev, forKey: NSURLFileResourceTypeKey)
        _ = try? fileURL.getResourceValue(&hiddenv, forKey: NSURLIsHiddenKey)
        _ = try? fileURL.getResourceValue(&readonlyv, forKey: NSURLVolumeIsReadOnlyKey)
        let path: String
        if isPathRelative {
            path = self.relativePathOf(url: fileURL)
        } else {
            path = fileURL.path!
        }
        let fileAttr = LocalFileObject(absoluteURL: fileURL, name: namev as! String, path: path, size: sizev?.longLongValue ?? -1, allocatedSize: allocated?.longLongValue ?? -1, createdDate: creationDatev as? NSDate, modifiedDate: modifiedDatev as? NSDate, fileType: FileType(urlResourceTypeValue: filetypev as? String ?? ""), isHidden: hiddenv?.boolValue ?? false, isReadOnly: readonlyv?.boolValue ?? false)
        return fileAttr
    }
    
    public func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObject?, error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            completionHandler(attributes: self.attributesOfItemAtURL(self.absoluteURL(path)), error: nil)
        }
    }
    
    public weak var fileOperationDelegate : FileOperationDelegate?
    
    public func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            do {
                try self.opFileManager.createDirectoryAtURL(self.absoluteURL(atPath).URLByAppendingPathComponent(folderName), withIntermediateDirectories: true, attributes: [:])
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Create(path: (atPath as NSString).stringByAppendingPathComponent(folderName) + "/"))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Create(path: (atPath as NSString).stringByAppendingPathComponent(folderName) + "/"))
                })
            }
        }
    }
    
    public func createFile(fileAttribs: FileObject, atPath: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            let fileURL = self.absoluteURL(atPath).URLByAppendingPathComponent(fileAttribs.name)
            var attributes = [String : AnyObject]()
            if let createdDate = fileAttribs.createdDate {
                attributes[NSFileCreationDate] = createdDate
            }
            if let modDate = fileAttribs.modifiedDate {
                attributes[NSFileModificationDate] = modDate
            }
            if fileAttribs.isReadOnly {
                attributes[NSFilePosixPermissions] = NSNumber(short: 365 /*555 o*/)
            }
            let success = self.opFileManager.createFileAtPath(fileURL.path!, contents: data, attributes: attributes)
            if success {
                do {
                    try fileURL.setResourceValue(fileAttribs.isHidden, forKey: NSURLIsHiddenKey)
                } catch _ {}
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Create(path: (atPath as NSString).stringByAppendingPathComponent(fileAttribs.name)))
                })
            } else {
                completionHandler?(error: self.throwError(atPath, code: NSURLError.CannotCreateFile))
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Create(path: (atPath as NSString).stringByAppendingPathComponent(fileAttribs.name)))
                })
            }
        }
    }
    
    public func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        // FIXME: progress
        dispatch_async(operation_queue) {
            if !overwrite && self.fileManager.fileExistsAtPath(self.absoluteURL(toPath).path ?? "") {
                completionHandler?(error: self.throwError(toPath, code: NSURLError.CannotMoveFile))
                return
            }
            do {
                try self.opFileManager.moveItemAtURL(self.absoluteURL(path), toURL: self.absoluteURL(toPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Move(source: path, destination: toPath))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Move(source: path, destination: toPath))
                })
            }
        }
    }
    
    public func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        // FIXME: progress, for files > 100mb, monitor file by another thread, for dirs check copied items count
        dispatch_async(operation_queue) {
            if !overwrite && self.fileManager.fileExistsAtPath(self.absoluteURL(toPath).path ?? "") {
                completionHandler?(error: self.throwError(toPath, code: NSURLError.CannotWriteToFile))
                return
            }
            do {
                try self.opFileManager.copyItemAtURL(self.absoluteURL(path), toURL: self.absoluteURL(toPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Copy(source: path, destination: toPath))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Copy(source: path, destination: toPath))
                })
            }
        }
    }
    
    public func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            do {
                try self.opFileManager.removeItemAtURL(self.absoluteURL(path))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Remove(path: path))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Remove(path: path))
                })
            }
        }
    }
    
    public func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            do {
                try self.opFileManager.copyItemAtURL(localFile, toURL: self.absoluteURL(toPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Copy(source: localFile.absoluteString, destination: toPath))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Copy(source: localFile.absoluteString, destination: toPath))
                })
            }
        }
    }
    
    public func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            do {
                try self.opFileManager.copyItemAtURL(self.absoluteURL(path), toURL: toLocalURL)
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Copy(source: path, destination: toLocalURL.absoluteString))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Copy(source: path, destination: toLocalURL.absoluteString))
                })
            }
        }
    }
    
    public func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            let data = self.fileManager.contentsAtPath(self.absoluteURL(path).path!)
            completionHandler(contents: data, error: nil)
        }
    }
    
    public func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        // Unfortunatlely there is no method provided in NSFileManager to read a segment of file.
        // So we have to fallback to POSIX provided methods
        dispatch_async(dispatch_queue) {
            let aPath = self.absoluteURL(path).path!
            if self.attributesOfItemAtURL(self.absoluteURL(path)).isDirectory {
                self.throwError(path, code: NSURLError.FileIsDirectory)
            }
            if !self.fileManager.fileExistsAtPath(aPath) {
                self.throwError(path, code: NSURLError.FileDoesNotExist)
            }
            let fd_from = open(aPath, O_RDONLY)
            if fd_from < 0 {
                completionHandler(contents: nil, error: self.throwError(path, code: NSURLError.CannotOpenFile))
            }
            defer { precondition(close(fd_from) >= 0) }
            lseek(fd_from, offset, SEEK_SET)
            var buf = [UInt8](count: length, repeatedValue: 0)
            let nread = read(fd_from, &buf, buf.count)
            if nread < 0 { self.throwError(path, code: NSURLError.NoPermissionsToReadFile) }
            if nread == 0 {
                completionHandler(contents: nil, error: nil)
            } else {
                let data = NSData(bytesNoCopy: &buf, length: nread, freeWhenDone: true)
                completionHandler(contents: data, error: nil)
            }
        }
    }
    
    public func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            data.writeToURL(self.absoluteURL(path), atomically: atomically)
            dispatch_async(dispatch_get_main_queue(), {
                self.delegate?.fileproviderSucceed(self, operation: .Modify(path: path))
            })
        }
    }
    
    public func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: ((files: [FileObject], error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) { 
            let iterator = self.fileManager.enumeratorAtURL(self.absoluteURL(path), includingPropertiesForKeys: nil, options: recursive ? NSDirectoryEnumerationOptions() : .SkipsSubdirectoryDescendants) { (url, e) -> Bool in
                completionHandler(files: [], error: e)
                return true
            }
            var result = [LocalFileObject]()
            while let fileURL = iterator?.nextObject() as? NSURL {
                if fileURL.lastPathComponent?.lowercaseString.containsString(query.lowercaseString) ?? false {
                    let fileObject = self.attributesOfItemAtURL(fileURL)
                    result.append(self.attributesOfItemAtURL(fileURL))
                    foundItemHandler?(fileObject)
                }
            }
            completionHandler(files: result, error: nil)
        }
    }
    
    private var monitors = [LocalFolderMonitor]()
    
    public func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        self.unregisterNotifcation(path)
        let absurl = self.absoluteURL(path)
        var isdirv: AnyObject?
        do {
            try absurl.getResourceValue(&isdirv, forKey: NSURLIsDirectoryKey)
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
    
    public func unregisterNotifcation(path: String) {
        var removedMonitor: LocalFolderMonitor?
        for (i, monitor) in monitors.enumerate() {
            if self.relativePathOf(url: monitor.url) == path {
                removedMonitor = monitors.removeAtIndex(i)
            }
        }
        removedMonitor?.stop()
    }
    
    public func isRegisteredForNotification(path: String) -> Bool {
        return monitors.map( { self.relativePathOf(url: $0.url) } ).contains(path)
    }
}

extension LocalFileProvider {
    public func createSymbolicLinkAtPath(path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(operation_queue) {
            do {
                try self.opFileManager.createSymbolicLinkAtURL(self.absoluteURL(path), withDestinationURL: self.absoluteURL(destPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderSucceed(self, operation: .Link(link: path, target: destPath))
                })
            } catch let e as NSError {
                completionHandler?(error: e)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderFailed(self, operation: .Link(link: path, target: destPath))
                })
            }
        }
    }
}

class LocalFileProviderManagerDelegate: NSObject, NSFileManagerDelegate {
    weak var provider: LocalFileProvider?
    
    init(provider: LocalFileProvider) {
        self.provider = provider
    }
    
    func fileManager(fileManager: NSFileManager, shouldCopyItemAtURL srcURL: NSURL, toURL dstURL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return true
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldDoOperation: .Copy(source: srcPath, destination: dstPath))
    }
    
    func fileManager(fileManager: NSFileManager, shouldMoveItemAtURL srcURL: NSURL, toURL dstURL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return true
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldDoOperation: .Move(source: srcPath, destination: dstPath))
    }
    
    func fileManager(fileManager: NSFileManager, shouldRemoveItemAtURL URL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return true
        }
        let path = provider.relativePathOf(url: URL)
        return delegate.fileProvider(provider, shouldDoOperation: .Remove(path: path))
    }
    
    func fileManager(fileManager: NSFileManager, shouldLinkItemAtURL srcURL: NSURL, toURL dstURL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return true
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldDoOperation: .Link(link: srcPath, target: dstPath))
    }
    
    func fileManager(fileManager: NSFileManager, shouldProceedAfterError error: NSError, copyingItemAtURL srcURL: NSURL, toURL dstURL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return false
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .Copy(source: srcPath, destination: dstPath))
    }
    
    func fileManager(fileManager: NSFileManager, shouldProceedAfterError error: NSError, movingItemAtURL srcURL: NSURL, toURL dstURL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return false
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .Move(source: srcPath, destination: dstPath))
    }
    
    func fileManager(fileManager: NSFileManager, shouldProceedAfterError error: NSError, removingItemAtURL URL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return false
        }
        let path = provider.relativePathOf(url: URL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .Remove(path: path))
    }
    
    func fileManager(fileManager: NSFileManager, shouldProceedAfterError error: NSError, linkingItemAtURL srcURL: NSURL, toURL dstURL: NSURL) -> Bool {
        guard let provider = self.provider, delegate = provider.fileOperationDelegate else {
            return false
        }
        let srcPath = provider.relativePathOf(url: srcURL)
        let dstPath = provider.relativePathOf(url: dstURL)
        return delegate.fileProvider(provider, shouldProceedAfterError: error, operation: .Link(link: srcPath, target: dstPath))
    }
}

internal class LocalFolderMonitor {
    private let source: dispatch_source_t
    private let descriptor: CInt
    private let qq: dispatch_queue_t = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    private var state: Bool = false
    private var monitoredTime: NSTimeInterval = NSDate().timeIntervalSinceReferenceDate
    var url: NSURL
    
    /// Creates a folder monitor object with monitoring enabled.
    init(url: NSURL, handler: ()->Void) {
        self.url = url
        descriptor = open(url.fileSystemRepresentation, O_EVTONLY)
        
        source = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_VNODE,
            UInt(descriptor),
            DISPATCH_VNODE_WRITE,
            qq
        )
        // Folder monitoring is recursive and deep. Monitoring a root folder may be very costly
        // We have a 0.2 second delay to ensure we wont call handler 1000s times when there is
        // a huge file operation. This ensures app will work smoothly while this 250 milisec won't
        // affect user experince much
        let main_handler: ()->Void = {
            if NSDate().timeIntervalSinceReferenceDate < self.monitoredTime + 0.2 {
                return
            }
            self.monitoredTime = NSDate().timeIntervalSinceReferenceDate
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(NSEC_PER_SEC) / 4), dispatch_get_main_queue(), {
                handler()
            })
        }
        dispatch_source_set_event_handler(source, main_handler)
        dispatch_source_set_cancel_handler(source) {
            close(self.descriptor)
        }
        start()
    }
    
    /// Starts sending notifications if currently stopped
    func start() {
        if !state {
            state = true
            dispatch_resume(source)
        }
    }
    
    /// Stops sending notifications if currently enabled
    func stop() {
        if state {
            state = false
            dispatch_suspend(source)
        }
    }
    
    deinit {
        dispatch_source_cancel(source)
    }
}
