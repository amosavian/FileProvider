//
//  LocalFileProvider.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 3/29/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

final class LocalFileObject: FileObject {
    let allocatedSize: Int64
    
    init(absoluteURL: NSURL, name: String, size: Int64, allocatedSize: Int64, createdDate: NSDate?, modifiedDate: NSDate?, fileType: FileType, isHidden: Bool, isReadOnly: Bool) {
        self.allocatedSize = allocatedSize
        super.init(absoluteURL: absoluteURL, name: name, size: size, createdDate: createdDate, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
}

class LocalFileProvider: FileProvider {
    let type = "NSFileManager"
    var isPathRelative: Bool = true
    var baseURL: NSURL? = LocalFileProvider.defaultBaseURL()
    var currentPath: String = ""
    var dispatch_queue: dispatch_queue_t
    var delegate: FileProviderDelegate?
    let credential: NSURLCredential? = nil
    
    typealias FileObjectClass = LocalFileObject
    
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
    
    func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [LocalFileObject], error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            do {
                let contents = try NSFileManager.defaultManager().contentsOfDirectoryAtURL(self.absoluteURL(path), includingPropertiesForKeys: [NSURLNameKey, NSURLFileSizeKey, NSURLFileAllocatedSizeKey, NSURLCreationDateKey, NSURLContentModificationDateKey, NSURLIsHiddenKey, NSURLVolumeIsReadOnlyKey, NSFileGroupOwnerAccountName], options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants)
                let filesAttributes = contents.map({ (fileURL) -> LocalFileObject in
                    return self.attributesOfItemAtURL(fileURL)
                })
                completionHandler(contents: filesAttributes, error: nil)
            } catch let e as NSError {
                completionHandler(contents: [], error: e)
            }
        }
    }
    
    func attributesOfItemAtURL(fileURL: NSURL) -> LocalFileObject {
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
    
    func attributesOfItemAtPath(path: String, completionHandler: ((attributes: LocalFileObject?, error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            completionHandler(attributes: self.attributesOfItemAtURL(self.absoluteURL(path)), error: nil)
        }
    }
    
    func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try NSFileManager.defaultManager().createDirectoryAtURL(self.absoluteURL(atPath).URLByAppendingPathComponent(folderName), withIntermediateDirectories: true, attributes: [:])
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderCreateModifyNotify(self, path: atPath)
                })
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
    
    func createFile(fileAttribs: FileObject, atPath: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
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
            let success = NSFileManager.defaultManager().createFileAtPath(fileURL.path!, contents: data, attributes: attributes)
            if success {
                do {
                    try fileURL.setResourceValue(fileAttribs.isHidden, forKey: NSURLIsHiddenKey)
                } catch _ {}
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderCreateModifyNotify(self, path: atPath)
                })
            } else {
                completionHandler?(error: self.throwError(atPath, code: NSURLError.CannotCreateFile))
            }
        }
    }
    
    func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            if !overwrite && NSFileManager.defaultManager().fileExistsAtPath(self.absoluteURL(toPath).path ?? "") {
                completionHandler?(error: self.throwError(toPath, code: NSURLError.CannotMoveFile))
                return
            }
            do {
                try NSFileManager.defaultManager().moveItemAtURL(self.absoluteURL(path), toURL: self.absoluteURL(toPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderMoveNotify(self, fromPath: path, toPath: toPath)
                })
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
    
    func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            if !overwrite && NSFileManager.defaultManager().fileExistsAtPath(self.absoluteURL(toPath).path ?? "") {
                completionHandler?(error: self.throwError(toPath, code: NSURLError.CannotWriteToFile))
                return
            }
            do {
                try NSFileManager.defaultManager().copyItemAtURL(self.absoluteURL(path), toURL: self.absoluteURL(toPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderCopyNotify(self, fromPath: path, toPath: toPath)
                })
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
    
    func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try NSFileManager.defaultManager().removeItemAtURL(self.absoluteURL(path))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderRemoveNotify(self, path: path)
                })
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
    
    func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try NSFileManager.defaultManager().copyItemAtURL(localFile, toURL: self.absoluteURL(toPath))
                completionHandler?(error: nil)
                dispatch_async(dispatch_get_main_queue(), {
                    self.delegate?.fileproviderCreateModifyNotify(self, path: toPath)
                })
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
    
    func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try NSFileManager.defaultManager().copyItemAtURL(self.absoluteURL(path), toURL: toLocalURL)
                completionHandler?(error: nil)
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
    
    func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) {
            let data = NSFileManager.defaultManager().contentsAtPath(self.absoluteURL(path).path!)
            completionHandler(contents: data, error: nil)
        }
    }
    
    func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        // Unfortunatlely there is no method provided in NSFileManager to read a segment of file.
        // So we have to fallback to POSIX provided methods
        dispatch_async(dispatch_queue) {
            let aPath = self.absoluteURL(path).path!
            if self.attributesOfItemAtURL(self.absoluteURL(path)).fileType == .Directory {
                self.throwError(path, code: NSURLError.FileIsDirectory)
            }
            if !NSFileManager.defaultManager().fileExistsAtPath(aPath) {
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
    
    func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            data.writeToURL(self.absoluteURL(path), atomically: atomically)
            dispatch_async(dispatch_get_main_queue(), {
                self.delegate?.fileproviderCreateModifyNotify(self, path: path)
            })
        }
    }
    
    func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObjectClass) -> Void)?, completionHandler: ((files: [FileObjectClass], error: ErrorType?) -> Void)) {
        dispatch_async(dispatch_queue) { 
            let iterator = NSFileManager.defaultManager().enumeratorAtURL(self.absoluteURL(path), includingPropertiesForKeys: nil, options: recursive ? NSDirectoryEnumerationOptions() : .SkipsSubdirectoryDescendants) { (url, e) -> Bool in
                completionHandler(files: [], error: e)
                return true
            }
            var result = [LocalFileObject]()
            while let fileURL = iterator?.nextObject() as? NSURL {
                if fileURL.fileName.lowercaseString.containsString(query.lowercaseString) {
                    let fileObject = self.attributesOfItemAtURL(fileURL)
                    result.append(self.attributesOfItemAtURL(fileURL))
                    foundItemHandler?(fileObject)
                }
            }
            completionHandler(files: result, error: nil)
        }
    }
}

extension LocalFileProvider {
    func createSymbolicLinkAtPath(path: String, withDestinationPath destPath: String, completionHandler: SimpleCompletionHandler) {
        dispatch_async(dispatch_queue) {
            do {
                try NSFileManager.defaultManager().createSymbolicLinkAtURL(self.absoluteURL(path), withDestinationURL: self.absoluteURL(destPath))
                completionHandler?(error: nil)
            } catch let e as NSError {
                completionHandler?(error: e)
            }
        }
    }
}
