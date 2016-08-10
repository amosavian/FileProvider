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

public class DropboxFileProvider: NSObject,  FileProviderBasic {
    public let type: String = "WebDAV"
    public let isPathRelative: Bool = true
    public let baseURL: NSURL?
    public var currentPath: String = ""
    public var dispatch_queue: dispatch_queue_t {
        willSet {
            assert(_session == nil, "It's not effective to change dispatch_queue property after session is initialized.")
        }
    }
    public weak var delegate: FileProviderDelegate?
    public let credential: NSURLCredential?
    
    private var _session: NSURLSession?
    internal var session: NSURLSession {
        if _session == nil {
            let queue = NSOperationQueue()
            //queue.underlyingQueue = dispatch_queue
            _session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration(), delegate: self, delegateQueue: queue)
        }
        return _session!
    }
    
    public init? (credential: NSURLCredential?) {
        self.baseURL = nil
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        //let url = baseURL.uw_absoluteString
        self.credential = credential
    }
    
    deinit {
        _session?.invalidateAndCancel()
    }
    
    public func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObject], error: ErrorType?) -> Void)) {
        list(path) { (contents, cursor, error) in
            completionHandler(contents: contents, error: error)
        }
    }
    
    public func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObject?, error: ErrorType?) -> Void)) {
        let url = NSURL(string: "https://api.dropboxapi.com/2/files/get_metadata")!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": correctPath(path)!]
        request.HTTPBody = dictionaryToJSON(requestDictionary)?.dataUsingEncoding(NSUTF8StringEncoding)
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse {
                defer {
                    self.delegateNotify(FileOperation.Create(path: path), error: error)
                }
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? NSData(), encoding: NSUTF8StringEncoding)) : nil
                if let data = data, let jsonStr = String(data: data, encoding: NSUTF8StringEncoding), let json = self.jsonToDictionary(jsonStr), let file = self.mapToFileObject(json) {
                    completionHandler(attributes: file, error: dbError)
                    return
                }
                completionHandler(attributes: nil, error: dbError)
                return
            }
            completionHandler(attributes: nil, error: error)
        }
        task.resume()
    }
    
    public func storageProperties(completionHandler: ((total: Int64, used: Int64) -> Void)) {
        let url = NSURL(string: "https://api.dropboxapi.com/2/users/get_space_usage")!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            if let data = data, let jsonStr = String(data: data, encoding: NSUTF8StringEncoding), let json = self.jsonToDictionary(jsonStr) {
                let totalSize = ((json["allocation"] as? NSDictionary)?["allocated"] as? NSNumber)?.longLongValue ?? -1
                let usedSize = (json["used"] as? NSNumber)?.longLongValue ?? 0
                completionHandler(total: totalSize, used: usedSize)
                return
            }
            completionHandler(total: -1, used: 0)
        }
        task.resume()
    }
    
    public weak var fileOperationDelegate: FileOperationDelegate?
}

extension DropboxFileProvider: FileProviderOperations {
    public func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        let path = (atPath as NSString).stringByAppendingPathComponent(folderName) + "/"
        doOperation(.Create(path: path), completionHandler: completionHandler)
    }
    
    public func createFile(fileAttribs: FileObject, atPath path: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
        self.writeContentsAtPath(path, contents: data ?? NSData(), completionHandler: completionHandler)
    }
    
    public func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        doOperation(.Move(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    public func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        doOperation(.Copy(source: path, destination: toPath), completionHandler: completionHandler)
    }
    
    public func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        doOperation(.Remove(path: path), completionHandler: completionHandler)
    }
    
    private func doOperation(operation: FileOperation, completionHandler: SimpleCompletionHandler) {
        let url: String
        var path: String?, fromPath: String?, toPath: String?
        switch operation {
        case .Create(path: let p):
            url = "https://api.dropboxapi.com/2/files/create_folder"
            path = p
        case .Copy(source: let fp, destination: let tp):
            url = "https://api.dropboxapi.com/2/files/copy"
            fromPath = fp
            toPath = tp
        case .Move(source: let fp, destination: let tp):
            url = "https://api.dropboxapi.com/2/files/move"
            fromPath = fp
            toPath = tp
        case .Modify(path: let p):
            return
        case .Remove(path: let p):
            url = "https://api.dropboxapi.com/2/files/delete"
            path = p
        case .Link(link: _, target: _):
            return
        }
        let request = NSMutableURLRequest(URL: NSURL(string: url)!)
        request.HTTPMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestDictionary = [String: AnyObject]()
        requestDictionary["path"] = correctPath(path)
        requestDictionary["from_path"] = correctPath(fromPath)
        requestDictionary["to_path"] = correctPath(toPath)
        request.HTTPBody = dictionaryToJSON(requestDictionary)?.dataUsingEncoding(NSUTF8StringEncoding)
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            if let response = response as? NSHTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path ?? fromPath ?? "", errorDescription: String(data: data ?? NSData(), encoding: NSUTF8StringEncoding)) : nil
                defer {
                    self.delegateNotify(operation, error: error ?? dbError)
                }
                /*if let data = data, let jsonStr = String(data: data, encoding: NSUTF8StringEncoding) {
                 let json = self.jsonToDictionary(jsonStr)
                 }*/
                completionHandler?(error: dbError)
                return
            }
            completionHandler?(error: error)
        }
        task.resume()
    }
    
    public func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        guard let data = NSData(contentsOfURL: localFile) else {
            let error = throwError(localFile.uw_absoluteString, code: NSURLError.FileDoesNotExist)
            completionHandler?(error: error)
            return
        }
        upload_simple(toPath, data: data, overwrite: true, operation: .Copy(source: localFile.absoluteString, destination: toPath), completionHandler: completionHandler)
    }
    
    public func copyPathToLocalFile(path: String, toLocalURL destURL: NSURL, completionHandler: SimpleCompletionHandler) {
        let url = NSURL(string: "https://content.dropboxapi.com/2/files/download")!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestDictionary = ["path": path]
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.downloadTaskWithRequest(request, completionHandler: { (cacheURL, response, error) in
            guard let cacheURL = cacheURL, let httpResponse = response as? NSHTTPURLResponse where httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (response as? NSHTTPURLResponse)?.statusCode ?? -1)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: nil) : nil
                completionHandler?(error: dbError ?? error)
                return
            }
            do {
                try NSFileManager.defaultManager().moveItemAtURL(cacheURL, toURL: destURL)
                completionHandler?(error: nil)
            } catch let e {
                completionHandler?(error: e)
            }
        })
        task.taskDescription = self.dictionaryToJSON(["type": "Copy", "source": path, "dest": destURL.uw_absoluteString])
        task.resume()
    }
}

extension DropboxFileProvider: FileProviderReadWrite {
    public func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        self.contentsAtPath(path, offset: 0, length: -1, completionHandler: completionHandler)
    }
    
    public func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        let url = NSURL(string: "https://content.dropboxapi.com/2/files/download")!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        if length > 0 {
            request.setValue("bytes=\(offset)-\(offset + length)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let requestDictionary = ["path": path]
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.dataTaskWithRequest(request, completionHandler: { (datam, response, error) in
            guard let data = datam, let httpResponse = response as? NSHTTPURLResponse where httpResponse.statusCode < 300 else {
                let code = FileProviderHTTPErrorCode(rawValue: (response as? NSHTTPURLResponse)?.statusCode ?? -1)
                let dbError: FileProviderDropboxError? = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: datam ?? NSData(), encoding: NSUTF8StringEncoding)) : nil
                completionHandler(contents: nil, error: dbError ?? error)
                return
            }
            completionHandler(contents: data, error: error)
        })
        task.resume()
    }
    
    public func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool = false, completionHandler: SimpleCompletionHandler) {
        // FIXME: remove 150MB restriction
        upload_simple(path, data: data, overwrite: true, operation: .Modify(path: path), completionHandler: completionHandler)
    }
    
    public func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObject) -> Void)?, completionHandler: ((files: [FileObject], error: ErrorType?) -> Void)) {
        var foundFiles = [DropboxFileObject]()
        search(path, query: query, foundItem: { (file) in
            foundFiles.append(file)
            foundItemHandler?(file)
            }, completionHandler: { (error) in
                completionHandler(files: foundFiles, error: error)
        })
    }
    
    private func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is two ways to monitor folders changing in Dropbox. Either using webooks
         * which means you have to implement a server to translate it to push notifications
         * or using apiv2 list_folder/longpoll method. The second one is implemeted here.
         * Tough webhooks are much more efficient, longpoll is much simpler to implement!
         * You can implemnt your own webhook service and replace this method accordingly.
         */
        NotImplemented()
    }
    private func unregisterNotifcation(path: String) {
        NotImplemented()
    }
    
    // TODO: Implement /copy_reference, /get_temporary_link, /save_url, /get_account & /get_current_account
}

extension DropboxFileProvider: ExtendedFileProvider {
    public func thumbnailOfFileSupported(path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercaseString {
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
    
    public func thumbnailOfFileAtPath(path: String, dimension: CGSize, completionHandler: ((image: ImageClass?, error: ErrorType?) -> Void)) {
        let url: NSURL
        switch (path as NSString).pathExtension.lowercaseString {
        case "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff":
            url = NSURL(string: "https://content.dropboxapi.com/2/files/get_thumbnail")!
        /*case "doc", "docx", "docm", "xls", "xlsx", "xlsm":
            fallthrough
        case  "ppt", "pps", "ppsx", "ppsm", "pptx", "pptm":
            fallthrough
        case "rtf":
            url = NSURL(string: "https://content.dropboxapi.com/2/files/get_preview")!*/
        default:
            return
        }
        let request = NSMutableURLRequest(URL: url)
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        var requestDictionary = ["path": path]
        requestDictionary["format"] = "jpeg"
        requestDictionary["size"] = "w\(Int(dimension.width))h\(Int(dimension.height))"
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        self.session.dataTaskWithRequest(request) { (data, response, error) in
            var image: ImageClass? = nil
            if let r = response as? NSHTTPURLResponse, let result = r.allHeaderFields["Dropbox-API-Result"] as? String, let jsonResult = self.jsonToDictionary(result) {
                if jsonResult["error"] != nil {
                    completionHandler(image: nil, error: self.throwError(path, code: NSURLError.CannotDecodeRawData))
                }
            }
            if let data = data {
                image = ImageClass(data: data)
            }
            completionHandler(image: image, error: error)
        }
    }
    
    public func propertiesOfFileAtPath(path: String, completionHandler: ((propertiesDictionary: [String : AnyObject], keys: [String], error: ErrorType?) -> Void)) {
        NotImplemented()
    }
}

extension DropboxFileProvider: FileProvider {}

// MARK: URLSession delegate
extension DropboxFileProvider: NSURLSessionDataDelegate, NSURLSessionDownloadDelegate {
    public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        return
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let desc = task.taskDescription, let json = jsonToDictionary(desc) else {
            return
        }
        guard let type = json["type"] as? String, let source = json["source"] as? String else {
            return
        }
        let dest = json["dest"] as? String
        let op : FileOperation
        switch type {
        case "Create":
            op = .Create(path: source)
        case "Copy":
            guard let dest = dest else { return }
            op = .Copy(source: source, destination: dest)
        case "Move":
            guard let dest = dest else { return }
            op = .Move(source: source, destination: dest)
        case "Modify":
            op = .Modify(path: source)
        case "Remove":
            op = .Remove(path: source)
        case "Link":
            guard let dest = dest else { return }
            op = .Link(link: source, target: dest)
        default:
            return
        }
        
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        
        self.delegate?.fileproviderProgress(self, operation: op, progress: progress)
    }
    
    public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let desc = downloadTask.taskDescription, let json = jsonToDictionary(desc), let source = json["source"] as? String, dest = json["dest"] as? String else {
            return
        }
        
        self.delegate?.fileproviderProgress(self, operation: .Copy(source: source, destination: dest), progress: Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
    }
}