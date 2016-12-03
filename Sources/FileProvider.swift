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

public protocol FileProviderBasicRemote: FileProviderBasic {
    var session: URLSession { get }
    var cache: URLCache? { get }
    var useCache: Bool { get set }
    var validatingCache: Bool { get set }
}

internal extension FileProviderBasicRemote {
    func returnCachedDate(with request: URLRequest, validatingCache: Bool, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Swift.Void) -> Bool {
        guard let cache = self.cache else { return false }
        if let response = cache.cachedResponse(for: request) {
            var validatedCache = !validatingCache
            let lastModifiedDate = (response.response as? HTTPURLResponse)?.allHeaderFields["Last-Modified"] as? String
            let eTag = (response.response as? HTTPURLResponse)?.allHeaderFields["ETag"] as? String
            if lastModifiedDate == nil && eTag == nil, validatingCache {
                var validateRequest = request
                validateRequest.httpMethod = "HEAD"
                let group = DispatchGroup()
                group.enter()
                self.session.dataTask(with: validateRequest, completionHandler: { (_, response, e) in
                    if let httpResponse = response as? HTTPURLResponse {
                        let currentETag = httpResponse.allHeaderFields["ETag"] as? String
                        let currentLastModifiedDate = httpResponse.allHeaderFields["ETag"] as? String ?? "nonvalidetag"
                        validatedCache = (eTag != nil && currentETag == eTag)
                            || (lastModifiedDate != nil && currentLastModifiedDate == lastModifiedDate)
                    }
                    group.leave()
                }).resume()
                _ = group.wait(timeout: DispatchTime.now() + self.session.configuration.timeoutIntervalForRequest)
            }
            if validatedCache {
                completionHandler(response.data, response.response, nil)
                return true
            }
        }
        return false
    }
    
    func runDataTask(with request: URLRequest, operationHandle: RemoteOperationHandle? = nil, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Swift.Void) {
        let useCache = self.useCache
        let validatingCache = self.validatingCache
        dispatch_queue.async {
            if useCache {
                if self.returnCachedDate(with: request, validatingCache: validatingCache, completionHandler: completionHandler) {
                    return
                }
            }
            let task = self.session.dataTask(with: request, completionHandler: completionHandler)
            task.taskDescription = operationHandle?.operationType.json
            operationHandle?.add(task: task)
            task.resume()
        }
    }
}

public protocol FileProviderOperations: FileProviderBasic {
    var fileOperationDelegate : FileOperationDelegate? { get set }
    
    @discardableResult
    func create(folder: String, at: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func create(file: String, at: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle?
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

public protocol FileProvider: FileProviderBasic, FileProviderOperations, FileProviderReadWrite, NSCopying {
}

extension FileProviderBasic {
    public var type: String {
        return Self.type
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
            p.remove(at: p.endIndex)
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
                $0.hasPrefix(result)
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
    
    internal func NotImplemented() {
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
    case fetch  (path: String)
    
    public var description: String {
        switch self {
        case .create: return "Create"
        case .copy: return "Copy"
        case .move: return "Move"
        case .modify: return "Modify"
        case .remove: return "Remove"
        case .link: return "Link"
        case .fetch: return "Fetch"
        }
    }
    
    public var actionDescription: String {
        return description.trimmingCharacters(in: CharacterSet(charactersIn: "e")) + "ing"
    }
    
    public var source: String? {
        guard let reflect = Mirror(reflecting: self).children.first?.value else { return nil }
        let mirror = Mirror(reflecting: reflect)
        return reflect as? String ?? mirror.children.first?.value as? String
    }
    
    public var destination: String? {
        guard let reflect = Mirror(reflecting: self).children.first?.value else { return nil }
        let mirror = Mirror(reflecting: reflect)
        return mirror.children.dropFirst().first?.value as? String
    }
    
    internal var json: String? {
        var dictionary: [String: AnyObject] = ["type": self.description as NSString]
        dictionary["source"] = source as NSString?
        dictionary["dest"] = destination as NSString?
        return dictionaryToJSON(dictionary)
    }
}

open class FileObject {
    open internal(set) var allValues: [String: Any]
    
    internal init(allValues: [String: Any]) {
        self.allValues = allValues
    }
    
    internal init(absoluteURL: URL? = nil, name: String, path: String) {
        self.allValues = [String: Any]()
        self.absoluteURL = absoluteURL
        self.name = name
        self.path = path
    }
    
    open internal(set) var absoluteURL: URL? {
        get {
            return allValues["NSURLAbsoluteURLKey"] as? URL
        }
        set {
            allValues["NSURLAbsoluteURLKey"] = newValue
        }
    }
    
    open internal(set) var name: String {
        get {
            return allValues[URLResourceKey.nameKey.rawValue] as! String
        }
        set {
            allValues[URLResourceKey.nameKey.rawValue] = newValue
        }
    }
    
    open internal(set) var path: String {
        get {
            return allValues[URLResourceKey.pathKey.rawValue] as! String
        }
        set {
            allValues[URLResourceKey.pathKey.rawValue] = newValue
        }
    }
    
    open internal(set) var size: Int64 {
        get {
            return allValues[URLResourceKey.fileSizeKey.rawValue] as? Int64 ?? -1
        }
        set {
            allValues[URLResourceKey.fileSizeKey.rawValue] = Int(exactly: newValue) ?? Int.max
        }
    }
    
    open internal(set) var creationDate: Date? {
        get {
            return allValues[URLResourceKey.creationDateKey.rawValue] as? Date
        }
        set {
            allValues[URLResourceKey.creationDateKey.rawValue] = newValue
        }
    }
    
    open internal(set) var modifiedDate: Date? {
        get {
            return allValues[URLResourceKey.contentModificationDateKey.rawValue] as? Date
        }
        set {
            allValues[URLResourceKey.contentModificationDateKey.rawValue] = newValue
        }
    }
    
    open internal(set) var fileType: URLFileResourceType? {
        get {
            guard let typeString = allValues[URLResourceKey.fileResourceTypeKey.rawValue] as? String else {
                return nil
            }
            return URLFileResourceType(rawValue: typeString)
        }
        set {
            allValues[URLResourceKey.fileResourceTypeKey.rawValue] = newValue
        }
    }
    
    open internal(set) var isHidden: Bool {
        get {
            return allValues[URLResourceKey.isHiddenKey.rawValue] as? Bool ?? false
        }
        set {
            allValues[URLResourceKey.isHiddenKey.rawValue] = newValue
        }
    }
    
    open internal(set) var isReadOnly: Bool {
        get {
            return !(allValues[URLResourceKey.isWritableKey.rawValue] as? Bool ?? true)
        }
        set {
            allValues[URLResourceKey.isWritableKey.rawValue] = !newValue
        }
    }
    
    open var isDirectory: Bool {
        return self.fileType == .directory
    }
    
    open var isRegularFile: Bool {
        return self.fileType == .regular
    }
    
    open var isSymLink: Bool {
        return self.fileType == .symbolicLink
    }
}

public protocol OperationHandle {
    var operationType: FileOperationType { get }
    var bytesSoFar: Int64 { get }
    var totalBytes: Int64 { get }
    var inProgress: Bool { get }
    var progress: Float { get }
    func cancel() -> Bool
}

public extension OperationHandle {
    public var progress: Float {
        let bytesSoFar = self.bytesSoFar
        let totalBytes = self.totalBytes
        return totalBytes > 0 ? Float(Double(bytesSoFar) / Double(totalBytes)) : Float.nan
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

internal class Weak<T: AnyObject> {
    weak var value : T?
    init (_ value: T) {
        self.value = value
    }
}

extension URLFileResourceType {
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

internal func jsonToDictionary(_ jsonString: String) -> [String: AnyObject]? {
    guard let data = jsonString.data(using: .utf8) else {
        return nil
    }
    if let dic = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] {
        return dic
    }
    return nil
}

internal func dictionaryToJSON(_ dictionary: [String: AnyObject]) -> String? {
    if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: JSONSerialization.WritingOptions()) {
        return String(data: data, encoding: .utf8)
    }
    return nil
}
