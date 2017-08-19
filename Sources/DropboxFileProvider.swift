
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
open class DropboxFileProvider: HTTPFileProvider, FileProviderSharing {
    override open class var type: String { return "Dropbox" }
    
    /// Dropbox RPC API URL, which is equal with [https://api.dropboxapi.com/2/](https://api.dropboxapi.com/2/)
    open let apiURL: URL
    /// Dropbox contents download/upload API URL, which is equal with [https://content.dropboxapi.com/2/](https://content.dropboxapi.com/2/)
    open let contentURL: URL
    
    /**
     Initializer for Dropbox provider with given client ID and Token.
     These parameters must be retrieved via [OAuth2 API of Dropbox](https://www.dropbox.com/developers/reference/oauth-guide).
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. 
     The latter is easier to use and prefered. Also you can use [auth0/Lock](https://github.com/auth0/Lock.iOS-OSX) which provides graphical user interface.
     
     - Parameter credential: a `URLCredential` object with Client ID set as `user` and Token set as `password`.
     - Parameter cache: A URLCache to cache downloaded files and contents.
    */
    public init(credential: URLCredential?, cache: URLCache? = nil) {
        self.apiURL = URL(string: "https://api.dropboxapi.com/2/")!
        self.contentURL = URL(string: "https://content.dropboxapi.com/2/")!
        super.init(baseURL: nil, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        self.init(credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.currentPath     = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    override open func copy(with zone: NSZone? = nil) -> Any {
        let copy = DropboxFileProvider(credential: self.credential, cache: self.cache)
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    open override func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        let progress = Progress(parent: nil, userInfo: nil)
        list(path, progress: progress) { (contents, cursor, error) in
            completionHandler(contents, error)
        }
    }
    
    open override func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(contentType: .json)
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
    
    open override func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        let url = URL(string: "users/get_space_usage", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.set(httpAuthentication: credential, with: .oAuth2)
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
    
    open override func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) -> Progress? {
        let progress = Progress(parent: nil, userInfo: nil)
        var foundFiles = [DropboxFileObject]()
        if let queryStr = query.findValue(forKey: "name", operator: .beginsWith) as? String {
            // Dropbox only support searching for file names begin with query in non-enterprise accounts.
            // We will use it if there is a `name BEGINSWITH[c] "query"` in predicate, then filter to form final result.
            search(path, query: queryStr, progress: progress, foundItem: { (file) in
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
            list(path, recursive: true, progress: progress, progressHandler: { (files, _, error) in
                for file in files where query.evaluate(with: file.mapPredicate()) {
                    foundItemHandler?(file)
                }
            }, completionHandler: { (files, _, error) in
                let predicatedFiles = files.filter { query.evaluate(with: $0.mapPredicate()) }
                completionHandler(predicatedFiles, error)
            })
        }
        return progress
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool, attributes: [URLResourceKey : Any]) -> URLRequest {
        // content operations
        var request: URLRequest
        switch operation {
        case .copy(source: let source, destination: let dest) where dest.lowercased().hasPrefix("file://"):
            let url = URL(string: "files/download", relativeTo: contentURL)!
            request = URLRequest(url: url)
            request.set(httpAuthentication: credential, with: .oAuth2)
            request.set(dropboxArgKey: ["path": correctPath(source)! as NSString])
        case .fetch(let path):
            let url = URL(string: "files/download", relativeTo: contentURL)!
            request = URLRequest(url: url)
            request.set(httpAuthentication: credential, with: .oAuth2)
            request.set(dropboxArgKey: ["path": correctPath(path)! as NSString])
        case .copy(source: let source, destination: let dest) where source.lowercased().hasPrefix("file://"):
            var requestDictionary = [String: AnyObject]()
            let url: URL = URL(string: "files/upload", relativeTo: contentURL)!
            requestDictionary["path"] = correctPath(dest) as NSString?
            requestDictionary["mode"] = (overwrite ? "overwrite" : "add") as NSString
            requestDictionary["client_modified"] = (attributes[.contentModificationDateKey] as? Date)?.rfc3339utc() as NSString?
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.set(httpAuthentication: credential, with: .oAuth2)
            request.set(contentType: .stream)
            request.set(dropboxArgKey: requestDictionary)
        case .modify(let path):
            var requestDictionary = [String: AnyObject]()
            let url: URL = URL(string: "files/upload", relativeTo: contentURL)!
            requestDictionary["path"] = correctPath(path) as NSString?
            requestDictionary["mode"] = (overwrite ? "overwrite" : "add") as NSString
            requestDictionary["client_modified"] = (attributes[.contentModificationDateKey] as? Date)?.rfc3339utc() as NSString?
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.set(httpAuthentication: credential, with: .oAuth2)
            request.set(contentType: .stream)
            request.set(dropboxArgKey: requestDictionary)
        default: // modify, link, fetch
            return self.apiRequest(for: operation)
        }
        return request
    }
    
    func apiRequest(for operation: FileOperationType) -> URLRequest {
        let url: String
        let sourcePath = operation.source
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
            fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        var request = URLRequest(url: URL(string: url, relativeTo: apiURL)!)
        request.httpMethod = "POST"
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(contentType: .json)
        var requestDictionary = [String: AnyObject]()
        if let dest = correctPath(destPath) as NSString? {
            requestDictionary["from_path"] = correctPath(sourcePath) as NSString?
            requestDictionary["to_path"] = dest
        } else {
            requestDictionary["path"] = correctPath(sourcePath) as NSString?
        }
        request.httpBody = Data(jsonDictionary: requestDictionary)
        return request
    }
    
    override func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        return FileProviderDropboxError(code: code, path: path ?? "", errorDescription: data.flatMap({ String(data: $0, encoding: .utf8) }))
    }
    
    override func upload_simple(_ targetPath: String, request: URLRequest, data: Data?, localFile: URL?, operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> Progress? {
        let size = data?.count ?? Int((try? localFile?.resourceValues(forKeys: [.fileSizeKey]))??.fileSize ?? -1)
        if size > 150 * 1024 * 1024 {
            let error = FileProviderDropboxError(code: .payloadTooLarge, path: targetPath, errorDescription: nil)
            completionHandler?(error)
            self.delegateNotify(operation, error: error)
            return nil
        }
        
        return super.upload_simple(targetPath, request: request, data: data, localFile: localFile, operation: operation, completionHandler: completionHandler)
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
    
    open func publicLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: FileObject?, _ expiration: Date?, _ error: Error?) -> Void)) {
        let url = URL(string: "files/get_temporary_link", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(contentType: .json)
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
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(contentType: .json)
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
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(contentType: .json)
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
        let thumbAPI: Bool
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff":
            url = URL(string: "files/get_thumbnail", relativeTo: contentURL)!
            thumbAPI = true
        case "doc", "docx", "docm", "xls", "xlsx", "xlsm":
            fallthrough
        case  "ppt", "pps", "ppsx", "ppsm", "pptx", "pptm":
            fallthrough
        case "rtf":
            url = URL(string: "files/get_preview", relativeTo: contentURL)!
            thumbAPI = false
        default:
            return
        }
        var request = URLRequest(url: url)
        request.set(httpAuthentication: credential, with: .oAuth2)
        var requestDictionary: [String: AnyObject] = ["path": path as NSString]
        if thumbAPI {
            requestDictionary["format"] = "jpeg" as NSString
            let size: String
            switch dimension?.height ?? 64 {
            case 0...32:    size = "w32h32"
            case 33...64:   size = "w64h64"
            case 65...128:  size = "w128h128"
            case 129...480: size = "w640h480"
            default: size = "w1024h768"
            }
            requestDictionary["size"] = size as NSString
        }
        request.set(dropboxArgKey: requestDictionary)
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
                } else if let fetchedimage = ImageClass(data: data){
                    if let dimension = dimension {
                        image = DropboxFileProvider.scaleDown(image: fetchedimage, toSize: dimension)
                    } else {
                        image = fetchedimage
                    }
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
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(contentType: .json)
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString, "include_media_info": NSNumber(value: true)]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderDropboxError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderDropboxError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON(), let properties = (json["media_info"] as? [String: Any])?["metadata"] as? [String: Any] {
                    (dic, keys) = self.mapMediaInfo(properties)
                }
            }
            completionHandler(dic, keys, serverError ?? error)
        })
        task.resume()
    }
}
