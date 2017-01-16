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
#elseif os(macOS)
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
    
    func url(of path: String?) -> URL
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
    func moveItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func moveItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(localFile: URL, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(localFile: URL, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle?
}

extension FileProviderOperations {
    @discardableResult
    public func moveItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.moveItem(path: path, to: to, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func copyItem(localFile: URL, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.copyItem(localFile: localFile, to: to, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func copyItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.copyItem(path: path, to: to, overwrite: false, completionHandler: completionHandler)
    }
}

public protocol FileProviderReadWrite: FileProviderBasic {
    @discardableResult
    func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?
    @discardableResult
    func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?
    
    @discardableResult
    func writeContents(path: String, contents: Data, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func writeContents(path: String, contents: Data, atomically: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func writeContents(path: String, contents: Data, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    @discardableResult
    func writeContents(path: String, contents: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void))
}

extension FileProviderReadWrite {
    @discardableResult
    public func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?{
        return self.contents(path: path, offset: 0, length: -1, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func writeContents(path: String, contents: Data, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.writeContents(path: path, contents: contents, atomically: false, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func writeContents(path: String, contents: Data, atomically: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.writeContents(path: path, contents: contents, atomically: atomically, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func writeContents(path: String, contents: Data, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.writeContents(path: path, contents: contents, atomically: false, overwrite: overwrite, completionHandler: completionHandler)
    }
}

public protocol FileProviderMonitor: FileProviderBasic {
    func registerNotifcation(path: String, eventHandler: @escaping (() -> Void))
    func unregisterNotifcation(path: String)
    func isRegisteredForNotification(path: String) -> Bool
}

public protocol FileProvider: FileProviderBasic, FileProviderOperations, FileProviderReadWrite, NSCopying {
}

fileprivate let pathTrimSet = CharacterSet(charactersIn: " /")
extension FileProviderBasic {
    public var type: String {
        return Self.type
    }
    
    public var bareCurrentPath: String {
        return currentPath.trimmingCharacters(in: pathTrimSet)
    }
    
    func escaped(path: String) -> String {
        return path.trimmingCharacters(in: pathTrimSet)
    }
    
    public func absoluteURL(_ path: String? = nil) -> URL {
        return url(of: path).absoluteURL
    }
    
    public func url(of path: String? = nil) -> URL {
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
                return URL(string: npath, relativeTo: baseURL)!
            } else {
                return URL(string: rpath, relativeTo: baseURL)!
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
            p.remove(at: p.index(before:p.endIndex))
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
    
    public func string(from date:Date) -> String {
        let fm = DateFormatter()
        fm.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
        fm.timeZone = TimeZone(identifier:"UTC")
        fm.locale = Locale(identifier:"en_US_POSIX")
        return fm.string(from:date)
    }
    
}

public protocol ExtendedFileProvider: FileProviderBasic {
    func thumbnailOfFileSupported(path: String) -> Bool
    func propertiesOfFileSupported(path: String) -> Bool
    func thumbnailOfFile(path: String, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void))
    func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void))
    func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String: Any], _ keys: [String], _ error: Error?) -> Void))
}

extension ExtendedFileProvider {
    public func thumbnailOfFile(path: String, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
        self.thumbnailOfFile(path: path, dimension: nil, completionHandler: completionHandler)
    }
    
    internal static func formatshort(interval: TimeInterval) -> String {
        var result = "0:00"
        if interval < TimeInterval(Int32.max) {
            result = ""
            var time = DateComponents()
            time.hour   = Int(interval / 3600)
            time.minute = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            time.second = Int(interval.truncatingRemainder(dividingBy: 60))
            let formatter = NumberFormatter()
            formatter.paddingCharacter = "0"
            formatter.minimumIntegerDigits = 2
            formatter.maximumFractionDigits = 0
            let formatterFirst = NumberFormatter()
            formatterFirst.maximumFractionDigits = 0
            if time.hour! > 0 {
                result = "\(formatterFirst.string(from: NSNumber(value: time.hour!))!):\(formatter.string(from: NSNumber(value: time.minute!))!):\(formatter.string(from: NSNumber(value: time.second!))!)"
            } else {
                result = "\(formatterFirst.string(from: NSNumber(value: time.minute!))!):\(formatter.string(from: NSNumber(value: time.second!))!)"
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        return result
    }
    
    internal static func dataIsPDF(_ data: Data) -> Bool {
        return data.count > 4 && data.scanString(length: 4, encoding: .ascii) == "%PDF"
    }
    
    internal static func convertToImage(pdfData: Data?, page: Int = 1) -> ImageClass? {
        guard let pdfData = pdfData else { return nil }
        
        let cfPDFData: CFData = pdfData as CFData
        if let provider = CGDataProvider(data: cfPDFData), let reference = CGPDFDocument(provider), let pageRef = reference.page(at: page) {
            let frame = pageRef.getBoxRect(CGPDFBox.mediaBox)
            var size = frame.size
            let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            
            #if os(macOS)
                let ppp = Int(NSScreen.main()?.backingScaleFactor ?? 1) // fetch device is retina or not
                
                size.width  *= CGFloat(ppp)
                size.height *= CGFloat(ppp)
                
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: NSCalibratedRGBColorSpace,
                    bytesPerRow: 0, bitsPerPixel: 0)
                
                guard let context = NSGraphicsContext(bitmapImageRep: rep!) else {
                    return nil
                }
                
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.setCurrent(context)
                
                let transform = pageRef.getDrawingTransform(CGPDFBox.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true)
                context.cgContext.concatenate(transform)
                
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: CGFloat(ppp), y: CGFloat(-ppp))
                context.cgContext.drawPDFPage(pageRef)
                
                let resultingImage = NSImage(size: size)
                resultingImage.addRepresentation(rep!)
                return resultingImage
            #else
                let ppp = Int(UIScreen.main.scale) // fetch device is retina or not
                guard let context = UIGraphicsGetCurrentContext() else {
                    return nil
                }
                size.width  *= CGFloat(ppp)
                size.height *= CGFloat(ppp)
                UIGraphicsBeginImageContext(size)
                
                context.saveGState()
                let transform = pageRef.getDrawingTransform(CGPDFBox.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true)
                context.concatenate(transform)
                
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: CGFloat(ppp), y: CGFloat(-ppp))
                context.drawPDFPage(pageRef)
                
                context.restoreGState()
                let resultingImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return resultingImage
            #endif
        }
        return nil
    }
    
    internal static func scaleDown(image: ImageClass, toSize maxSize: CGSize) -> ImageClass {
        let height, width: CGFloat
        if image.size.width > image.size.height {
            width = maxSize.width
            height = (image.size.height / image.size.width) * width
        } else {
            height = maxSize.height
            width = (image.size.width / image.size.height) * height
        }
        
        let newSize = CGSize(width: width, height: height)
        
        #if os(macOS)
            var imageRect = NSRect(origin: CGPoint.zero, size: image.size)
            let imageRef = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
            
            // Create NSImage from the CGImage using the new size
            return NSImage(cgImage: imageRef!, size: newSize)
        #else
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            image.draw(in: CGRect(origin: CGPoint.zero, size: newSize))
            let newImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            return newImage
        #endif
    }
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

internal class Weak<T: AnyObject> {
    weak var value : T?
    init (_ value: T) {
        self.value = value
    }
}

public protocol FoundationErrorEnum {
    init? (rawValue: Int)
    var rawValue: Int { get }
}

extension URLError.Code: FoundationErrorEnum {}
extension CocoaError.Code: FoundationErrorEnum {}
