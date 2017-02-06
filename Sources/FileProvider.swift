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
    /// An string to identify type of provider.
    static var type: String { get }
    
    /// An string to identify type of provider.
    var type: String { get }
    
    /// The paths in arguments should resolved against base url.
    var isPathRelative: Bool { get }
    
    /// The url of which paths should resolve against.
    var baseURL: URL? { get }
    
    /// Current active path used in `contentsOfDirectory(path:completionHandler:)` method.
    var currentPath: String { get set }
    
    /**
     Dispatch queue usually used in query methods.
     Set it to a new object to switch between cuncurrent and serial queues.
     - **Default:** Cuncurrent `DispatchQueue` object.
    */
    var dispatch_queue: DispatchQueue { get set }
    
    /// Operation queue ususlly used in file operation methods.
    /// use `maximumOperationTasks` property of provider to manage operation queue.
    var operation_queue: OperationQueue { get set }
    
    /// Delegate to update UI after finishing file operations.
    var delegate: FileProviderDelegate? { get set }
    
    /**
     login credential for provider. Should be set in `init` method.
     
     **Example initialization:**
     ````
     let credential = URLCredential(user: "user", password: "password", persistence: .forSeession)
     ````
     
     - Note: In OAuth based providers like `DropboxFileProvider` and `OneDriveFileProvider`, password is Token.
     use [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) library to fetch clientId and Token of user.
     */
    var credential: URLCredential? { get }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter completionHandler: a block with result of directory entries or error.
        `contents`: An array of `FileObject` identifying the the directory entries.
        `error`: Error returned by system.
     */
    func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void))
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameter path: path to target directory. If empty, `currentPath` value will be used.
     - Parameter completionHandler: a block with result of directory entries or error.
        `attributes`: A `FileObject` containing the attributes of the item.
        `error`: Error returned by system.
     */
    func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void))
    
    
    /// Returns total and used space in provider container asynchronously.
    func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void))
    
    /**
     Returns an independent url to access the file. Some providers like `Dropbox` due to their nature.
     don't return an absolute url to be used to access file directly.
     - Parameter path: Relative path of file or directory.
     - Returns: An url, can be used to access to file directly.
    */
    func url(of path: String?) -> URL
}

public extension FileProviderBasic {
    /// The maximum number of queued operations that can execute at the same time.
    ///
    /// The default value of this property is `OperationQueue.defaultMaxConcurrentOperationCount`.
    public var maximumOperationTasks: Int {
        get {
            return operation_queue.maxConcurrentOperationCount
        }
        set {
            operation_queue.maxConcurrentOperationCount = newValue
        }
    }
}

public var fileProviderCancelTasksOnInvalidating = true

public protocol FileProviderBasicRemote: FileProviderBasic {
    /// Underlying URLSession instance used for HTTP/S requests
    var session: URLSession { get }
    
    /// A `URLCache` to cache downloaded files and contents.
    ///
    /// If set to nil, `URLCache.shared` object will be used.
    /// - Note: It has no effect unless setting `useCache` property to `true`.
    var cache: URLCache? { get }
    
    /// Determine to use `cache` property to cache downloaded file objects. Doesn't have effect on query type methods.
    var useCache: Bool { get set }
    
    /// Validating cached data using E-Tag or Revision identifier if possible.
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
    /// Delgate for managing operations involving the copying, moving, linking, or removal of files and directories. When you use an FileManager object to initiate a copy, move, link, or remove operation, the file provider asks its delegate whether the operation should begin at all and whether it should proceed when an error occurs.
    var fileOperationDelegate : FileOperationDelegate? { get set }
    
    /**
     Creates a new directory at the specified path asynchronously. 
     This will create any necessary intermediate directories.
     
     - Parameters:
       - folder: Directory name.
       - at: Parent path of new directory.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     */
    @discardableResult
    func create(folder: String, at: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Creates an new file with data passed to method asynchronously. 
     Returns error via completionHandler if file is already exists.
     
     - Parameters:
       - file: New file name with extension separated by period.
       - at: Parent path of new file.
       - data: Data of new files. Pass nil or `Data()` to create empty file.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    
    func create(file: String, at: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Moves a file or directory from `path` to designated path asynchronously.
     When you want move a file, destination path should also consists of file name.
     Either a new name or the old one. If file is already exist, an error will be returned via completionHandler.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func moveItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Moves a file or directory from `path` to designated path asynchronously.
     When you want move a file, destination path should also consists of file name.
     Either a new name or the old one.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func moveItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Copies a file or directory from `path` to designated path asynchronously.
     When want copy a file, destination path should also consists of file name.
     Either a new name or the old one. If file is already exist, an error will be returned via completionHandler.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func copyItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Copies a file or directory from `path` to designated path asynchronously.
     When want copy a file, destination path should also consists of file name.
     Either a new name or the old one.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func copyItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Removes the file or directory at the specified path.
     
     - Parameters:
       - path: file or directory path.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     
     */
    @discardableResult
    func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Uploads a file from local file url to designated path asynchronously.
     Method will fail if source is not a local url with `file://` scheme.
     
     - Parameters:
       - localFile: a file url to file.
       - to: destination path of file, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress.
     */
    @discardableResult
    func copyItem(localFile: URL, to: String, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Uploads a file from local file url to designated path asynchronously.
     Method will fail if source is not a local url with `file://` scheme.
     
     - Parameters:
       - localFile: a file url to file.
       - to: destination path of file, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress.
     */
    @discardableResult
    func copyItem(localFile: URL, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Download a file from `path` to designated local file url asynchronously.
     Method will fail if destination is not a local url with `file://` scheme.
     
     - Parameters:
       - path: original file or directory path.
       - toLocalURL: destination local url of file, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
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
    /**
     Retreives a `Data` object with the contents of the file asynchronously vis contents argument of completion handler.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - completionHandler: a block with result of file contents or error.
         `contents`: contents of file in a `Data` object.
         `error`: Error returned by system.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
    */
    @discardableResult
    func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?
    
    /**
     Retreives a `Data` object with a portion contents of the file asynchronously vis contents argument of completion handler.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - offset: First byte index which should be read. **Starts from 0.**
       - length: Bytes count of data. Pass `-1` to read until the end of file.
       - completionHandler: a block with result of file contents or error.
         `contents`: contents of file in a `Data` object.
         `error`: Error returned by system.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     It will return error if file is already exists.
     Not attomically by default, unless the provider enforces it.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     It will return error if file is already exists.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file.
       - atomically: data will be written to a temporary file before writing to final location. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data, atomically: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     Not attomically by default, unless the provider enforces it.
     
     - Parameters:
     - path: Path of target file.
       - contents: Data to be written into file.
       - overwrite: Destination file should be overwritten if file is already exists. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file.
       - overwrite: Destination file should be overwritten if file is already exists. Default is `false`.
       - atomically: data will be written to a temporary file before writing to final location. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `OperationHandle` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle?
    
    /**
     Search files inside directory using query asynchronously.
     
     - Note: For now only it's limited to file names. `query` parameter may take `NSPredicate` format in near future.
     
     - Parameters:
       - path: location of directory to start search
       - recursive: Searching subdirectories of path
       - query: Simple string of file name to be search (for now).
       - foundItemHandler: Block which is called when a file is found
       - completionHandler: Block which will be called after finishing search. Returns an arry of `FileObject` or error if occured.
     */
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
    
    /**
     Starts monitoring a path and its subpaths, including files and folders, for any change,
     including copy, move/rename, content changes, etc.
     To avoid thread congestion, `evetHandler` will be triggered with 0.2 seconds interval,
     and has a 0.25 second delay, to ensure it's called after updates.
     
     - Note: this functionality is available only in `LocalFileProvider` and `CloudFileProvider`.
     - Note: `eventHandler` is not called on main thread, for updating UI. dispatch routine to main thread.
     - Important: `eventHandler` may be called if file is changed in recursive subpaths of registered path.
       This may cause negative impact on performance if a root path is being monitored.
    
     - Parameters:
       - path: path of directory.
       - eventHandler: Block executed after change, on a secondary thread.
     */
    func registerNotifcation(path: String, eventHandler: @escaping (() -> Void))
    
    /// Stops monitoring the path.
    ///
    /// - Parameter path: path of directory.
    func unregisterNotifcation(path: String)
    
    /// Investigate either the path is registered for change notification or not.
    ///
    /// - Parameter path: path of directory.
    /// - Returns: Directory is being monitored or not.
    func isRegisteredForNotification(path: String) -> Bool
}

public protocol FileProvider: FileProviderBasic, FileProviderOperations, FileProviderReadWrite, NSCopying {
}

internal let pathTrimSet = CharacterSet(charactersIn: " /")
extension FileProviderBasic {
    public var type: String {
        return Self.type
    }
    
    /// path without heading and trailing slash
    public var bareCurrentPath: String {
        return currentPath.trimmingCharacters(in: pathTrimSet)
    }
    
    func escaped(path: String) -> String {
        return path.trimmingCharacters(in: pathTrimSet).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }
    
    /// **OBSOLETED:** Use `url(of:).absoluteURL` instead.
    @available(*, obsoleted: 1.0, renamed: "url(of:)", message: "Use url(of:).absoluteURL instead.")
    public func absoluteURL(_ path: String? = nil) -> URL {
        return url(of: path).absoluteURL
    }
    
    public func url(of path: String? = nil) -> URL {
        var rpath: String
        if let path = path {
            rpath = path
        } else {
            rpath = self.currentPath
        }
        rpath = rpath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rpath
        if let baseURL = baseURL {
            if isPathRelative && rpath.hasPrefix("/") {
                rpath.remove(at: rpath.startIndex)
            }
            return URL(string: rpath, relativeTo: baseURL) ?? baseURL
        } else {
            return URL(string: rpath)!
        }
    }
    
    
    /// Returns the relative path of url, wothout percent encoding. Even if url is absolute or
    /// retrieved from another provider, it will try to resolve the url against `baseURL` of
    /// current provider. It's highly recomended to use this method for displaying purposes.
    ///
    /// - Parameter url: Absolute url to file or directory.
    /// - Returns: A `String` contains relative path of url against base url.
    public func relativePathOf(url: URL) -> String {
        // check if url derieved from current base url
        if url.relativeString.isEmpty, url.baseURL == self.baseURL {
            return url.relativePath.removingPercentEncoding!
        }
        
        // resolve url string against baseurl
        guard let baseURL = self.baseURL?.standardizedFileURL else { return url.absoluteString }
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
    
    /// Returns a file name supposed to be unique with adding numbers to end of file.
    /// - Important: It's a synchronous method. Don't use it on matin thread.
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
                $0.url?.lastPathComponent ?? $0.name
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
        let fileURL = self.url(of: path)
        let domain: String
        switch code {
        case is URLError:
            domain = NSURLErrorDomain
        default:
            domain = NSCocoaErrorDomain
        }
        return NSError(domain: domain, code: code.rawValue, userInfo: [NSURLErrorFailingURLErrorKey: fileURL, NSURLErrorFailingURLStringErrorKey: fileURL.absoluteString])
    }
    
    internal func NotImplemented(_ fn: String = #function, file: StaticString = #file) {
        assert(false, "\(fn) method is not yet implemented. \(file)")
    }
}

public protocol ExtendedFileProvider: FileProviderBasic {
    /// Returuns true if thumbnail preview is supported by provider and file type accordingly.
    ///
    /// - Parameter path: path of file.
    /// - Returns: A `Bool` idicates path can have thumbnail.
    func thumbnailOfFileSupported(path: String) -> Bool
    
    /// Returns true if provider supports fetching properties of file like dimensions, duration, etc.
    /// Usually media or document files support these meta-infotmations.
    ///
    /// - Parameter path: path of file.
    /// - Returns: A `Bool` idicates path can have properties.
    func propertiesOfFileSupported(path: String) -> Bool
    
    /**
     Generates ans returns a thumbnail preview of document asynchronously. The defualt dimension of returned image is different
     regarding provider type, usually 64x64 pixels.
     
     - Parameters:
       - path: path of file.
       - completionHandler: a block with result of preview image or error.
         `image`: `NSImage`/`UIImage` object contains preview.
         `error`: Error returned by system.
    */
    func thumbnailOfFile(path: String, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void))
    
    /**
     Generates ans returns a thumbnail preview of document asynchronously. The defualt dimension of returned image is different
     regarding provider type, usually 64x64 pixels. Default value used when `dimenstion` is `nil`.
     
     - Note: `LocalFileInformationGenerator` variables can be set to change default behavior of
             thumbnail and properties generator of `LocalFileProvider`.
     
     - Parameters:
       - path: path of file.
       - dimension: width and height of result preview image.
       - completionHandler: a block with result of preview image or error.
         `image`: `NSImage`/`UIImage` object contains preview.
     `error`: Error returned by system.
     */
    func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void))
    
    /**
     Fetching properties of file like dimensions, duration, etc. It's variant depending on file type.
     Images, videos and audio files meta-information will be returned.
     
     - Note: `LocalFileInformationGenerator` variables can be set to change default behavior of 
             thumbnail and properties generator of `LocalFileProvider`.
     
     - Parameters:
       - path: path of file.
       - completionHandler: a block with result of preview image or error.
         `propertiesDictionary`: A `Dictionary` of proprty keys and values.
         `keys`: An `Array` contains ordering of keys.
         `error`: Error returned by system.
     */
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

/// Operation type description of file operation, included files path in associated values.
public enum FileOperationType: CustomStringConvertible {
    /// Creating a file or directory in path.
    case create (path: String)
    /// Copying a file or directory from source to destination.
    case copy   (source: String, destination: String)
    /// Moving a file or directory from source to destination.
    case move   (source: String, destination: String)
    /// Modifying data of a file o in path by writing new data.
    case modify (path: String)
    /// Deleting file or directory in path.
    case remove (path: String)
    /// Creating a symbolic link or alias to target.
    case link   (link: String, target: String)
    /// Fetching data in file located in path.
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
    
    /// present participle of action, like 'Copying`.
    public var actionDescription: String {
        return description.trimmingCharacters(in: CharacterSet(charactersIn: "e")) + "ing"
    }
    
    /// Path of subjecting file.
    public var source: String? {
        guard let reflect = Mirror(reflecting: self).children.first?.value else { return nil }
        let mirror = Mirror(reflecting: reflect)
        return reflect as? String ?? mirror.children.first?.value as? String
    }
    
    /// Path of subjecting file.
    public var path: String? {
        return source
    }
    
    /// Path of destination file.
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
    /// Operation supposed to be done on files. Contains file paths as associated value.
    var operationType: FileOperationType { get }
    
    /// Bytes written/read by operation so far.
    var bytesSoFar: Int64 { get }
    
    /// Total bytes of operation.
    var totalBytes: Int64 { get }
    
    /// Operation is progress or not, Returns false if operation is done or not initiated yet.
    var inProgress: Bool { get }
    
    /// Progress of operation, usually equals with `bytesSoFar/totalBytes`. or NaN if not available.
    var progress: Float { get }
    
    /// Cancels operation while in progress, or cancels data/download/upload url session task.
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
    /// fileproviderSucceed(_:operation:) gives delegate a notification when an operation finished with success.
    /// This method is called in main thread to avoids UI bugs.
    func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType)
    /// fileproviderSucceed(_:operation:) gives delegate a notification when an operation finished with failure.
    /// This method is called in main thread to avoids UI bugs.
    func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType)
    /// fileproviderSucceed(_:operation:) gives delegate a notification when an operation progess.
    /// Supported by some providers, especially remote ones.
    /// This method is called in main thread to avoids UI bugs.
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
