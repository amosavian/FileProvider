//
//  FileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation
#if os(iOS) || os(tvOS)
import UIKit
public typealias ImageClass = UIImage
#elseif os(OSX)
import Cocoa
public typealias ImageClass = NSImage
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
    
    public init(urlResourceTypeValue: String) {
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
    
    public init(fileTypeValue: String) {
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

public protocol FoundationErrorEnum {
    init? (rawValue: Int)
    var rawValue: Int { get }
}

extension NSURLError: FoundationErrorEnum {}
extension NSCocoaError: FoundationErrorEnum {}

public class FileObject {
    public let absoluteURL: NSURL?
    public let name: String
    public let path: String
    public let size: Int64
    public let createdDate: NSDate?
    public let modifiedDate: NSDate?
    public let fileType: FileType
    public let isHidden: Bool
    public let isReadOnly: Bool
    
    public init(absoluteURL: NSURL? = nil, name: String, path: String, size: Int64 = -1, createdDate: NSDate? = nil, modifiedDate: NSDate? = nil, fileType: FileType = .Regular, isHidden: Bool = false, isReadOnly: Bool = false) {
        self.absoluteURL = absoluteURL
        self.name = name
        self.path = path
        self.size = size
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.fileType = fileType
        self.isHidden = isHidden
        self.isReadOnly = isReadOnly
    }
    
    public var isDirectory: Bool {
        return self.fileType == .Directory
    }
    
    public var isSymLink: Bool {
        return self.fileType == .SymbolicLink
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
    
    func storageProperties(completionHandler: ((total: Int64, used: Int64) -> Void))
}

public protocol FileProviderOperations: FileProviderBasic {
    var fileOperationDelegate : FileOperationDelegate? { get set }
    
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
    func isRegisteredForNotification(path: String) -> Bool
}

public protocol FileProvider: FileProviderBasic, FileProviderOperations, FileProviderReadWrite {
    
}

extension FileProviderBasic {
    public var bareCurrentPath: String {
        return currentPath.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: ". /"))
    }
    
    public func absoluteURL(path: String? = nil) -> NSURL {
        let rpath: String
        if let path = path {
            rpath = path
        } else {
            rpath = self.currentPath
        }
        if isPathRelative, let baseURL = baseURL {
            if rpath.hasPrefix("/") && baseURL.uw_absoluteString.hasSuffix("/") {
                var npath = rpath
                npath.removeAtIndex(npath.startIndex)
                return baseURL.uw_URLByAppendingPathComponent(npath)
            } else {
                return baseURL.uw_URLByAppendingPathComponent(rpath)
            }
        } else {
            return NSURL(fileURLWithPath: rpath).URLByStandardizingPath!
        }
    }
    
    public func relativePathOf(url url: NSURL) -> String {
        guard let baseURL = self.baseURL else { return url.uw_absoluteString }
        return url.URLByStandardizingPath!.uw_absoluteString.stringByReplacingOccurrencesOfString(baseURL.uw_absoluteString, withString: "/").stringByRemovingPercentEncoding!
    }
    
    internal func correctPath(path: String?) -> String? {
        guard let path = path else { return nil }
        return path.hasPrefix("/") ? path : "/" + path
    }
    
    public func fileByUniqueName(filePath: String) -> String {
        let fileUrl = NSURL(fileURLWithPath: filePath)
        let dirPath = fileUrl.URLByDeletingLastPathComponent?.path ?? ""
        guard let fileName = fileUrl.URLByDeletingPathExtension?.lastPathComponent else {
            return filePath
        }
        let fileExt = fileUrl.pathExtension ?? ""
        var result = fileName
        let group = dispatch_group_create()
        dispatch_group_enter(group)
        self.contentsOfDirectoryAtPath(dirPath) { (contents, error) in
            var bareFileName = fileName
            let number = Int(fileName.componentsSeparatedByString(" ").filter {
                !$0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()).isEmpty
                }.last ?? "noname")
            if let _ = number {
                result = fileName.componentsSeparatedByString(" ").filter {
                    !$0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()).isEmpty
                    }.dropLast().joinWithSeparator(" ")
                bareFileName = result
            }
            var i = number ?? 2
            let similiar = contents.map {
                $0.absoluteURL?.lastPathComponent ?? $0.name
            }.filter {
                $0.hasPrefix(result) && (!fileExt.isEmpty && $0.hasSuffix("." + fileExt))
            }
            while similiar.contains(result + (!fileExt.isEmpty ? "." + fileExt : "")) {
                result = "\(bareFileName) \(i)"
                i += 1
            }
            dispatch_group_leave(group)
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        let finalFile = result + (!fileExt.isEmpty ? "." + fileExt : "")
        return (dirPath as NSString).stringByAppendingPathComponent(finalFile)
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
        return NSError(domain: domain, code: code.rawValue, userInfo: [NSURLErrorFailingURLErrorKey: fileURL, NSURLErrorFailingURLStringErrorKey: fileURL.uw_absoluteString])
    }
    
    internal func NotImplemented() {
        assert(false, "method not implemented")
    }
    
    internal func resolveDate(dateString: String) -> NSDate? {
        let dateFor: NSDateFormatter = NSDateFormatter()
        dateFor.locale = NSLocale(localeIdentifier: "en_US")
        dateFor.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss zzz"
        if let rfc1123 = dateFor.dateFromString(dateString) {
            return rfc1123
        }
        dateFor.dateFormat = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
        if let rfc850 = dateFor.dateFromString(dateString) {
            return rfc850
        }
        dateFor.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
        if let asctime = dateFor.dateFromString(dateString) {
            return asctime
        }
        dateFor.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssz"
        if let isotime = dateFor.dateFromString(dateString) {
            return isotime
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


public protocol ExtendedFileProvider: FileProvider {
    func thumbnailOfFileSupported(path: String) -> Bool
    func propertiesOfFileSupported(path: String) -> Bool
    func thumbnailOfFileAtPath(path: String, dimension: CGSize, completionHandler: ((image: ImageClass?, error: ErrorType?) -> Void))
    func propertiesOfFileAtPath(path: String, completionHandler: ((propertiesDictionary: [String: AnyObject], keys: [String], error: ErrorType?) -> Void))
}

public enum FileOperation: CustomStringConvertible {
    case Create (path: String)
    case Copy   (source: String, destination: String)
    case Move   (source: String, destination: String)
    case Modify (path: String)
    case Remove (path: String)
    case Link   (link: String, target: String)
    
    public var description: String {
        switch self {
        case .Create(path: _): return "Create"
        case .Copy(source: _, destination: _): return "Copy"
        case .Move(source: _, destination: _): return "Move"
        case .Modify(path: _): return "Modify"
        case .Remove(path: _): return "Remove"
        case .Link(link: _, target: _): return "Link"
        }
    }
    
    internal var actionDescription: String {
        switch self {
        case .Create(path: _): return "Creating"
        case .Copy(source: _, destination: _): return "Copying"
        case .Move(source: _, destination: _): return "Moving"
        case .Modify(path: _): return "Modifying"
        case .Remove(path: _): return "Removing"
        case .Link(link: _, target: _): return "Linking"
        }
    }
    
}

public protocol FileProviderDelegate: class {
    func fileproviderSucceed(fileProvider: FileProviderOperations, operation: FileOperation)
    func fileproviderFailed(fileProvider: FileProviderOperations, operation: FileOperation)
    func fileproviderProgress(fileProvider: FileProviderOperations, operation: FileOperation, progress: Float)
}

public protocol FileOperationDelegate: class {
    
    /// fileProvider(_:shouldOperate:) gives the delegate an opportunity to filter the file operation. Returning true from this method will allow the copy to happen. Returning false from this method causes the item in question to be skipped. If the item skipped was a directory, no children of that directory will be subject of the operation, nor will the delegate be notified of those children.
    func fileProvider(fileProvider: FileProviderOperations, shouldDoOperation operation: FileOperation) -> Bool
    
    /// fileProvider(_:shouldProceedAfterError:copyingItemAtPath:toPath:) gives the delegate an opportunity to recover from or continue copying after an error. If an error occurs, the error object will contain an ErrorType indicating the problem. The source path and destination paths are also provided. If this method returns true, the FileProvider instance will continue as if the error had not occurred. If this method returns false, the NSFileManager instance will stop copying, return false from copyItemAtPath:toPath:error: and the error will be provied there.
    func fileProvider(fileProvider: FileProviderOperations, shouldProceedAfterError error: ErrorType, operation: FileOperation) -> Bool
}

// THESE ARE METHODS TO PROVIDE COMPATIBILITY WITH SWIFT 2.3 SIMOULTANIOUSLY!

internal extension NSURL {
    var uw_scheme: String {
        #if swift(>=2.3)
            return self.scheme ?? ""
        #else
            return self.scheme
        #endif
    }
    
    var uw_absoluteString: String {
        #if swift(>=2.3)
            return self.absoluteString ?? ""
        #else
            return self.absoluteString
        #endif
    }
    
    func uw_URLByAppendingPathComponent(pathComponent: String) -> NSURL {
        #if swift(>=2.3)
            return self.URLByAppendingPathComponent(pathComponent)!
        #else
            return self.URLByAppendingPathComponent(pathComponent)
        #endif
    }
    
    func uw_URLByAppendingPathExtension(pathExtension: String) -> NSURL {
        #if swift(>=2.3)
            return self.URLByAppendingPathExtension(pathExtension)!
        #else
            return self.URLByAppendingPathExtension(pathExtension)
        #endif
    }
}
