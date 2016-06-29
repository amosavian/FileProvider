//
//  FileProvider.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 3/28/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

enum FileType: String {
    case Directory
    case Regular
    case SymbolicLink
    case Socket
    case CharacterSpecial
    case BlockSpecial
    case NamedPipe
    case Unknown
    
    init(urlResourceTypeValue: String) {
        switch urlResourceTypeValue {
        case NSURLFileResourceTypeNamedPipe: self = .NamedPipe
        case NSURLFileResourceTypeCharacterSpecial: self = .CharacterSpecial
        case NSURLFileResourceTypeDirectory: self = .Directory
        case NSURLFileResourceTypeBlockSpecial: self = .BlockSpecial
        case NSURLFileResourceTypeRegular: self = .Regular
        case NSURLFileResourceTypeSymbolicLink: self = .SymbolicLink
        case NSURLFileResourceTypeSocket: self = .Socket
        case NSURLFileResourceTypeUnknown: self = .Unknown
        default: self = .Unknown
        }
    }
    
    init(fileTypeValue: String) {
        switch fileTypeValue {
        case NSFileTypeCharacterSpecial: self = .CharacterSpecial
        case NSFileTypeDirectory: self = .Directory
        case NSFileTypeBlockSpecial: self = .BlockSpecial
        case NSFileTypeRegular: self = .Regular
        case NSFileTypeSymbolicLink: self = .SymbolicLink
        case NSFileTypeSocket: self = .Socket
        case NSFileTypeUnknown: self = .Unknown
        default: self = .Unknown
        }
    }
}

protocol FoundationErrorEnum {
    init? (rawValue: Int)
    var rawValue: Int { get }
}

extension NSURLError: FoundationErrorEnum {}
extension NSCocoaError: FoundationErrorEnum {}

class FileObject {
    let absoluteURL: NSURL?
    let name: String
    let size: Int64
    let createdDate: NSDate?
    let modifiedDate: NSDate?
    let fileType: FileType
    let isHidden: Bool
    let isReadOnly: Bool
    
    init(absoluteURL: NSURL, name: String, size: Int64, createdDate: NSDate?, modifiedDate: NSDate?, fileType: FileType, isHidden: Bool, isReadOnly: Bool) {
        self.absoluteURL = absoluteURL
        self.name = name
        self.size = size
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.fileType = fileType
        self.isHidden = isHidden
        self.isReadOnly = isReadOnly
    }
    
    init(name: String, createdDate: NSDate?, modifiedDate: NSDate?, isHidden: Bool, isReadOnly: Bool) {
        self.absoluteURL = NSURL()
        self.name = name
        self.size = -1
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.fileType = .Regular
        self.isHidden = isHidden
        self.isReadOnly = isReadOnly
    }
}


typealias SimpleCompletionHandler = ((error: ErrorType?) -> Void)?

protocol FileProvider: class {
    var type: String { get }
    var isPathRelative: Bool { get set }
    var baseURL: NSURL? { get }
    var currentPath: String { get set }
    var dispatch_queue: dispatch_queue_t { get set }
    var delegate: FileProviderDelegate? { get set }
    var credential: NSURLCredential? { get }
    
    associatedtype FileObjectClass
    
    func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObjectClass], error: ErrorType?) -> Void))
    func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObjectClass?, error: ErrorType?) -> Void))
    
    func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler)
    func createFile(fileAttribs: FileObject, atPath: String, contents data: NSData?, completionHandler: SimpleCompletionHandler)
    func moveItemAtPath(path: String, toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler)
    func copyItemAtPath(path: String, toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler)
    func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler)
    
    func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler)
    func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler)
    
    func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void))
    func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void))
    func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool, completionHandler: SimpleCompletionHandler)
    
    func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObjectClass) -> Void)?, completionHandler: ((files: [FileObjectClass], error: ErrorType?) -> Void))
}

extension FileProvider {
    var bareCurrentPath: String {
        return currentPath.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: ". /"))
    }
    
    func absoluteURL(path: String? = nil) -> NSURL {
        let rpath: String
        if let path = path {
            rpath = path
        } else {
            rpath = self.currentPath
        }
        if isPathRelative, let baseURL = baseURL {
            if rpath.hasPrefix("/") && baseURL.absoluteString.hasSuffix("/") {
                var npath = rpath
                npath.removeAtIndex(npath.startIndex)
                return baseURL.URLByAppendingPathComponent(npath)
            } else {
                return baseURL.URLByAppendingPathComponent(rpath)
            }
        } else {
            return NSURL(fileURLWithPath: rpath)
        }
    }
    
    func throwError(path: String, code: FoundationErrorEnum) -> NSError {
        let fileURL = self.absoluteURL(path)
        let domain: String
        switch code {
        case is NSURLError:
            domain = NSURLErrorDomain
        default:
            domain = NSCocoaErrorDomain
        }
        return NSError(domain: domain, code: code.rawValue, userInfo: [NSURLErrorFailingURLErrorKey: fileURL, NSURLErrorFailingURLStringErrorKey: fileURL.absoluteString])
    }
    
    func NotImplemented() {
        assertionFailure("method not implemented")
    }
}

protocol ExtendedFileProvider: FileProvider {
    func thumbnailOfFileAtPath(path: String, dimension: CGSize, completionHandler: ((image: UIImage?, error: ErrorType?) -> Void))
    func propertiesOfFileAtPath(path: String, completionHandler: ((propertiesDictionary: [String: AnyObject], keys: [String], error: ErrorType?) -> Void))
}

protocol FileProviderDelegate {
    func fileproviderCreateModifyNotify<P: FileProvider>(fileProvider: P, path: String)
    func fileproviderCopyNotify<P: FileProvider>(fileProvider: P, fromPath: String, toPath: String)
    func fileproviderMoveNotify<P: FileProvider>(fileProvider: P, fromPath: String, toPath: String)
    func fileproviderRemoveNotify<P: FileProvider>(fileProvider: P, path: String)
}


