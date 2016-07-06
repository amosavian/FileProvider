//
//  FileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation
#if (iOS)
import UIKit
#endif
#if (OSX)
import AppKit
#endif

public enum FileType: String {
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

public class FileObject {
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


public typealias SimpleCompletionHandler = ((error: ErrorType?) -> Void)?

public protocol FileProviderBasic: class {
    var type: String { get }
    var isPathRelative: Bool { get }
    var baseURL: NSURL? { get }
    var currentPath: String { get set }
    var dispatch_queue: dispatch_queue_t { get set }
    var delegate: FileProviderDelegate? { get set }
    var credential: NSURLCredential? { get }
    
    /**
     *
    */
    func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObject], error: ErrorType?) -> Void))
    func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObject?, error: ErrorType?) -> Void))
}

public protocol FileProviderOperations: FileProviderBasic {
    func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler)
    func createFile(fileAttribs: FileObject, atPath: String, contents data: NSData?, completionHandler: SimpleCompletionHandler)
    func moveItemAtPath(path: String, toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler)
    func copyItemAtPath(path: String, toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler)
    func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler)
    
    func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler)
    func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler)
}

public protocol FileProviderReadWrite: FileProviderBasic {
    func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void))
    func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void))
    func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool, completionHandler: SimpleCompletionHandler)
    
    func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: ((files: [FileObject], error: ErrorType?) -> Void))
}

public protocol FileProviderMonitor: FileProviderBasic {
    func registerNotifcation(path: String, eventHandler: (() -> Void))
    func unregisterNotifcation(path: String)
}

public protocol FileProvider: FileProviderBasic, FileProviderOperations, FileProviderReadWrite {
    
}

extension FileProviderBasic {
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
    
    internal func throwError(path: String, code: FoundationErrorEnum) -> NSError {
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
    
    internal func NotImplemented() {
        assert(false, "method not implemented")
    }
    
    internal func resolveRFCDate(httpDateString: String) -> NSDate? {
        let dateFor: NSDateFormatter = NSDateFormatter()
        dateFor.locale = NSLocale(localeIdentifier: "en_US")
        dateFor.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss zzz"
        if let rfc1123 = dateFor.dateFromString(httpDateString) {
            return rfc1123
        }
        dateFor.dateFormat = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
        if let rfc850 = dateFor.dateFromString(httpDateString) {
            return rfc850
        }
        dateFor.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
        if let asctime = dateFor.dateFromString(httpDateString) {
            return asctime
        }
        //self.init()
        return nil
    }
    
    internal func jsonToDictionary(jsonString: String) -> [String: AnyObject]? {
        guard let data = jsonString.dataUsingEncoding(NSUTF8StringEncoding) else {
            return nil
        }
        if let dic = try? NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? [String: AnyObject] {
            return dic
        }
        return nil
    }
    
    internal func dictionaryToJSON(dictionary: [String: AnyObject]) -> String? {
        if let data = try? NSJSONSerialization.dataWithJSONObject(dictionary, options: NSJSONWritingOptions()) {
            return String(data: data, encoding: NSUTF8StringEncoding)
        }
        return nil
    }
}

#if (iOS)
public protocol ExtendedFileProvider: FileProvider {
    func thumbnailOfFileAtPath(path: String, dimension: CGSize, completionHandler: ((image: UIImage?, error: ErrorType?) -> Void))
    func propertiesOfFileAtPath(path: String, completionHandler: ((propertiesDictionary: [String: AnyObject], keys: [String], error: ErrorType?) -> Void))
}
#elseif (OSX)
public protocol ExtendedFileProvider: FileProvider {
    func thumbnailOfFileAtPath(path: String, dimension: CGSize, completionHandler: ((image: NSImage?, error: ErrorType?) -> Void))
    func propertiesOfFileAtPath(path: String, completionHandler: ((propertiesDictionary: [String: AnyObject], keys: [String], error: ErrorType?) -> Void))
}
#endif

public enum FileOperation {
    case Create (path: String)
    case Copy   (source: String, destination: String)
    case Move   (source: String, destination: String)
    case Modify (path: String)
    case Remove (path: String)
    case Link   (link: String, target: String)
}

public protocol FileProviderDelegate {
    func fileproviderSucceed(fileProvider: FileProviderOperations, operation: FileOperation)
    func fileproviderFailed(fileProvider: FileProviderOperations, operation: FileOperation)
    func fileproviderProgress(fileProvider: FileProviderOperations, operation: FileOperation, progress: Float)
}


