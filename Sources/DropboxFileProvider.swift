
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

open class DropboxFileProvider: NSObject,  FileProviderBasic {
    open static let type: String = "WebDAV"
    open let isPathRelative: Bool = true
    open let baseURL: URL?
    open var currentPath: String = ""
    open var dispatch_queue: DispatchQueue {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    open weak var delegate: FileProviderDelegate?
    open let credential: URLCredential?
    
    fileprivate var _session: URLSession?
    fileprivate var sessionDelegate: SessionDelegate?
    internal var session: URLSession {
        if _session == nil {
            self.sessionDelegate = SessionDelegate(fileProvider: self, credential: credential)
            let queue = OperationQueue()
            //queue.underlyingQueue = dispatch_queue
            _session = URLSession(configuration: URLSessionConfiguration.default, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: queue)
        }
        return _session!
    }
    
    public init? (credential: URLCredential?) {
        self.baseURL = nil
        dispatch_queue = DispatchQueue(label: "FileProvider.\(DropboxFileProvider.type)", attributes: DispatchQueue.Attributes.concurrent)
        //let url = baseURL.uw_absoluteString
        self.credential = credential
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
        let url = URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": correctPath(path)! as NSString]
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let response = response as? HTTPURLResponse {
                defer {
                    self.delegateNotify(.create(path: path), error: error)
                }
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr), let file = self.mapToFileObject(json) {
                    completionHandler(file, dbError)
                    return
                }
                completionHandler(nil, dbError)
                return
            }
            completionHandler(nil, error)
        }) 
        task.resume()
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        let url = URL(string: "https://api.dropboxapi.com/2/users/get_space_usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let data = data, let jsonStr = String(data: data, encoding: .utf8), let json = jsonToDictionary(jsonStr) {
                let totalSize = ((json["allocation"] as? NSDictionary)?["allocated"] as? NSNumber)?.int64Value ?? -1
                let usedSize = (json["used"] as? NSNumber)?.int64Value ?? 0
                completionHandler(totalSize, usedSize)
                return
            }
            completionHandler(-1, 0)
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
    
    public func create(file fileAttribs: FileObject, at path: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return self.writeContents(path: path, contents: data ?? Data(), completionHandler: completionHandler)
    }
    
    public func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        return doOperation(.move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    public func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
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
        var path: String?, fromPath: String?, toPath: String?
        switch operation {
        case .create(path: let p):
            url = "https://api.dropboxapi.com/2/files/create_folder"
            path = p
        case .copy(source: let fp, destination: let tp):
            url = "https://api.dropboxapi.com/2/files/copy"
            fromPath = fp
            toPath = tp
        case .move(source: let fp, destination: let tp):
            url = "https://api.dropboxapi.com/2/files/move"
            fromPath = fp
            toPath = tp
        case .modify(path: let p):
            return nil
        case .remove(path: let p):
            url = "https://api.dropboxapi.com/2/files/delete"
            path = p
        case .link(link: _, target: _):
            return nil
        }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestDictionary = [String: AnyObject]()
        requestDictionary["path"] = correctPath(path) as NSString?
        requestDictionary["from_path"] = correctPath(fromPath) as NSString?
        requestDictionary["to_path"] = correctPath(toPath) as NSString?
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path ?? fromPath ?? "", errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                defer {
                    self.delegateNotify(operation, error: error ?? dbError)
                }
                /*if let data = data, let jsonStr = String(data: data, encoding: NSUTF8StringEncoding) {
                 let json = self.jsonToDictionary(jsonStr)
                 }*/
                completionHandler?(dbError)
                return
            }
            completionHandler?(error)
        }) 
        task.resume()
        return RemoteOperationHandle(tasks: [task])
    }
    
    public func copyItem(localFile: URL, to toPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: .copy(source: localFile.absoluteString, destination: toPath)) ?? true == true else {
            return nil
        }
        guard let data = try? Data(contentsOf: localFile) else {
            let error = throwError(localFile.absoluteString, code: URLError.fileDoesNotExist as FoundationErrorEnum)
            completionHandler?(error)
            return nil
        }
        return upload_simple(toPath, data: data, overwrite: true, operation: .copy(source: localFile.absoluteString, destination: toPath), completionHandler: completionHandler)
    }
    
    public func copyItem(path: String, toLocalURL destURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: .copy(source: path, destination: destURL.absoluteString)) ?? true == true else {
            return nil
        }
        let url = URL(string: "https://content.dropboxapi.com/2/files/download")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": path as NSString]
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.downloadTask(with: request, completionHandler: { (cacheURL, response, error) in
            guard let cacheURL = cacheURL, let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (response as? HTTPURLResponse)?.statusCode ?? -1)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: nil) : nil
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
        task.taskDescription = dictionaryToJSON(["type": "Copy" as NSString, "source": path as NSString, "dest": destURL.absoluteString as NSString])
        task.resume()
        return RemoteOperationHandle(tasks: [task])
    }
}

extension DropboxFileProvider: FileProviderReadWrite {
    public func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        return self.contents(path: path, offset: 0, length: -1, completionHandler: completionHandler)
    }
    
    public func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        let url = URL(string: "https://content.dropboxapi.com/2/files/download")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let requestDictionary = ["path": path]
        request.setValue(dictionaryToJSON(requestDictionary as [String : AnyObject]), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.dataTask(with: request, completionHandler: { (datam, response, error) in
            guard let data = datam, let httpResponse = response as? HTTPURLResponse , httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (response as? HTTPURLResponse)?.statusCode ?? -1)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: datam ?? Data(), encoding: .utf8)) : nil
                completionHandler(nil, dbError ?? error)
                return
            }
            completionHandler(data, error)
        })
        task.resume()
        return RemoteOperationHandle(tasks: [task])
    }
    
    public func writeContents(path: String, contents data: Data, atomically: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: .modify(path: path)) ?? true == true else {
            return nil
        }
        // FIXME: remove 150MB restriction
        return upload_simple(path, data: data, overwrite: true, operation: .modify(path: path), completionHandler: completionHandler)
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
    
    // TODO: Implement /copy_reference, /get_temporary_link, /save_url, /get_account & /get_current_account
}

extension DropboxFileProvider: ExtendedFileProvider {
    public func thumbnailOfFileSupported(path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff":
            return true
        /*case "doc", "docx", "docm", "xls", "xlsx", "xlsm":
            return true
        case  "ppt", "pps", "ppsx", "ppsm", "pptx", "pptm":
            return true
        case "rtf":
            return true*/
        default:
            return false
        }
    }
    
    public func propertiesOfFileSupported(path: String) -> Bool {
        return false
    }
    
    public func thumbnailOfFile(path: String, dimension: CGSize, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
        let url: URL
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff":
            url = URL(string: "https://content.dropboxapi.com/2/files/get_thumbnail")!
        /*case "doc", "docx", "docm", "xls", "xlsx", "xlsm":
            fallthrough
        case  "ppt", "pps", "ppsx", "ppsm", "pptx", "pptm":
            fallthrough
        case "rtf":
            url = NSURL(string: "https://content.dropboxapi.com/2/files/get_preview")!*/
        default:
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        var requestDictionary = ["path": path as NSString]
        requestDictionary["format"] = "jpeg" as NSString
        requestDictionary["size"] = "w\(Int(dimension.width))h\(Int(dimension.height))" as NSString
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let r = response as? HTTPURLResponse, let result = r.allHeaderFields["Dropbox-API-Result"] as? String, let jsonResult = jsonToDictionary(result) {
                if jsonResult["error"] != nil {
                    completionHandler(nil, self.throwError(path, code: URLError.cannotDecodeRawData as FoundationErrorEnum))
                }
            }
            if let data = data {
                image = ImageClass(data: data)
            }
            completionHandler(image, error)
        }) 
    }
    
    public func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) {
        NotImplemented()
    }
}

extension DropboxFileProvider: FileProvider {}
