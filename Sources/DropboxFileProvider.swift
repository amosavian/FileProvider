
//
//  DropboxFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation
import CoreGraphics

/**
 Allows accessing to Dropbox stored files. This provider doesn't cache or save files internally, however you can
 set `useCache` and `cache` properties to use Foundation `NSURLCache` system.
 
 - Note: Uploading files and data are limited to 150MB, for now.
 */
open class DropboxFileProvider: FileProviderBasicRemote {
    open class var type: String { return "DropBox" }
    open let baseURL: URL?
    open var currentPath: String
    
    /// Dropbox RPC API URL, which is equal with [https://api.dropboxapi.com/2/](https://api.dropboxapi.com/2/)
    open let apiURL: URL
    /// Dropbox contents download/upload API URL, which is equal with [https://content.dropboxapi.com/2/](https://content.dropboxapi.com/2/)
    open let contentURL: URL
    
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    
    open weak var delegate: FileProviderDelegate?
    open var credential: URLCredential? {
        didSet {
            sessionDelegate?.credential = self.credential
        }
    }
    open private(set) var cache: URLCache?
    public var useCache: Bool
    public var validatingCache: Bool
   
    fileprivate var _session: URLSession?
    fileprivate var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        get {
            if _session == nil {
                self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
                let config = URLSessionConfiguration.default
                config.urlCache = cache
                config.requestCachePolicy = .returnCacheDataElseLoad
                _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: self.operation_queue)
                _session!.sessionDescription = UUID().uuidString
                initEmptySessionHandler(_session!.sessionDescription!)
            }
            return _session!
        }
        
        set {
            assert(newValue.delegate is SessionDelegate, "session instances should have a SessionDelegate instance as delegate.")
            _session = newValue
            if session.sessionDescription?.isEmpty ?? true {
                _session?.sessionDescription = UUID().uuidString
            }
            self.sessionDelegate = newValue.delegate as? SessionDelegate
            initEmptySessionHandler(_session!.sessionDescription!)
        }
    }
    
    internal var completionHandlersForTasks = [Int: SimpleCompletionHandler]()
    internal var downloadCompletionHandlersForTasks = [Int: (URL) -> Void]()
    internal var dataCompletionHandlersForTasks = [Int: (Data) -> Void]()
    
    fileprivate var _longpollSession: URLSession?
    internal var longpollSession: URLSession {
        if _longpollSession == nil {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600
            _longpollSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        }
        return _longpollSession!
    }
    
    /**
     Initializer for Dropbox provider with given client ID and Token.
     These parameters must be retrieved via [OAuth2 API of Dropbox](https://www.dropbox.com/developers/reference/oauth-guide).
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. 
     The latter is easier to use and prefered. Also you can use [auth0/Lock](https://github.com/auth0/Lock.iOS-OSX) which provides graphical user interface.
     
     - Parameter credential: a `URLCredential` object with Client ID set as `user` and Token set as `password`.
     - Parameter cache: A URLCache to cache downloaded files and contents.
    */
    public init(credential: URLCredential?, cache: URLCache? = nil) {
        self.baseURL = nil
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        
        self.apiURL = URL(string: "https://api.dropboxapi.com/2/")!
        self.contentURL = URL(string: "https://content.dropboxapi.com/2/")!
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        self.init(credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.currentPath     = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(self.credential, forKey: "credential")
        aCoder.encode(self.currentPath, forKey: "currentPath")
        aCoder.encode(self.useCache, forKey: "useCache")
        aCoder.encode(self.validatingCache, forKey: "validatingCache")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = DropboxFileProvider(credential: self.credential, cache: self.cache)
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    deinit {
        if let sessionuuid = _session?.sessionDescription {
            removeSessionHandler(for: sessionuuid)
        }
        
        if fileProviderCancelTasksOnInvalidating {
            _session?.invalidateAndCancel()
        } else {
            _session?.finishTasksAndInvalidate()
        }
        
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        list(path) { (contents, cursor, error) in
            completionHandler(contents, error)
        }
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON(), let file = DropboxFileObject(json: json) {
                    fileObject = file
                }
            }
            completionHandler(fileObject, serverError ?? error)
        }) 
        task.resume()
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        let url = URL(string: "users/get_space_usage", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var totalSize: Int64 = -1
            var usedSize: Int64 = 0
            if let json = data?.deserializeJSON() {
                totalSize = ((json["allocation"] as? NSDictionary)?["allocated"] as? NSNumber)?.int64Value ?? -1
                usedSize = (json["used"] as? NSNumber)?.int64Value ?? 0
            }
            completionHandler(totalSize, usedSize)
        }) 
        task.resume()
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        var foundFiles = [DropboxFileObject]()
        if let queryStr = query.findValue(forKey: "name", operator: .beginsWith) as? String {
            // Dropbox only support searching for file names begin with query in non-enterprise accounts.
            // We will use it if there is a `name BEGINSWITH[c] "query"` in predicate, then filter to form final result.
            search(path, query: queryStr, foundItem: { (file) in
                if query.evaluate(with: file.mapPredicate()) {
                    foundFiles.append(file)
                    foundItemHandler?(file)
                }
            }, completionHandler: { (error) in
                completionHandler(foundFiles, error)
            })
        } else {
            // Dropbox doesn't support searching attributes natively. The workaround is to fallback to listing all files
            // and filter it locally. It may have a network burden in case there is many files in Dropbox, so please use it concisely.
            list(path, recursive: true, progressHandler: { (files, _, error) in
                for file in files where query.evaluate(with: file.mapPredicate()) {
                    foundItemHandler?(file)
                }
            }, completionHandler: { (files, _, error) in
                let predicatedFiles = files.filter { query.evaluate(with: $0.mapPredicate()) }
                completionHandler(predicatedFiles, error)
            })
        }
    }
    
    open func isReachable(completionHandler: @escaping (Bool) -> Void) {
        self.storageProperties { total, _ in
            completionHandler(total > 0)
        }
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension DropboxFileProvider: FileProviderOperations {
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let path = (atPath as NSString).appendingPathComponent(folderName) + "/"
        return doOperation(.create(path: path), completionHandler: completionHandler)
    }
    
    open func moveItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.remove(path: path), completionHandler: completionHandler)
    }
    
    fileprivate func doOperation(_ operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        let url: String
        guard let sourcePath = operation.source else { return nil }
        let destPath = operation.destination
        switch operation {
        case .create:
            url = "files/create_folder"
        case .copy:
            url = "files/copy"
        case .move:
            url = "files/move"
        case .remove:
            url = "files/delete"
        default: // modify, link, fetch
            return nil
        }
        var request = URLRequest(url: URL(string: url, relativeTo: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestDictionary = [String: AnyObject]()
        if let dest = correctPath(destPath) as NSString? {
            requestDictionary["from_path"] = correctPath(sourcePath) as NSString?
            requestDictionary["to_path"] = dest
        } else {
            requestDictionary["path"] = correctPath(sourcePath) as NSString?
        }
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            if let response = response as? HTTPURLResponse, response.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                 serverError = FileProviderDropboxError(code: code, path: sourcePath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(serverError ?? error)
            self.delegateNotify(operation, error: serverError ?? error)
        })
        task.taskDescription = operation.json
        task.resume()
        return RemoteOperationHandle(operationType: operation, tasks: [task])
    }
    
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return upload_simple(toPath, localFile: localFile, overwrite: overwrite, operation: opType, completionHandler: completionHandler)
    }
    
    open func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = URL(string: "files/download", relativeTo: contentURL)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let requestDictionary: [String: AnyObject] = ["path": path as NSString]
        let requestJson = String(jsonDictionary: requestDictionary) ?? ""
        request.setValue(requestJson, forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.downloadTask(with: request)
        completionHandlersForTasks[task.taskIdentifier] = completionHandler
        downloadCompletionHandlersForTasks[task.taskIdentifier] = { tempURL in
            guard let httpResponse = task.response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (task.response as? HTTPURLResponse)?.statusCode ?? -1)
                let errorData : Data? = nil //Data(contentsOf:cacheURL) // TODO: Figure out how to get error response data for the error description
                let serverError : FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: errorData ?? Data(), encoding: .utf8)) : nil
                completionHandler?(serverError)
                return
            }
            do {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                completionHandler?(nil)
            } catch let e {
                completionHandler?(e)
            }
        }
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
}

extension DropboxFileProvider: FileProviderReadWrite {
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        if length == 0 || offset < 0 {
            dispatch_queue.async {
                completionHandler(Data(), nil)
            }
            return nil
        }
        
        let opType = FileOperationType.fetch(path: path)
        let url = URL(string: "files/download", relativeTo: contentURL)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString]
        request.setValue(String(jsonDictionary: requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.downloadTask(with: request)
        completionHandlersForTasks[task.taskIdentifier] = { error in
            completionHandler(nil, error)
        }
        downloadCompletionHandlersForTasks[task.taskIdentifier] = { tempURL in
            guard let httpResponse = task.response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (task.response as? HTTPURLResponse)?.statusCode ?? -1)
                let errorData : Data? = nil //Data(contentsOf:cacheURL) // TODO: Figure out how to get error response data for the error description
                let serverError : FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: errorData ?? Data(), encoding: .utf8)) : nil
                completionHandler(nil, serverError)
                return
            }
            do {
                let data = try Data(contentsOf: tempURL)
                completionHandler(data, nil)
            } catch let e {
                completionHandler(nil, e)
            }
        }
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    public func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        // FIXME: remove 150MB restriction
        return upload_simple(path, data: data ?? Data(), overwrite: overwrite, operation: opType, completionHandler: completionHandler)
    }
    
    /*
    fileprivate func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is two ways to monitor folders changing in Dropbox. Either using webooks
         * which means you have to implement a server to translate it to push notifications
         * or using apiv2 list_folder/longpoll method. The second one is implemeted here.
         * Tough webhooks are much more efficient, longpoll is much simpler to implement!
         * You can implemnt your own webhook service and replace this method accordingly.
         */
        NotImplemented()
    }
    fileprivate func unregisterNotifcation(path: String) {
        NotImplemented()
    }
    */
    // TODO: Implement /get_account & /get_current_account
}

extension DropboxFileProvider {
    /**
     Genrates a public url to a file to be shared with other users and can be downloaded without authentication.
     
     - Important: URL will be available for a limitied time (4 hours according to Dropbox documentation).
     
     - Parameters:
       - to: path of file, including file/directory name.
       - completionHandler: a closure with result of directory entries or error.
         - `link`: a url returned by Dropbox to share.
         - `attribute`: a `FileObject` containing the attributes of the item.
         - `expiration`: a `Date` object, determines when the public url will expires.
         - `error`: Error returned by Dropbox.
    */
    open func publicLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: DropboxFileObject?, _ expiration: Date?, _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_temporary_link", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            var link: URL?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON() {
                    if let linkStr = json["link"] as? String {
                        link = URL(string: linkStr)
                    }
                    if let attribDic = json["metadata"] as? [String: AnyObject] {
                        fileObject = DropboxFileObject(json: attribDic)
                    }
                }
            }
            
            let expiration: Date? = link != nil ? Date(timeIntervalSinceNow: 4 * 60 * 60) : nil
            completionHandler(link, fileObject, expiration, serverError ?? error)
        })
        task.resume()
    }
    
    /**
     Downloads a file from remote url to designated path asynchronously.
     
     - Parameters:
       - remoteURL: a valid remote url to file.
       - to: Destination path of file, including file/directory name.
       - completionHandler: a closure with result of directory entries or error.
         - `jobId`: Job ID returned by Dropbox to monitor the copy/download progress.
         - `attribute`: A `FileObject` containing the attributes of the item.
         - `error`: Error returned by Dropbox.
     */
    open func copyItem(remoteURL: URL, to toPath: String, completionHandler: @escaping ((_ jobId: String?, _ attribute: DropboxFileObject?, _ error: Error?) -> Void)) {
        if remoteURL.isFileURL {
            completionHandler(nil, nil, self.throwError(remoteURL.path, code: URLError.badURL))
            return
        }
        let url = URL(string: "files/save_url", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary: [String: AnyObject] = ["path": correctPath(toPath)! as NSString, "url" : remoteURL.absoluteString as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            var jobId: String?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderDropboxError(code: code!, path: toPath, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON() {
                    jobId = json["async_job_id"] as? String
                    if let attribDic = json["metadata"] as? [String: AnyObject] {
                        fileObject = DropboxFileObject(json: attribDic)
                    }
                }
            }
            completionHandler(jobId, fileObject, serverError ?? error)
        })
        task.resume()
    }
    
    /**
     Copys a file from another user Dropbox storage to designated path asynchronously.
     
     - Parameters:
       - reference: a valid reference string from another user via `copy_reference/get` REST method.
       - to: Destination path of file, including file/directory name.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     */
    open func copyItem(reference: String, to toPath: String, completionHandler: SimpleCompletionHandler) {
        let url = URL(string: "files/copy_reference/save", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary: [String: AnyObject] = ["path": correctPath(toPath)! as NSString, "copy_reference" : reference as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderDropboxError(code: code!, path: toPath, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
            }
            completionHandler?(serverError ?? error)
        })
        task.resume()
    }
}

extension DropboxFileProvider: ExtendedFileProvider {
    open func thumbnailOfFileSupported(path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff":
            return true
        case "doc", "docx", "docm", "xls", "xlsx", "xlsm":
            return true
        case  "ppt", "pps", "ppsx", "ppsm", "pptx", "pptm":
            return true
        case "rtf":
            return true
        default:
            return false
        }
    }
    
    open func propertiesOfFileSupported(path: String) -> Bool {
        let fileExt = (path as NSString).pathExtension.lowercased()
        switch fileExt {
        case "jpg", "jpeg", "bmp", "gif", "png", "tif", "tiff":
            return true
        /*case "mp3", "aac", "m4a":
            return true*/
        case "mp4", "mpg", "3gp", "mov", "avi":
            return true
        default:
            return false
        }
    }
        
    /// Default value for dimension is 64x64, according to Dropbox documentation
    open func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
        let url: URL
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff":
            url = URL(string: "files/get_thumbnail", relativeTo: contentURL)!
        case "doc", "docx", "docm", "xls", "xlsx", "xlsm":
            fallthrough
        case  "ppt", "pps", "ppsx", "ppsm", "pptx", "pptm":
            fallthrough
        case "rtf":
            url = URL(string: "files/get_preview", relativeTo: contentURL)!
        default:
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        var requestDictionary: [String: AnyObject] = ["path": path as NSString]
        requestDictionary["format"] = "jpeg" as NSString
        if let dimension = dimension {
            requestDictionary["size"] = "w\(Int(dimension.width))h\(Int(dimension.height))" as NSString
        }
        request.setValue(String(jsonDictionary: requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let r = response as? HTTPURLResponse, let result = r.allHeaderFields["Dropbox-API-Result"] as? String, let jsonResult = result.deserializeJSON() {
                if jsonResult["error"] != nil {
                    completionHandler(nil, self.throwError(path, code: URLError.cannotDecodeRawData as FoundationErrorEnum))
                }
            }
            if let data = data {
                if data.isPDF, let pageImage = DropboxFileProvider.convertToImage(pdfData: data) {
                    image = pageImage
                } else if let contentType = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, contentType.contains("text/html") {
                     // TODO: Implement converting html returned type of get_preview to image
                } else {
                    image = ImageClass(data: data)
                }
            }
            completionHandler(image, error)
        })
        task.resume()
    }
    
    open func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString, "include_media_info": NSNumber(value: true)]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON(), let properties = json["media_info"] as? [String: Any] {
                    (dic, keys) = self.mapMediaInfo(properties)
                }
            }
            completionHandler(dic, keys, serverError ?? error)
        })
        task.resume()
    }
}

extension DropboxFileProvider: FileProvider { }
