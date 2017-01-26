
//
//  DropboxFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation
import CoreGraphics

// Because this class uses NSURLSession, it's necessary to disable App Transport Security
// in case of using this class with unencrypted HTTP connection.

open class DropboxFileProvider: FileProviderBasicRemote {
    open static let type: String = "DropBox"
    open let isPathRelative: Bool
    open let baseURL: URL?
    open var currentPath: String
    
    open let apiURL: URL
    open let contentURL: URL
    
    open var dispatch_queue: DispatchQueue {
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
    
    public init? (credential: URLCredential?, cache: URLCache? = nil) {
        self.baseURL = nil
        self.isPathRelative = true
        self.currentPath = ""
        self.useCache = false
        self.validatingCache = true
        self.cache = cache
        self.credential = credential
        
        self.apiURL = URL(string: "https://api.dropboxapi.com/2/")!
        self.contentURL = URL(string: "https://content.dropboxapi.com/2")!
        
        dispatch_queue = DispatchQueue(label: "FileProvider.\(DropboxFileProvider.type)", attributes: DispatchQueue.Attributes.concurrent)
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
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": correctPath(path)! as NSString]
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var dbError: FileProviderDropboxError?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                dbError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr), let file = self.mapToFileObject(json) {
                    fileObject = file
                }
            }
            completionHandler(fileObject, dbError ?? error)
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
            if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                totalSize = ((json["allocation"] as? NSDictionary)?["allocated"] as? NSNumber)?.int64Value ?? -1
                usedSize = (json["used"] as? NSNumber)?.int64Value ?? 0
            }
            completionHandler(totalSize, usedSize)
        }) 
        task.resume()
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
}

extension DropboxFileProvider: FileProviderOperations {
    
    
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
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var dbError: FileProviderDropboxError?
            if let response = response as? HTTPURLResponse, response.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: response.statusCode) {
                 dbError = FileProviderDropboxError(code: code, path: sourcePath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
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
        let url = URL(string: "files/download", relativeTo: contentURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let requestDictionary = ["path": path]
        let requestJson = dictionaryToJSON(requestDictionary as [String : AnyObject]) ?? ""
        request.setValue(requestJson, forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.downloadTask(with: request, completionHandler: { (cacheURL, response, error) in
            guard let cacheURL = cacheURL, let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (response as? HTTPURLResponse)?.statusCode ?? -1)
                let errorData : Data? = nil //Data(contentsOf:cacheURL) // TODO: Figure out how to get error response data for the error description
                let dbError : FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: errorData ?? Data(), encoding: .utf8)) : nil
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

extension DropboxFileProvider: FileProviderReadWrite {
    public func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let opType = FileOperationType.fetch(path: path)
        let url = URL(string: "files/download", relativeTo: contentURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let requestDictionary = ["path": correctPath(path)! as NSString]
        request.setValue(dictionaryToJSON(requestDictionary as [String : AnyObject]), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var dbError: FileProviderDropboxError?
            if let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode >= 300, let code = FileProviderHTTPErrorCode(rawValue: httpResponse.statusCode) {
                dbError = FileProviderDropboxError(code: code, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
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
        var foundFiles = [DropboxFileObject]()
        search(path, query: query, foundItem: { (file) in
            foundFiles.append(file)
            foundItemHandler?(file)
            }, completionHandler: { (error) in
                completionHandler(foundFiles, error)
        })
    }
    
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
    
    // TODO: Implement /copy_reference, /get_account & /get_current_account
}

extension DropboxFileProvider {
    open func temporaryLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: DropboxFileObject?, _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_temporary_link", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": correctPath(path)! as NSString]
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var dbError: FileProviderDropboxError?
            var link: URL?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                dbError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                    if let linkStr = json["link"] as? String {
                        link = URL(string: linkStr)
                    }
                    if let attribDic = json["metadata"] as? [String: AnyObject] {
                        fileObject = self.mapToFileObject(attribDic)
                    }
                }
            }
            completionHandler(link, fileObject, dbError ?? error)
        })
        task.resume()
    }
    
    open func copyItem(path: String, toRemoteURL destURL: URL, completionHandler: @escaping ((_ jobId: String?, _ attribute: DropboxFileObject?, _ error: Error?) -> Void)) {
        let url = URL(string: "files/save_url", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": correctPath(path)! as NSString, "url" : destURL.absoluteString as NSString]
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var dbError: FileProviderDropboxError?
            var jobId: String?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                dbError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                    jobId = json["async_job_id"] as? String
                    if let attribDic = json["metadata"] as? [String: AnyObject] {
                        fileObject = self.mapToFileObject(attribDic)
                    }
                }
            }
            completionHandler(jobId, fileObject, dbError ?? error)
        })
        task.resume()
    }
}

extension DropboxFileProvider: ExtendedFileProvider {
    public func thumbnailOfFileSupported(path: String) -> Bool {
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
    
    public func propertiesOfFileSupported(path: String) -> Bool {
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
    public func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
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
        var requestDictionary = ["path": path as NSString]
        requestDictionary["format"] = "jpeg" as NSString
        if let dimension = dimension {
            requestDictionary["size"] = "w\(Int(dimension.width))h\(Int(dimension.height))" as NSString
        }
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let r = response as? HTTPURLResponse, let result = r.allHeaderFields["Dropbox-API-Result"] as? String, let jsonResult = jsonToDictionary(result) {
                if jsonResult["error"] != nil {
                    completionHandler(nil, self.throwError(path, code: URLError.cannotDecodeRawData as FoundationErrorEnum))
                }
            }
            if let data = data {
                if DropboxFileProvider.dataIsPDF(data) {
                    image = DropboxFileProvider.convertToImage(pdfData: data)
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
    
    public func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": correctPath(path)! as NSString, "include_media_info": NSNumber(value: true)]
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var dbError: FileProviderDropboxError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                dbError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr), let properties = json["media_info"] as? [String: Any] {
                    (dic, keys) = self.mapMediaInfo(properties)
                }
            }
            completionHandler(dic, keys, dbError ?? error)
        })
        task.resume()
    }
}

extension DropboxFileProvider: FileProvider {
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = DropboxFileProvider(credential: self.credential, cache: self.cache)!
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
}
