
//
//  OneDriveFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation
import CoreGraphics

open class OneDriveFileProvider: FileProviderBasicRemote {
    open class var type: String { return "OneDrive" }
    open let isPathRelative: Bool
    open let baseURL: URL?
    /// OneDrive server url, equals with unwrapped `baseURL`
    open var serverURL: URL { return baseURL! }
    /// Drive name for user, default is `root`. Changing its value will effect on new operations.
    open var drive: String
    /// Generated storage url from server url and drive name
    open var driveURL: URL {
        return URL(string: "/drive/\(drive):/", relativeTo: baseURL)!
    }
    open var currentPath: String
    
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    
    open weak var delegate: FileProviderDelegate?
    open let credential: URLCredential?
    open private(set) var cache: URLCache?
    public var useCache: Bool
    public var validatingCache: Bool
   
    fileprivate var _session: URLSession?
    fileprivate var sessionDelegate: SessionDelegate?
    public var session: URLSession {
        if _session == nil {
            self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
            let queue = OperationQueue()
            //queue.underlyingQueue = dispatch_queue
            let config = URLSessionConfiguration.default
            config.urlCache = cache
            config.requestCachePolicy = .returnCacheDataElseLoad
            _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: queue)
        }
        return _session!
    }
    
    /**
     Initializer for Onedrive provider with given client ID and Token.
     These parameters must be retrieved via [Authentication for the OneDrive API](https://dev.onedrive.com/auth/readme.htm).
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token.
     The latter is easier to use and prefered. Also you can use [auth0/Lock](https://github.com/auth0/Lock.iOS-OSX) which provides graphical user interface.
     
     - Parameters:
       - credential: a `URLCredential` object with Client ID set as `user` and Token set as `password`.
       - serverURL: server url, Set it if you are trying to connect OneDrive Business server, otherwise leave it
         `nil` to connect to OneDrive Personal uses.
       - drive: drive name for user on server, default value is `root`.
       - cache: A URLCache to cache downloaded files and contents. If set to nil, URLCache.shared object will be used.
     */
    public init(credential: URLCredential?, serverURL: URL? = nil, drive: String = "root", cache: URLCache? = nil) {
        self.baseURL = (serverURL ?? URL(string: "https://api.onedrive.com/")!).appendingPathComponent("")
        self.drive = drive
        self.isPathRelative = true
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
    }
    
    deinit {
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
        let url = URL(string: escaped(path: path), relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            var fileObject: OneDriveFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr), let file = OneDriveFileObject(baseURL: self.baseURL, drive: self.drive, json: json) {
                    fileObject = file
                }
            }
            completionHandler(fileObject, serverError ?? error)
        }) 
        task.resume()
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        let url = URL(string: "/drive/root", relativeTo: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var totalSize: Int64 = -1
            var usedSize: Int64 = 0
            if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                totalSize = (json["total"] as? NSNumber)?.int64Value ?? -1
                usedSize = (json["used"] as? NSNumber)?.int64Value ?? 0
            }
            completionHandler(totalSize, usedSize)
        }) 
        task.resume()
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension OneDriveFileProvider: FileProviderOperations {
    
    
    public func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let path = (atPath as NSString).appendingPathComponent(folderName) + "/"
        return doOperation(.create(path: path), completionHandler: completionHandler)
    }
    
    public func create(file fileName: String, at path: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let filePath = (path as NSString).appendingPathComponent(fileName)
        return self.writeContents(path: filePath, contents: data ?? Data(), completionHandler: completionHandler)
    }
    
    public func moveItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    public func copyItem(path: String, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    public func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.remove(path: path), completionHandler: completionHandler)
    }
    
    fileprivate func doOperation(_ operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        guard let sourcePath = operation.source else { return nil }
        let destPath = operation.destination
        var request = URLRequest(url: URL(string: sourcePath, relativeTo: driveURL)!)
        switch operation {
        case .create:
            request.httpMethod = "CREATE"
        case .copy:
            request.httpMethod = "POST"
        case .move:
            request.httpMethod = "PATCH"
        case .remove:
            request.httpMethod = "DELETE"
        default: // modify, link, fetch
            return nil
        }
        
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        var requestDictionary = [String: AnyObject]()
        if let dest = correctPath(destPath) as NSString? {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requestDictionary["parentReference"] = ("/drive/\(drive):" + dest.deletingLastPathComponent) as NSString
            requestDictionary["name"] = dest.lastPathComponent as NSString
            request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        }
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            if let response = response as? HTTPURLResponse, response.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                 serverError = FileProviderOneDriveError(code: code, path: sourcePath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(serverError ?? error)
            self.delegateNotify(operation, error: serverError ?? error)
        })
        task.taskDescription = operation.json
        task.resume()
        return RemoteOperationHandle(operationType: operation, tasks: [task])
    }
    
    public func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        return upload_simple(toPath, localFile: localFile, overwrite: overwrite, operation: opType, completionHandler: completionHandler)
    }
    
    public func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.copy(source: path, destination: destURL.absoluteString)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        let url = URL(string: escaped(path: path) + ":/content", relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.downloadTask(with: request, completionHandler: { (cacheURL, response, error) in
            guard let cacheURL = cacheURL, let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (response as? HTTPURLResponse)?.statusCode ?? -1)
                let errorData : Data? = nil //Data(contentsOf:cacheURL) // TODO: Figure out how to get error response data for the error description
                let serverError : FileProviderOneDriveError? = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: errorData ?? Data(), encoding: .utf8)) : nil
                completionHandler?(serverError ?? error)
                return
            }
            do {
                try FileManager.default.moveItem(at: cacheURL, to: destURL)
                completionHandler?(nil)
            } catch let e {
                completionHandler?(e)
            }
        })
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
}

extension OneDriveFileProvider: FileProviderReadWrite {
    public func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        if length == 0 {
            return nil
        }
        
        let opType = FileOperationType.fetch(path: path)
        let url =  URL(string: escaped(path: path) + ":/content", relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            if let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: httpResponse.statusCode) {
                serverError = FileProviderOneDriveError(code: code, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            let filedata = serverError ?? error == nil ? data : nil
            completionHandler(filedata, serverError ?? error)
        })
        task.taskDescription = opType.json
        task.resume()
        return RemoteOperationHandle(operationType: opType, tasks: [task])
    }
    
    public func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let opType = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: opType) ?? true == true else {
            return nil
        }
        // FIXME: remove 150MB restriction
        return upload_simple(path, data: data, overwrite: overwrite, operation: opType, completionHandler: completionHandler)
    }
    
    public func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) {
        var foundFiles = [OneDriveFileObject]()
        search(path, query: query, foundItem: { (file) in
            foundFiles.append(file)
            foundItemHandler?(file)
            }, completionHandler: { (error) in
                completionHandler(foundFiles, error)
        })
    }
    
    fileprivate func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is two ways to monitor folders changing in OneDrive. Either using webooks
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
    
    /**
     Genrates a public url to a file to be shared with other users and can be downloaded without authentication.
     
     - Parameters:
       - to: path of file, including file/directory name.
       - completionHandler: a block with result of directory entries or error.
         `link`: a url returned by OneDrive to share.
         `attribute`: `nil` for OneDrive.
         `expiration`: `nil` for OneDrive, as it doesn't expires.
         `error`: Error returned by OneDrive.
     */
    open func publicLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: OneDriveFileObject?, _ expiration: Date?, _ error: Error?) -> Void)) {
        let url =  URL(string: escaped(path: path) + ":/action.createLink", relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let requestDictionary: [String: AnyObject] = ["type": "view" as NSString]
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            var link: URL?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                    if let linkDic = json["link"] as? NSDictionary, let linkStr = linkDic["webUrl"] as? String {
                        link = URL(string: linkStr)
                    }
                }
            }
            
            completionHandler(link, nil, nil, serverError ?? error)
        })
        task.resume()
    }
}


extension OneDriveFileProvider: ExtendedFileProvider {
    public func thumbnailOfFileSupported(path: String) -> Bool {
        return true
    }
    
    public func propertiesOfFileSupported(path: String) -> Bool {
        let fileExt = (path as NSString).pathExtension.lowercased()
        switch fileExt {
        case "jpg", "jpeg", "bmp", "gif", "png", "tif", "tiff":
            return true
        case "mp3", "aac", "m4a", "wma":
            return true
        case "mp4", "mpg", "3gp", "mov", "avi", "wmv":
            return true
        default:
            return false
        }
    }
    
    public func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
        let url: URL
        if let dimension = dimension {
            url = URL(string: escaped(path: path) + ":/thumbnails/0/=c\(dimension.width)x\(dimension.height)/content", relativeTo: driveURL)!
        } else {
            url = URL(string: escaped(path: path) + ":/thumbnails/0/small/content", relativeTo: driveURL)!
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                let responseError = FileProviderOneDriveError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
                completionHandler(nil, responseError)
                return
            }
            if let data = data {
                image = ImageClass(data: data)
            }
            completionHandler(image, error)
        })
        task.resume()
    }
    
    public func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) {
        let url = URL(string: escaped(path: path), relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                    (dic, keys) = self.mapMediaInfo(json)
                }
            }
            completionHandler(dic, keys, serverError ?? error)
        })
        task.resume()
    }
}

extension OneDriveFileProvider: FileProvider {
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = OneDriveFileProvider(credential: self.credential, serverURL: self.baseURL, drive: self.drive, cache: self.cache)
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
}
