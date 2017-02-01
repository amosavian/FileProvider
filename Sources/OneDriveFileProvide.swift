
//
//  OneDriveFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation
import CoreGraphics

// Because this class uses NSURLSession, it's necessary to disable App Transport Security
// in case of using this class with unencrypted HTTP connection.

open class OneDriveFileProvider: FileProviderBasicRemote {
    open static let type: String = "OneDrive"
    open let isPathRelative: Bool
    open let baseURL: URL?
    open var serverURL: URL { return baseURL! }
    open var drive: String
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
    
    public init? (credential: URLCredential?, serverURL: URL? = nil, drive: String = "root", cache: URLCache? = nil) {
        self.baseURL = (serverURL ?? URL(string: "https://api.onedrive.com/")!).appendingPathComponent("")
        self.drive = drive
        self.isPathRelative = true
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
    }
    
    deinit {
        _session?.invalidateAndCancel()
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
            var dbError: FileProviderOneDriveError?
            var fileObject: OneDriveFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                dbError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr), let file = OneDriveFileObject(baseURL: self.baseURL, drive: self.drive, json: json) {
                    fileObject = file
                }
            }
            completionHandler(fileObject, dbError ?? error)
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
            var dbError: FileProviderOneDriveError?
            if let response = response as? HTTPURLResponse, response.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                 dbError = FileProviderOneDriveError(code: code, path: sourcePath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(dbError ?? error)
            self.delegateNotify(operation, error: dbError ?? error)
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
                let dbError : FileProviderOneDriveError? = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: errorData ?? Data(), encoding: .utf8)) : nil
                completionHandler?(dbError ?? error)
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
            var dbError: FileProviderOneDriveError?
            if let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: httpResponse.statusCode) {
                dbError = FileProviderOneDriveError(code: code, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            let filedata = dbError ?? error == nil ? data : nil
            completionHandler(filedata, dbError ?? error)
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
    
    // TODO: Implement /copy_reference, /get_account & /get_current_account
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
            var dbError: FileProviderOneDriveError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                dbError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                    (dic, keys) = self.mapMediaInfo(json)
                }
            }
            completionHandler(dic, keys, dbError ?? error)
        })
        task.resume()
    }
}

extension OneDriveFileProvider: FileProvider {
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = OneDriveFileProvider(credential: self.credential, serverURL: self.baseURL, drive: self.drive, cache: self.cache)!
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
}
