//
//  LocalFileProvider.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 3/29/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

public final class LocalFileObject: FileObject {
    let allocatedSize: Int64
    
    init(absoluteURL: NSURL, name: String, size: Int64, allocatedSize: Int64, createdDate: NSDate?, modifiedDate: NSDate?, fileType: FileType, isHidden: Bool, isReadOnly: Bool) {
        self.allocatedSize = allocatedSize
        super.init(absoluteURL: absoluteURL, name: name, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
}

public class LocalFileProvider: FileProvider {
    public let type = "NSFileManager"
    public var isPathRelative: Bool = true
    public var baseURL: NSURL? = LocalFileProvider.defaultBaseURL()
    public var currentPath: String = ""
    public var dispatch_queue: dispatch_queue_t
    public var delegate: FileProviderDelegate?
    public let credential: NSURLCredential? = nil
    
    public typealias FileObjectClass = LocalFileObject
    
    let fileManager = NSFileManager()
    
    init () {
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_SERIAL)
    }
    
    init (baseURL: NSURL) {
        self.baseURL = baseURL
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_SERIAL)
    }
    
    private static func defaultBaseURL() -> NSURL {
        let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true);
        return NSURL(fileURLWithPath: paths[0])
    }
    
    public func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [LocalFileObject], error: ErrorType?) -> Void)) {
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
    
    private func attributesOfItemAtURL(fileURL: NSURL) -> LocalFileObject {
        var namev, sizev, allocated, filetypev, creationDatev, modifiedDatev, hiddenv, readonlyv: AnyObject?
        _ = try? fileURL.getResourceValue(&namev, forKey: NSURLNameKey)
        _ = try? fileURL.getResourceValue(&sizev, forKey: NSURLFileSizeKey)
        _ = try? fileURL.getResourceValue(&allocated, forKey: NSURLFileAllocatedSizeKey)
        _ = try? fileURL.getResourceValue(&creationDatev, forKey: NSURLCreationDateKey)
        _ = try? fileURL.getResourceValue(&modifiedDatev, forKey: NSURLContentModificationDateKey)
        _ = try? fileURL.getResourceValue(&filetypev, forKey: NSURLFileResourceTypeKey)
        _ = try? fileURL.getResourceValue(&hiddenv, forKey: NSURLIsHiddenKey)
        _ = try? fileURL.getResourceValue(&readonlyv, forKey: NSURLVolumeIsReadOnlyKey)
        let fileAttr = LocalFileObject(absoluteURL: fileURL, name: namev as! String, size: sizev?.longLongValue ?? -1, allocatedSize: allocated?.longLongValue ?? -1, createdDate: creationDatev as? NSDate, modifiedDate: modifiedDatev as? NSDate, fileType: FileType(urlResourceTypeValue: filetypev as? String ?? ""), isHidden: hiddenv?.boolValue ?? false, isReadOnly: readonlyv?.boolValue ?? false)
        return fileAttr
    }
    
    public func attributesOfItemAtPath(path: String, completionHandler: ((attributes: LocalFileObject?, error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            completionHandler(attributes: self.attributesOfItemAtURL(self.absoluteURL(path)), error: nil)
        }
    }
    
    public func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try self.fileManager.createDirectoryAtURL(self.absoluteURL(atPath).URLByAppendingPathComponent(folderName), withIntermediateDirectories: true, attributes: [:])
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
        dispatch_async(dispatch_queue) {
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
            let success = self.fileManager.createFileAtPath(fileURL.path!, contents: data, attributes: attributes)
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
        dispatch_async(dispatch_queue) {
            if !overwrite && self.fileManager.fileExistsAtPath(self.absoluteURL(toPath).path ?? "") {
                completionHandler?(error: self.throwError(toPath, code: NSURLError.CannotMoveFile))
                return
            }
            do {
                try self.fileManager.moveItemAtURL(self.absoluteURL(path), toURL: self.absoluteURL(toPath))
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
        dispatch_async(dispatch_queue) {
            if !overwrite && self.fileManager.fileExistsAtPath(self.absoluteURL(toPath).path ?? "") {
                completionHandler?(error: self.throwError(toPath, code: NSURLError.CannotWriteToFile))
                return
            }
            do {
                try self.fileManager.copyItemAtURL(self.absoluteURL(path), toURL: self.absoluteURL(toPath))
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
        dispatch_async(dispatch_queue) {
            do {
                try self.fileManager.removeItemAtURL(self.absoluteURL(path))
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
        dispatch_async(dispatch_queue) {
            do {
                try self.fileManager.copyItemAtURL(localFile, toURL: self.absoluteURL(toPath))
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
        dispatch_async(dispatch_queue) {
            do {
                try self.fileManager.copyItemAtURL(self.absoluteURL(path), toURL: toLocalURL)
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
            if self.attributesOfItemAtURL(self.absoluteURL(path)).fileType == .Directory {
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
        dispatch_async(dispatch_queue) {
            data.writeToURL(self.absoluteURL(path), atomically: atomically)
            dispatch_async(dispatch_get_main_queue(), {
                self.delegate?.fileproviderSucceed(self, operation: .Modify(path: path))
            })
        }
    }
    
    public func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObjectClass) -> Void)?, completionHandler: ((files: [FileObjectClass], error: ErrorType?) -> Void)) {
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
    
    private var monitorDictionary = [String : LocalFolderMonitor]()
    
    public func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        self.unregisterNotifcation(path)
        var isdirv: AnyObject?
        do {
            try absoluteURL(path).getResourceValue(&isdirv, forKey: NSURLIsDirectoryKey)
        } catch _ {
        }
        if !(isdirv?.boolValue ?? false) {
            return
        }
        let monitor = LocalFolderMonitor(url: absoluteURL(path)) {
            eventHandler()
        }
        monitor.start()
        monitorDictionary[path] = monitor
    }
    
    public func unregisterNotifcation(path: String) {
        if let prevMonitor = monitorDictionary[path] {
            prevMonitor.stop()
            monitorDictionary.removeValueForKey(path)
        }
    }
}

extension LocalFileProvider {
    public func createSymbolicLinkAtPath(path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try self.fileManager.createSymbolicLinkAtURL(self.absoluteURL(path), withDestinationURL: self.absoluteURL(destPath))
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

private class LocalFolderMonitor {
    private let source: dispatch_source_t
    private let descriptor: CInt
    private let qq: dispatch_queue_t = dispatch_get_main_queue()
    private var state: Bool = false
    
    /// Creates a folder monitor object with monitoring enabled.
    init(url: NSURL, handler: ()->Void) {
        
        descriptor = open(url.fileSystemRepresentation, O_EVTONLY)
        
        source = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_VNODE,
            UInt(descriptor),
            DISPATCH_VNODE_WRITE,
            qq
        )
        
        dispatch_source_set_event_handler(source, handler)
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
        close(descriptor)
        dispatch_source_cancel(source)
    }
}
