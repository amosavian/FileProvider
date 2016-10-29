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
    case directory
    case regular
    case symbolicLink
    case socket
    case characterSpecial
    case blockSpecial
    case namedPipe
    case unknown
    
    public init(urlResourceTypeValue: URLFileResourceType) {
        switch urlResourceTypeValue {
        case URLFileResourceType.namedPipe: self = .namedPipe
        case URLFileResourceType.characterSpecial: self = .characterSpecial
        case URLFileResourceType.directory: self = .directory
        case URLFileResourceType.blockSpecial: self = .blockSpecial
        case URLFileResourceType.regular: self = .regular
        case URLFileResourceType.symbolicLink: self = .symbolicLink
        case URLFileResourceType.socket: self = .socket
        case URLFileResourceType.unknown: self = .unknown
        default: self = .unknown
        }
    }
    
    public init(fileTypeValue: FileAttributeType) {
        switch fileTypeValue {
        case FileAttributeType.typeCharacterSpecial: self = .characterSpecial
        case FileAttributeType.typeDirectory: self = .directory
        case FileAttributeType.typeBlockSpecial: self = .blockSpecial
        case FileAttributeType.typeRegular: self = .regular
        case FileAttributeType.typeSymbolicLink: self = .symbolicLink
        case FileAttributeType.typeSocket: self = .socket
        case FileAttributeType.typeUnknown: self = .unknown
        default: self = .unknown
        }
    }
}

public protocol FoundationErrorEnum {
    init? (rawValue: Int)
    var rawValue: Int { get }
}

extension URLError.Code: FoundationErrorEnum {}
extension CocoaError.Code: FoundationErrorEnum {}

open class FileObject {
    open let absoluteURL: URL?
    open let name: String
    open let path: String
    open let size: Int64
    open let createdDate: Date?
    open let modifiedDate: Date?
    open let fileType: FileType
    open let isHidden: Bool
    open let isReadOnly: Bool
    
    public init(absoluteURL: URL? = nil, name: String, path: String, size: Int64 = -1, createdDate: Date? = nil, modifiedDate: Date? = nil, fileType: FileType = .regular, isHidden: Bool = false, isReadOnly: Bool = false) {
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
    
    open var isDirectory: Bool {
        return self.fileType == .directory
    }
    
    open var isSymLink: Bool {
        return self.fileType == .symbolicLink
    }
}


public typealias SimpleCompletionHandler = ((_ error: Error?) -> Void)?

public protocol FileProviderBasic: class {
    static var type: String { get }
    var isPathRelative: Bool { get }
    var baseURL: URL? { get }
    var currentPath: String { get set }
    var dispatch_queue: DispatchQueue { get set }
    var delegate: FileProviderDelegate? { get set }
    var credential: URLCredential? { get }
    
    /**
     *
    */
    func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void))
    func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void))
    
    func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void))
}

public protocol FileProviderOperations: FileProviderBasic {
    var fileOperationDelegate : FileOperationDelegate? { get set }
    
    @discardableResult
    func create(folder: String, at: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func create(file: FileObject, at: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func moveItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    @discardableResult
    func copyItem(localFile: URL, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle?
}

public protocol FileProviderReadWrite: FileProviderBasic {
    @discardableResult
    func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?
    @discardableResult
    func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?
    @discardableResult
    func writeContents(path: String, contents: Data, atomically: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void))
}

public protocol FileProviderMonitor: FileProviderBasic {
    func registerNotifcation(path: String, eventHandler: @escaping (() -> Void))
    func unregisterNotifcation(path: String)
    func isRegisteredForNotification(path: String) -> Bool
}

public protocol FileProvider: FileProviderBasic, FileProviderOperations, FileProviderReadWrite {
    
}

extension FileProviderBasic {
    public var type: String {
        return type(of: self).type
    }
    
    public var bareCurrentPath: String {
        return currentPath.trimmingCharacters(in: CharacterSet(charactersIn: ". /"))
    }
    
    public func absoluteURL(_ path: String? = nil) -> URL {
        let rpath: String
        if let path = path {
            rpath = path
        } else {
            rpath = self.currentPath
        }
        if isPathRelative, let baseURL = baseURL {
            if rpath.hasPrefix("/") && baseURL.absoluteString.hasSuffix("/") {
                var npath = rpath
                npath.remove(at: npath.startIndex)
                return baseURL.appendingPathComponent(npath)
            } else {
                return baseURL.appendingPathComponent(rpath)
            }
        } else {
            return URL(fileURLWithPath: rpath).standardizedFileURL
        }
    }
    
    public func relativePathOf(url: URL) -> String {
        guard let baseURL = self.baseURL else { return url.absoluteString }
        return url.standardizedFileURL.absoluteString.replacingOccurrences(of: baseURL.absoluteString, with: "/").removingPercentEncoding!
    }
    
    internal func correctPath(_ path: String?) -> String? {
        guard let path = path else { return nil }
        var p = path.hasPrefix("/") ? path : "/" + path
        if p.hasSuffix("/") {
            p.remove(at: p.characters.index(before: p.endIndex))
        }
        return p
    }
    
    public func fileByUniqueName(_ filePath: String) -> String {
        let fileUrl = URL(fileURLWithPath: filePath)
        let dirPath = fileUrl.deletingLastPathComponent().path 
        let fileName = fileUrl.deletingPathExtension().lastPathComponent
        let fileExt = fileUrl.pathExtension 
        var result = fileName
        let group = DispatchGroup()
        group.enter()
        self.contentsOfDirectory(path: dirPath) { (contents, error) in
            var bareFileName = fileName
            let number = Int(fileName.components(separatedBy: " ").filter {
                !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                }.last ?? "noname")
            if let _ = number {
                result = fileName.components(separatedBy: " ").filter {
                    !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                    }.dropLast().joined(separator: " ")
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
            group.leave()
        }
        _ = group.wait(timeout: DispatchTime.distantFuture)
        let finalFile = result + (!fileExt.isEmpty ? "." + fileExt : "")
        return (dirPath as NSString).appendingPathComponent(finalFile)
    }
    
    internal func throwError(_ path: String, code: FoundationErrorEnum) -> NSError {
        let fileURL = self.absoluteURL(path)
        let domain: String
        switch code {
        case is URLError:
            domain = NSURLErrorDomain
        default:
            domain = NSCocoaErrorDomain
        }
        return NSError(domain: domain, code: code.rawValue, userInfo: [NSURLErrorFailingURLErrorKey: fileURL, NSURLErrorFailingURLStringErrorKey: fileURL.absoluteString])
    }
    
    internal func NotImplemented() -> Never {
        assert(false, "method not implemented")
    }
    
    internal func resolve(dateString: String) -> Date? {
        let dateFor: DateFormatter = DateFormatter()
        dateFor.locale = Locale(identifier: "en_US")
        dateFor.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss zzz"
        if let rfc1123 = dateFor.date(from: dateString) {
            return rfc1123
        }
        dateFor.dateFormat = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
        if let rfc850 = dateFor.date(from: dateString) {
            return rfc850
        }
        dateFor.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
        if let asctime = dateFor.date(from: dateString) {
            return asctime
        }
        dateFor.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssz"
        if let isotime = dateFor.date(from: dateString) {
            return isotime
        }
        //self.init()
        return nil
    }
}


public protocol ExtendedFileProvider: FileProvider {
    func thumbnailOfFileSupported(path: String) -> Bool
    func propertiesOfFileSupported(path: String) -> Bool
    func thumbnailOfFile(path: String, dimension: CGSize, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void))
    func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String: Any], _ keys: [String], _ error: Error?) -> Void))
}

public enum FileOperationType: CustomStringConvertible {
    case create (path: String)
    case copy   (source: String, destination: String)
    case move   (source: String, destination: String)
    case modify (path: String)
    case remove (path: String)
    case link   (link: String, target: String)
    
    public var description: String {
        switch self {
        case .create(path: _): return "Create"
        case .copy(source: _, destination: _): return "Copy"
        case .move(source: _, destination: _): return "Move"
        case .modify(path: _): return "Modify"
        case .remove(path: _): return "Remove"
        case .link(link: _, target: _): return "Link"
        }
    }
    
    internal var actionDescription: String {
        switch self {
        case .create(path: _): return "Creating"
        case .copy(source: _, destination: _): return "Copying"
        case .move(source: _, destination: _): return "Moving"
        case .modify(path: _): return "Modifying"
        case .remove(path: _): return "Removing"
        case .link(link: _, target: _): return "Linking"
        }
    }
}

@objc
public protocol OperationHandle {
    var progress: Float { get }
    var bytesSoFar: Int64 { get }
    var totalBytes: Int64 { get }
    var inProgress: Bool { get }
    func cancel()
}

internal class Weak<T: AnyObject> {
    weak var value : T?
    init (_ value: T) {
        self.value = value
    }
}

public protocol FileProviderDelegate: class {
    func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType)
    func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType)
    func fileproviderProgress(_ fileProvider: FileProviderOperations, operation: FileOperationType, progress: Float)
}

public protocol FileOperationDelegate: class {
    
    /// fileProvider(_:shouldOperate:) gives the delegate an opportunity to filter the file operation. Returning true from this method will allow the copy to happen. Returning false from this method causes the item in question to be skipped. If the item skipped was a directory, no children of that directory will be subject of the operation, nor will the delegate be notified of those children.
    func fileProvider(_ fileProvider: FileProviderOperations, shouldDoOperation operation: FileOperationType) -> Bool
    
    /// fileProvider(_:shouldProceedAfterError:copyingItemAtPath:toPath:) gives the delegate an opportunity to recover from or continue copying after an error. If an error occurs, the error object will contain an ErrorType indicating the problem. The source path and destination paths are also provided. If this method returns true, the FileProvider instance will continue as if the error had not occurred. If this method returns false, the NSFileManager instance will stop copying, return false from copyItemAtPath:toPath:error: and the error will be provied there.
    func fileProvider(_ fileProvider: FileProviderOperations, shouldProceedAfterError error: Error, operation: FileOperationType) -> Bool
}

// THESE ARE METHODS TO PROVIDE COMPATIBILITY WITH SWIFT 2.3 SIMOULTANIOUSLY!

internal extension URL {
    var uw_scheme: String {
        return self.scheme ?? ""
    }
}

internal func jsonToDictionary(_ jsonString: String) -> [String: AnyObject]? {
    guard let data = jsonString.data(using: String.Encoding.utf8) else {
        return nil
    }
    if let dic = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] {
        return dic
    }
    return nil
}

internal func dictionaryToJSON(_ dictionary: [String: AnyObject]) -> String? {
    if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: JSONSerialization.WritingOptions()) {
        return String(data: data, encoding: String.Encoding.utf8)
    }
    return nil
}
