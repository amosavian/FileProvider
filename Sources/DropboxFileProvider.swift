
//
//  DropboxFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif

/**
 Allows accessing to Dropbox stored files. This provider doesn't cache or save files internally, however you can
 set `useCache` and `cache` properties to use Foundation `NSURLCache` system.
 
 - Note: You can pass file id or rev instead of file path, e.g `"id:1234abcd"` or `"rev:1234abcd"`, to point to a file or folder by ID.
 
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
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. The latter is easier to use and prefered.
     
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
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    override open func copy(with zone: NSZone? = nil) -> Any {
        let copy = DropboxFileProvider(credential: self.credential, cache: self.cache)
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameters:
       - path: path to target directory. If empty, root will be iterated.
       - completionHandler: a closure with result of directory entries or error.
       - contents: An array of `FileObject` identifying the the directory entries.
       - error: Error returned by system.
     */
    open override func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        let query = NSPredicate(format: "TRUEPREDICATE")
        _ = searchFiles(path: path, recursive: false, query: query, foundItemHandler: nil, completionHandler: completionHandler)
    }
    
    /**
     Returns a `FileObject` containing the attributes of the item (file, directory, symlink, etc.) at the path in question via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty `FileObject`.
     
     - Parameters:
       - path: path to target directory. If empty, attributes of root will be returned.
       - completionHandler: a closure with result of directory entries or error.
       - attributes: A `FileObject` containing the attributes of the item.
       - error: Error returned by system.
     */
    open override func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse, response.statusCode >= 400 {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: path, data: data) }
            }
            if let json = data?.deserializeJSON(), let file = DropboxFileObject(json: json) {
                fileObject = file
            }
            completionHandler(fileObject, serverError ?? error)
        }) 
        task.resume()
    }
    
    /// Returns volume/provider information asynchronously.
    /// - Parameter volumeInfo: Information of filesystem/Provider returned by system/server.
    open override func storageProperties(completionHandler: @escaping (_ volumeInfo: VolumeObject?) -> Void) {
        let url = URL(string: "users/get_space_usage", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON() else {
                completionHandler(nil)
                return
            }
            
            let volume = VolumeObject(allValues: [:])
            volume.totalCapacity = ((json["allocation"] as? NSDictionary)?["allocated"] as? NSNumber)?.int64Value ?? -1
            volume.usage = (json["used"] as? NSNumber)?.int64Value ?? 0
            completionHandler(volume)
        }) 
        task.resume()
    }
    
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
    open override func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let queryStr: String?
        if query.predicateFormat == "TRUEPREDICATE" {
            queryStr = nil
        } else {
            queryStr = query.findValue(forKey: "name", operator: .beginsWith) as? String
        }
        let requestHandler = self.listRequest(path: path, queryStr: queryStr, recursive: recursive)
        let queryIsTruePredicate = query.predicateFormat == "TRUEPREDICATE"
        return paginated(path, requestHandler: requestHandler,
            pageHandler: { [weak self] (data, progress) -> (files: [FileObject], error: Error?, newToken: String?) in
            guard let json = data?.deserializeJSON(), let entries = (json["entries"] ?? json["matches"]) as? [AnyObject] else {
                let err = self?.urlError(path, code: .badServerResponse)
                return ([], err, nil)
            }
            
            var files = [FileObject]()
            for entry in entries {
                if let entry = entry as? [String: AnyObject], let file = DropboxFileObject(json: entry), queryIsTruePredicate || query.evaluate(with: file.mapPredicate()) {
                    files.append(file)
                    progress.completedUnitCount += 1
                    foundItemHandler?(file)
                }
            }
            let ncursor: String?
            if let hasmore = (json["has_more"] as? NSNumber)?.boolValue, hasmore {
                ncursor = json["cursor"] as? String
            } else if let hasmore = (json["more"] as? NSNumber)?.boolValue, hasmore {
                ncursor = (json["start"] as? Int).flatMap(String.init)
            } else {
                ncursor = nil
            }
            return (files, nil, ncursor)
        }, completionHandler: completionHandler)
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey : Any] = [:]) -> URLRequest {
        
        func uploadRequest(to path: String) -> URLRequest {
            var requestDictionary = [String: AnyObject]()
            let url: URL = URL(string: "files/upload", relativeTo: contentURL)!
            requestDictionary["path"] = correctPath(path) as NSString?
            requestDictionary["mode"] = (overwrite ? "overwrite" : "add") as NSString
            //requestDictionary["client_modified"] = (attributes[.contentModificationDateKey] as? Date)?.format(with: .rfc3339) as NSString?
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(authentication: credential, with: .oAuth2)
            request.setValue(contentType: .stream)
            request.setValue(dropboxArgKey: requestDictionary)
            return request
        }
        
        func downloadRequest(from path: String) -> URLRequest {
            let url = URL(string: "files/download", relativeTo: contentURL)!
            var request = URLRequest(url: url)
            request = URLRequest(url: url)
            request.setValue(authentication: credential, with: .oAuth2)
            request.setValue(dropboxArgKey: ["path": correctPath(path)! as NSString])
            return request
        }
        
        // content operations
        switch operation {
        case .copy(source: let source, destination: let dest) where dest.lowercased().hasPrefix("file://"):
            return downloadRequest(from: source)
        case .fetch(let path):
            return downloadRequest(from: path)
        case .copy(source: let source, destination: let dest) where source.lowercased().hasPrefix("file://"):
            return uploadRequest(to: dest)
        case .modify(let path):
            return uploadRequest(to: path)
        default:
            return self.apiRequest(for: operation, overwrite: overwrite)
        }
    }
    
    func apiRequest(for operation: FileOperationType, overwrite: Bool = false) -> URLRequest {
        let url: String
        let sourcePath = operation.source
        let destPath = operation.destination
        var requestDictionary = [String: AnyObject]()
        switch operation {
        case .create:
            url = "files/create_folder_v2"
            
        case .copy:
            url = "files/copy_v2"
            requestDictionary["allow_shared_folder"] = NSNumber(value: true)
        case .move:
            url = "files/move_v2"
            requestDictionary["allow_shared_folder"] = NSNumber(value: true)
        case .remove:
            url = "files/delete_v2"
        default: // modify, link, fetch
            fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        var request = URLRequest(url: URL(string: url, relativeTo: apiURL)!)
        request.httpMethod = "POST"
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
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
        let errorDesc: String?
        if let response = data?.deserializeJSON() {
            errorDesc = (response["user_message"] as? String) ?? (response["error"]?["tag"] as? String)
        } else {
            errorDesc = data.flatMap({ String(data: $0, encoding: .utf8) })
        }
        return FileProviderDropboxError(code: code, path: path ?? "", serverDescription: errorDesc)
    }
    
    override var maxUploadSimpleSupported: Int64 {
        return 157_286_400 // 150MB
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
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            var link: URL?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: path, data: data) }
                if let json = data?.deserializeJSON() {
                    link = (json["link"] as? String).flatMap(URL.init(string:))
                    fileObject = (json["metadata"] as? [String: AnyObject]).flatMap(DropboxFileObject.init(json:))
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
            completionHandler(nil, nil, self.urlError(remoteURL.path, code: .badURL))
            return
        }
        let url = URL(string: "files/save_url", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
        let requestDictionary: [String: AnyObject] = ["path": correctPath(toPath)! as NSString, "url" : remoteURL.absoluteString as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            var jobId: String?
            var fileObject: DropboxFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: toPath, data: data) }
                if let json = data?.deserializeJSON() {
                    jobId = json["async_job_id"] as? String
                    fileObject = (json["metadata"] as? [String: AnyObject]).flatMap(DropboxFileObject.init(json:))
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
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
        let requestDictionary: [String: AnyObject] = ["path": correctPath(toPath)! as NSString, "copy_reference" : reference as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: toPath, data: data) }
            }
            completionHandler?(serverError ?? error)
        })
        task.resume()
    }
}

extension DropboxFileProvider: ExtendedFileProvider {
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
    
    @discardableResult
    open func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) -> Progress? {
        let url = URL(string: "files/get_metadata", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authentication: credential, with: .oAuth2)
        request.setValue(contentType: .json)
        let requestDictionary: [String: AnyObject] = ["path": correctPath(path)! as NSString, "include_media_info": NSNumber(value: true)]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: path, data: data) }
                if let json = data?.deserializeJSON(), let properties = (json["media_info"] as? [String: Any])?["metadata"] as? [String: Any] {
                    (dic, keys) = self.mapMediaInfo(properties)
                }
            }
            completionHandler(dic, keys, serverError ?? error)
        })
        task.resume()
        return nil
    }
    
    #if os(macOS) || os(iOS) || os(tvOS)
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
    
    /// Default value for dimension is 64x64, according to Dropbox documentation
    @discardableResult
    open func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) -> Progress? {
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
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(authentication: credential, with: .oAuth2)
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
        request.setValue(dropboxArgKey: requestDictionary)
        let task = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let r = response as? HTTPURLResponse, let result = r.allHeaderFields["Dropbox-API-Result"] as? String, let jsonResult = result.deserializeJSON() {
                if jsonResult["error"] != nil {
                    completionHandler(nil, self.urlError(path, code: .cannotDecodeRawData))
                }
            }
            if let data = data {
                if data.isPDF, let pageImage = DropboxFileProvider.convertToImage(pdfData: data) {
                    image = pageImage
                } else if let contentType = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, contentType.contains("text/html") {
                     // TODO: Implement converting html returned type of get_preview to image
                } else if let fetchedimage = ImageClass(data: data) {
                    image = dimension.map({ DropboxFileProvider.scaleDown(image: fetchedimage, toSize: $0) }) ?? fetchedimage
                }
            }
            completionHandler(image, error)
        })
        task.resume()
        return nil
    }
    #endif
}
