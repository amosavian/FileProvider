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

/// Completion handler type with an error argument
public typealias SimpleCompletionHandler = ((_ error: Error?) -> Void)?

/// This protocol defines FileProvider neccesary functions and properties to connect and get contents list
public protocol FileProviderBasic: class, NSSecureCoding {
    /// An string to identify type of provider.
    static var type: String { get }
    
    /// An string to identify type of provider.
    var type: String { get }
    
    /// The url of which paths should resolve against.
    var baseURL: URL? { get }
    
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
     provider.credential = URLCredential(user: "user", password: "password", persistence: .forSeession)
     ````
     
     - Note: In OAuth based providers like `DropboxFileProvider` and `OneDriveFileProvider`, password is Token.
     use [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) library to fetch clientId and Token of user.
     */
    var credential: URLCredential? { get set }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameters:
       - path: path to target directory. If empty, root will be iterated.
       - completionHandler: a closure with result of directory entries or error.
       - contents: An array of `FileObject` identifying the the directory entries.
       - error: Error returned by system.
     */
    func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void)
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameters:
       - path: path to target directory. If empty, attributes of root will be returned.
       - completionHandler: a closure with result of directory entries or error.
       - attributes: A `FileObject` containing the attributes of the item.
       - error: Error returned by system.
     */
    func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void)
    
    
    /// Returns volume/provider information asynchronously.
    /// - Parameter volumeInfo: Information of filesystem/Provider returned by system/server.
    func storageProperties(completionHandler: @escaping (_ volumeInfo: VolumeObject?) -> Void)
    
    /**
     Search files inside directory using query asynchronously.
     
     - Note: Query string is limited to file name, to search based on other file attributes, use NSPredicate version.
     
     - Parameters:
       - path: location of directory to start search
       - recursive: Searching subdirectories of path
       - query: Simple string that file name begins with to be search, case-insensitive.
       - foundItemHandler: Closure which is called when a file is found
       - completionHandler: Closure which will be called after finishing search. Returns an arry of `FileObject` or error if occured.
       - files: all files meat the `query` criteria.
       - error: `Error` returned by server if occured.
     */
    @discardableResult
    func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress?
    
    /**
     Search files inside directory using query asynchronously.
     
     Sample predicates:
     ```
     NSPredicate(format: "(name CONTAINS[c] 'hello') && (fileSize >= 10000)")
     NSPredicate(format: "(modifiedDate >= %@)", Date())
     NSPredicate(format: "(path BEGINSWITH %@)", "folder/child folder")
     ```
     
     - Note: Don't pass Spotlight predicates to this method directly, use `FileProvider.convertSpotlightPredicateTo()` method to get usable predicate.
     
     - Important: A file name criteria should be provided for Dropbox.
     
     - Parameters:
       - path: location of directory to start search
       - recursive: Searching subdirectories of path
       - query: An `NSPredicate` object with keys like `FileObject` members, except `size` which becomes `filesize`.
       - foundItemHandler: Closure which is called when a file is found
       - completionHandler: Closure which will be called after finishing search. Returns an arry of `FileObject` or error if occured.
       - files: all files meat the `query` criteria.
       - error: `Error` returned by server if occured.
     - Returns: An `Progress` to get progress or cancel progress. Use `completedUnitCount` to iterate count of found items.
     */
    @discardableResult
    func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress?
    
    /**
     Returns an independent url to access the file. Some providers like `Dropbox` due to their nature.
     don't return an absolute url to be used to access file directly.
     - Parameter path: Relative path of file or directory.
     - Returns: An url, can be used to access to file directly.
    */
    func url(of path: String) -> URL
    
    
    /// Returns the relative path of url, without percent encoding. Even if url is absolute or
    /// retrieved from another provider, it will try to resolve the url against `baseURL` of
    /// current provider. It's highly recomended to use this method for displaying purposes.
    ///
    /// - Parameter url: Absolute url to file or directory.
    /// - Returns: A `String` contains relative path of url against base url.
    func relativePathOf(url: URL) -> String
    
    /// Checks the connection to server or permission on local
    ///
    /// - Note: To prevent race condition, use this method wisely and avoid it as far possible.
    ///
    /// - Parameter success: indicated server is reachable or not.
    /// - Parameter error: `Error` returned by server if occured.
    func isReachable(completionHandler: @escaping(_ success: Bool, _ error: Error?) -> Void)
}

extension FileProviderBasic {
    public func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let predicate = NSPredicate(format: "name BEGINSWITH[c] %@", query)
        return self.searchFiles(path: path, recursive: recursive, query: predicate, foundItemHandler: foundItemHandler, completionHandler: completionHandler)
    }
    
    /**
     Search files inside directory using query asynchronously.
     
     Sample predicates:
     ```
     NSPredicate(format: "(name CONTAINS[c] 'hello') && (filesize >= 10000)")
     NSPredicate(format: "(modifiedDate >= %@)", Date())
     NSPredicate(format: "(path BEGINSWITH %@)", "folder/child folder")
     ```
     
     - Note: Don't pass Spotlight predicates to this method directly, use `FileProvider.convertSpotlightPredicateTo()` method to get usable predicate.
     
     - Important: A file name criteria should be provided for Dropbox.
     
     - Parameters:
     - path: location of directory to start search
     - recursive: Searching subdirectories of path
     - query: An `NSPredicate` object with keys like `FileObject` members, except `size` which becomes `filesize`.
     - completionHandler: Closure which will be called after finishing search. Returns an arry of `FileObject` or error if occured.
     - files: all files meat the `query` criteria.
     - error: `Error` returned by server if occured.
     - Returns: An `Progress` to get progress or cancel progress. Use `completedUnitCount` to iterate count of found items.
     */
    func searchFiles(path: String, recursive: Bool, query: NSPredicate, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        return searchFiles(path: path, recursive: recursive, query: query, foundItemHandler: nil, completionHandler: completionHandler)
    }
    
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

/// Checking equality of two file provider, regardless of current path queues and delegates.
public func ==(lhs: FileProviderBasic, rhs: FileProviderBasic) -> Bool {
    if lhs === rhs { return true }
    if type(of: lhs) != type(of: rhs) {
        return false
    }
    return lhs.type == rhs.type && lhs.baseURL == rhs.baseURL && lhs.credential == rhs.credential
}

/// Cancels all active underlying tasks when deallocating remote providers
public var fileProviderCancelTasksOnInvalidating = true

/// Extending `FileProviderBasic` for web-based file providers
public protocol FileProviderBasicRemote: FileProviderBasic {
    /// Underlying URLSession instance used for HTTP/S requests
    var session: URLSession { get }
    
    /**
     A `URLCache` to cache downloaded files and contents.
     
     - Note: It has no effect unless setting `useCache` property to `true`.
     
     - Warning: FileProvider doesn't manage/free `URLCache` object in a memory pressure scenario. It's upon you to clear
     cache memory when receiving `didReceiveMemoryWarning` or via observing `.UIApplicationDidReceiveMemoryWarning` notification.
     To clear memory usage use this code:
     ```
     provider.cache?.removeAllCachedResponses()
     ```
     */
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
                _ = group.wait(timeout: .now() + self.session.configuration.timeoutIntervalForRequest)
            }
            if validatedCache {
                completionHandler(response.data, response.response, nil)
                return true
            }
        }
        return false
    }
    
    func runDataTask(with request: URLRequest, operation: FileOperationType? = nil, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Swift.Void) {
        let useCache = self.useCache
        let validatingCache = self.validatingCache
        dispatch_queue.async {
            if useCache {
                if self.returnCachedDate(with: request, validatingCache: validatingCache, completionHandler: completionHandler) {
                    return
                }
            }
            let task = self.session.dataTask(with: request, completionHandler: completionHandler)
            task.taskDescription = operation?.json
            task.resume()
        }
    }
}

/// Defines methods for common file operaions including create, copy/move and delete
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
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func create(folder: String, at: String, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Moves a file or directory from `path` to designated path asynchronously.
     When you want move a file, destination path should also consists of file name.
     Either a new name or the old one. If file is already exist, an error will be returned via completionHandler.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func moveItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Moves a file or directory from `path` to designated path asynchronously.
     When you want move a file, destination path should also consists of file name.
     Either a new name or the old one.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func moveItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Copies a file or directory from `path` to designated path asynchronously.
     When want copy a file, destination path should also consists of file name.
     Either a new name or the old one. If file is already exist, an error will be returned via completionHandler.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func copyItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Copies a file or directory from `path` to designated path asynchronously.
     When want copy a file, destination path should also consists of file name.
     Either a new name or the old one.
     
     - Parameters:
       - path: original file or directory path.
       - to: destination path of file or directory, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func copyItem(path: String, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Removes the file or directory at the specified path.
     
     - Parameters:
       - path: file or directory path.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     
     */
    @discardableResult
    func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Uploads a file from local file url to designated path asynchronously.
     Method will fail if source is not a local url with `file://` scheme.
     
     - Note: It's safe to assume that this method only works on individual files and **won't** copy folders recursively.
     
     - Parameters:
       - localFile: a file url to file.
       - to: destination path of file, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress.
     */
    @discardableResult
    func copyItem(localFile: URL, to: String, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Uploads a file from local file url to designated path asynchronously.
     Method will fail if source is not a local url with `file://` scheme.
     
     - Note: It's safe to assume that this method only works on individual files and **won't** copy folders recursively.
     
     - Parameters:
       - localFile: a file url to file.
       - to: destination path of file, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress.
     */
    @discardableResult
    func copyItem(localFile: URL, to: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Download a file from `path` to designated local file url asynchronously.
     Method will fail if destination is not a local url with `file://` scheme.
     
     - Note: It's safe to assume that this method only works on individual files and **won't** copy folders recursively.
     
     - Parameters:
       - path: original file or directory path.
       - toLocalURL: destination local url of file, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> Progress?
}

public extension FileProviderOperations {
    @discardableResult
    public func moveItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.moveItem(path: path, to: to, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func copyItem(localFile: URL, to: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.copyItem(localFile: localFile, to: to, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func copyItem(path: String, to: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.copyItem(path: path, to: to, overwrite: false, completionHandler: completionHandler)
    }
}

internal extension FileProviderOperations {
    internal func delegateNotify(_ operation: FileOperationType, error: Error? = nil) {
        DispatchQueue.main.async(execute: {
            if let error = error {
                self.delegate?.fileproviderFailed(self, operation: operation, error: error)
            } else {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            }
        })
    }
    
    internal func delegateNotify(_ operation: FileOperationType, progress: Double) {
        DispatchQueue.main.async(execute: {
            self.delegate?.fileproviderProgress(self, operation: operation, progress: Float(progress))
        })
    }
}

/// Defines method for fetching and modifying file contents
public protocol FileProviderReadWrite: FileProviderBasic {
    /**
     Retreives a `Data` object with the contents of the file asynchronously vis contents argument of completion handler.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - completionHandler: a closure with result of file contents or error.
       - contents: contents of file in a `Data` object.
       - error: `Error` returned by system if occured.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
    */
    @discardableResult
    func contents(path: String, completionHandler: @escaping (_ contents: Data?, _ error: Error?) -> Void) -> Progress?
    
    /**
     Retreives a `Data` object with a portion contents of the file asynchronously vis contents argument of completion handler.
     If path specifies a directory, or if some other error occurs, data will be nil.
     
     - Parameters:
       - path: Path of file.
       - offset: First byte index which should be read. **Starts from 0.**
       - length: Bytes count of data. Pass `-1` to read until the end of file.
       - completionHandler: a closure with result of file contents or error.
       - contents: contents of file in a `Data` object.
       - error: Error returned by system if occured.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping (_ contents: Data?, _ error: Error?) -> Void) -> Progress?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     It will return error if file is already exists.
     Not attomically by default, unless the provider enforces it.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file, pass nil to create empty file.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data?, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     It will return error if file is already exists.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file, pass nil to create empty file.
       - atomically: data will be written to a temporary file before writing to final location. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data?, atomically: Bool, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     Not attomically by default, unless the provider enforces it.
     
     - Parameters:
     - path: Path of target file.
       - contents: Data to be written into file, pass nil to create empty file.
       - overwrite: Destination file should be overwritten if file is already exists. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data?, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress?
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file, pass nil to create empty file.
       - overwrite: Destination file should be overwritten if file is already exists. Default is `false`.
       - atomically: data will be written to a temporary file before writing to final location. Default is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    func writeContents(path: String, contents: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress?
}

extension FileProviderReadWrite {
    @discardableResult
    public func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        return self.contents(path: path, offset: 0, length: -1, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func writeContents(path: String, contents: Data?, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.writeContents(path: path, contents: contents, atomically: false, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func writeContents(path: String, contents: Data?, atomically: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.writeContents(path: path, contents: contents, atomically: atomically, overwrite: false, completionHandler: completionHandler)
    }
    
    @discardableResult
    public func writeContents(path: String, contents: Data?, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.writeContents(path: path, contents: contents, atomically: false, overwrite: overwrite, completionHandler: completionHandler)
    }
}

/// Allows a file provider to notify changes occured
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
       - eventHandler: Closure executed after change, on a secondary thread.
     */
    func registerNotifcation(path: String, eventHandler: @escaping () -> Void)
    
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

#if os(macOS) || os(iOS) || os(tvOS)
/// Allows undo file operations done by provider
public protocol FileProvideUndoable: FileProviderOperations {
    /// To initialize undo manager either call `setupUndoManager()` or set it manually.
    ///
    /// - Note: Only some operations (moving/renaming, copying and creating) are supported for undoing.
    /// - Note: recording operations will occur after setting this object.
    var undoManager: UndoManager? { get set }
    
    /// UndoManager supports undoing this file operation
    /// - Parameter handle: determines wheither this progress can be rolled back or not.
    func canUndo(handle: Progress) -> Bool
    /// UndoManager supports undoing this operation
    /// - Parameter operation: determines wheither this operation can be rolled back or not.
    func canUndo(operation: FileOperationType) -> Bool
}

public extension FileProvideUndoable {
    public func canUndo(operation: FileOperationType) -> Bool {
        return undoOperation(for: operation) != nil
    }
    
    public func canUndo(handle: Progress) -> Bool {
        if let operationType = handle.userInfo[.fileProvderOperationTypeKey] as? FileOperationType {
            return canUndo(operation: operationType)
        }
        return false
    }
    
    /// Reuturns roll back operation for provided `operation`.
    internal func undoOperation(for operation: FileOperationType) -> FileOperationType? {
        switch operation {
        case .create(path: let path):
            return .remove(path: path)
        case .modify(path: _):
            return nil
        case .copy(source: _, destination: let dest):
            return .remove(path: dest)
        case .move(source: let source, destination: let dest):
            return .move(source: dest, destination: source)
        case .link(link: let link, target: _):
            return .remove(path: link)
        case .remove(path: _):
            return nil
        default:
            return nil
        }
    }
    
    /// Initiates `self.undoManager` if equals with `nil`, and set `levelsOfUndo` to 10.
    public func setupUndoManager() {
        guard self.undoManager == nil else { return }
        self.undoManager = UndoManager()
        self.undoManager?.levelsOfUndo = 10
    }
}
#endif

/// This protocol defines method to share a public link with other users
public protocol FileProviderSharing {
    /**
     Genrates a public url to a file to be shared with other users and can be downloaded without authentication.
     
     - Important: In some providers url will be available for a limitied time, determined in `expiration` argument.
         e.g. Dropbox links will be expired after 4 hours.
     
     - Parameters:
         - to: path of file, including file/directory name.
         - completionHandler: a closure with result of directory entries or error.
         - link: a url returned by Dropbox to share.
         - attribute: a `FileObject` containing the attributes of the item.
         - expiration: a `Date` object, determines when the public url will expires.
         - error: Error returned by server.
     */
    func publicLink(to path: String, completionHandler: @escaping (_ link: URL?, _ attribute: FileObject?, _ expiration: Date?, _ error: Error?) -> Void)
}

/// Defines protocol for provider allows all common operations.
public protocol FileProvider: FileProviderOperations, FileProviderReadWrite, NSCopying {
}

internal let pathTrimSet = CharacterSet(charactersIn: " /")
public extension FileProviderBasic {
    public var type: String {
        #if swift(>=3.1)
        return Swift.type(of: self).type
        #else
        return type(of: self).type
        #endif
    }
    
    public func url(of path: String) -> URL {
        var rpath: String = path
        rpath = rpath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? rpath
        if let baseURL = baseURL {
            if rpath.hasPrefix("/") {
                rpath.remove(at: rpath.startIndex)
            }
            return URL(string: rpath, relativeTo: baseURL) ?? baseURL
        } else {
            return URL(string: rpath) ?? URL(string: "/")!
        }
    }
    
    public func relativePathOf(url: URL) -> String {
        // check if url derieved from current base url
        let relativePath = url.relativePath
        if !relativePath.isEmpty, url.baseURL == self.baseURL {
            return (relativePath.removingPercentEncoding ?? relativePath).replacingOccurrences(of: "/", with: "", options: .anchored)
        }
        
        // resolve url string against baseurl
        guard let baseURL = self.baseURL else { return url.absoluteString }
        let standardRelativePath = url.absoluteString.replacingOccurrences(of: baseURL.absoluteString, with: "/").replacingOccurrences(of: "/", with: "", options: .anchored)
        if URLComponents(string: standardRelativePath)?.host?.isEmpty ?? true {
            return standardRelativePath.removingPercentEncoding ?? standardRelativePath
        } else {
            return relativePath.replacingOccurrences(of: "/", with: "", options: .anchored)
        }
    }
    
    /// Returns a file name supposed to be unique with adding numbers to end of file.
    /// - Important: It's a synchronous method. Don't use it on main thread.
    /// - Parameter filePath: supposed path of file which should be examined.
    public func fileByUniqueName(_ filePath: String) -> String {
        //assert(!Thread.isMainThread, "\(#function) is not recommended to be executed on Main Thread.")
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
                $0.url.lastPathComponent.isEmpty ? $0.name : $0.url.lastPathComponent
            }.filter {
                $0.hasPrefix(result)
            }
            while similiar.contains(result + (!fileExt.isEmpty ? "." + fileExt : "")) {
                result = "\(bareFileName) \(i)"
                i += 1
            }
            group.leave()
        }
        _ = group.wait(timeout: .now() + 5)
        let finalFile = result + (!fileExt.isEmpty ? "." + fileExt : "")
        return (dirPath as NSString).appendingPathComponent(finalFile)
    }
    
    internal func urlError(_ path: String, code: URLError.Code) -> Error {
        let fileURL = self.url(of: path)
        var userInfo: [String: Any] = [NSURLErrorKey: fileURL,
                                       NSURLErrorFailingURLErrorKey: fileURL,
                                       NSURLErrorFailingURLStringErrorKey: fileURL.absoluteString,
                                       ]
        let error = NSError(domain: NSURLErrorDomain, code: code.rawValue, userInfo: nil)
        for (key, value) in error.userInfo {
            userInfo[key] = value
        }
        return URLError(code, userInfo: userInfo)
    }
    
    internal func cocoaError(_ path: String, code: CocoaError.Code) -> Error {
        let fileURL = self.url(of: path)
        var userInfo: [String: Any] = [NSFilePathErrorKey: path,
                                       NSURLErrorKey: fileURL,
                                       ]
        let error = NSError(domain: NSCocoaErrorDomain, code: code.rawValue, userInfo: nil)
        for (key, value) in error.userInfo {
            userInfo[key] = value
        }
        return cocoaError(fileURL.path, code: code)
    }
    
    internal func NotImplemented(_ fn: String = #function, file: StaticString = #file) {
        assert(false, "\(fn) method is not yet implemented. \(file)")
    }
}

/// Define methods to get preview and thumbnail for files or folders
public protocol ExtendedFileProvider: FileProviderBasic {
    /// Returns true if provider supports fetching properties of file like dimensions, duration, etc.
    /// Usually media or document files support these meta-infotmations.
    ///
    /// - Parameter path: path of file.
    /// - Returns: A `Bool` idicates path can have properties.
    func propertiesOfFileSupported(path: String) -> Bool
    
    /**
     Fetching properties of file like dimensions, duration, etc. It's variant depending on file type.
     Images, videos and audio files meta-information will be returned.
     
     - Note: `LocalFileInformationGenerator` variables can be set to change default behavior of
     thumbnail and properties generator of `LocalFileProvider`.
     
     - Parameters:
     - path: path of file.
     - completionHandler: a closure with result of preview image or error.
     - propertiesDictionary: A `Dictionary` of proprty keys and values.
     - keys: An `Array` contains ordering of keys.
     - error: Error returned by system.
     */
    @discardableResult
    func propertiesOfFile(path: String, completionHandler: @escaping (_ propertiesDictionary: [String: Any], _ keys: [String], _ error: Error?) -> Void) -> Progress?
    
    #if os(macOS) || os(iOS) || os(tvOS)
    /// Returuns true if thumbnail preview is supported by provider and file type accordingly.
    ///
    /// - Parameter path: path of file.
    /// - Returns: A `Bool` idicates path can have thumbnail.
    func thumbnailOfFileSupported(path: String) -> Bool
    
    /**
     Generates and returns a thumbnail preview of document asynchronously. The defualt dimension of returned image is different
     regarding provider type, usually 64x64 pixels.
     
     - Parameters:
       - path: path of file.
       - completionHandler: a closure with result of preview image or error.
       - image: `NSImage`/`UIImage` object contains preview.
       - error: `Error` returned by system.
    */
    @discardableResult
    func thumbnailOfFile(path: String, completionHandler: @escaping (_ image: ImageClass?, _ error: Error?) -> Void) -> Progress?
    
    /**
     Generates and returns a thumbnail preview of document asynchronously. The defualt dimension of returned image is different
     regarding provider type, usually 64x64 pixels. Default value used when `dimenstion` is `nil`.
     
     - Note: `LocalFileInformationGenerator` variables can be set to change default behavior of
             thumbnail and properties generator of `LocalFileProvider`.
     
     - Parameters:
       - path: path of file.
       - dimension: width and height of result preview image.
       - completionHandler: a closure with result of preview image or error.
       - image: `NSImage`/`UIImage` object contains preview.
       - error: `Error` returned by system.
     */
    @discardableResult
    func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping (_ image: ImageClass?, _ error: Error?) -> Void) -> Progress?
    #endif
}

#if os(macOS) || os(iOS) || os(tvOS)
extension ExtendedFileProvider {
    @discardableResult
    public func thumbnailOfFile(path: String, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) -> Progress? {
        return self.thumbnailOfFile(path: path, dimension: nil, completionHandler: completionHandler)
    }
    
    internal static func convertToImage(pdfData: Data?, page: Int = 1) -> ImageClass? {
        guard let pdfData = pdfData else { return nil }
        
        let cfPDFData: CFData = pdfData as CFData
        if let provider = CGDataProvider(data: cfPDFData), let reference = CGPDFDocument(provider), let pageRef = reference.page(at: page) {
            return self.convertToImage(pdfPage: pageRef)
        }
        return nil
    }
    
    internal static func convertToImage(pdfURL: URL, page: Int = 1) -> ImageClass? {
        // To accelerate, supporting only local file URL
        guard pdfURL.isFileURL else { return nil }
        
        if let reference = CGPDFDocument(pdfURL as CFURL), let pageRef = reference.page(at: page) {
            return self.convertToImage(pdfPage: pageRef)
        }
        return nil
    }
    
    private static func convertToImage(pdfPage: CGPDFPage) -> ImageClass? {
        let frame = pdfPage.getBoxRect(CGPDFBox.mediaBox)
        var size = frame.size
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        
        #if os(macOS)
            #if swift(>=3.2)
            let ppp = Int(NSScreen.main?.backingScaleFactor ?? 1) // fetch device is retina or not
            #else
            let ppp = Int(NSScreen.main()?.backingScaleFactor ?? 1) // fetch device is retina or not
            #endif
            
            size.width  *= CGFloat(ppp)
            size.height *= CGFloat(ppp)
            
            #if swift(>=3.2)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)
            #else
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: NSCalibratedRGBColorSpace,
                                           bytesPerRow: 0, bitsPerPixel: 0)
            #endif
            
            guard let context = NSGraphicsContext(bitmapImageRep: rep!) else {
                return nil
            }
            
            NSGraphicsContext.saveGraphicsState()
            #if swift(>=4.0)
            NSGraphicsContext.current = context
            #else
            NSGraphicsContext.setCurrent(context)
            #endif
            
            let transform = pdfPage.getDrawingTransform(CGPDFBox.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true)
            context.cgContext.concatenate(transform)
            
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: CGFloat(ppp), y: CGFloat(-ppp))
            context.cgContext.drawPDFPage(pdfPage)
            
            let resultingImage = NSImage(size: size)
            resultingImage.addRepresentation(rep!)
            return resultingImage
        #else
            let ppp = Int(UIScreen.main.scale) // fetch device is retina or not
            size.width  *= CGFloat(ppp)
            size.height *= CGFloat(ppp)
            UIGraphicsBeginImageContext(size)
            guard let context = UIGraphicsGetCurrentContext() else {
                return nil
            }
            context.saveGState()
            let transform = pdfPage.getDrawingTransform(CGPDFBox.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true)
            context.concatenate(transform)
            
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: CGFloat(ppp), y: CGFloat(-ppp))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect)
            context.drawPDFPage(pdfPage)
            
            context.restoreGState()
            let resultingImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resultingImage
        #endif
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
            var imageRect = NSRect(origin: .zero, size: image.size)
            let imageRef = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
            
            // Create NSImage from the CGImage using the new size
            return NSImage(cgImage: imageRef!, size: newSize)
        #else
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let newImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            return newImage
        #endif
    }
}
#endif

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
    
    /// present participle of action, like `Copying`.
    public var actionDescription: String {
        return description.trimmingCharacters(in: CharacterSet(charactersIn: "e")) + "ing"
    }
    
    /// Path of subjecting file.
    public var source: String {
        let reflect = Mirror(reflecting: self).children.first!.value
        let mirror = Mirror(reflecting: reflect)
        return reflect as? String ?? mirror.children.first?.value as! String
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
    
    init? (json: [String: AnyObject]) {
        guard let type = json["type"] as? String, let source = json["source"] as? String else {
            return nil
        }
        let dest = json["dest"] as? String
        switch type {
        case "Fetch":
            self = .fetch(path: source)
        case "Create":
            self = .create(path: source)
        case "Modify":
            self = .modify(path: source)
        case "Remove":
            self = .remove(path: source)
        case "Copy":
            guard let dest = dest else { return nil }
            self = .copy(source: source, destination: dest)
        case "Move":
            guard let dest = dest else { return nil }
            self = .move(source: source, destination: dest)
        case "Link":
            guard let dest = dest else { return nil }
            self = .link(link: source, target: dest)
        default:
            return nil
        }
    }
    
    internal var json: String? {
        var dictionary: [String: AnyObject] = ["type": self.description as NSString]
        dictionary["source"] = source as NSString?
        dictionary["dest"] = destination as NSString?
        return String(jsonDictionary: dictionary)
    }
}

/// Delegate methods for reporting provider's operation result and progress, when it's ready to update
/// user interface.
/// All methods are called in main thread to avoids UI bugs.
public protocol FileProviderDelegate: class {
    /// fileproviderSucceed(_:operation:) gives delegate a notification when an operation finished with success.
    /// This method is called in main thread to avoids UI bugs.
    func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType)
    /// fileproviderSucceed(_:operation:) gives delegate a notification when an operation finished with failure.
    /// This method is called in main thread to avoids UI bugs.
    func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType, error: Error)
    /// fileproviderSucceed(_:operation:) gives delegate a notification when an operation progess.
    /// Supported by some providers, especially remote ones.
    /// This method is called in main thread to avoids UI bugs.
    func fileproviderProgress(_ fileProvider: FileProviderOperations, operation: FileOperationType, progress: Float)
}

/// The `FileOperationDelegate` protocol defines methods for managing operations involving the copying, moving, linking, or removal of files and directories. When you use an `FileProvider` object to initiate a copy, move, link, or remove operation, the file provider asks its delegate whether the operation should begin at all and whether it should proceed when an error occurs.
public protocol FileOperationDelegate: class {
    
    /// fileProvider(_:shouldOperate:) gives the delegate an opportunity to filter the file operation. Returning true from this method will allow the copy to happen. Returning false from this method causes the item in question to be skipped. If the item skipped was a directory, no children of that directory will be subject of the operation, nor will the delegate be notified of those children.
    func fileProvider(_ fileProvider: FileProviderOperations, shouldDoOperation operation: FileOperationType) -> Bool
    
    /// fileProvider(_:shouldProceedAfterError:copyingItemAtPath:toPath:) gives the delegate an opportunity to recover from or continue copying after an error. If an error occurs, the error object will contain an ErrorType indicating the problem. The source path and destination paths are also provided. If this method returns true, the FileProvider instance will continue as if the error had not occurred. If this method returns false, the NSFileManager instance will stop copying, return false from copyItemAtPath:toPath:error: and the error will be provied there.
    func fileProvider(_ fileProvider: FileProviderOperations, shouldProceedAfterError error: Error, operation: FileOperationType) -> Bool
}
