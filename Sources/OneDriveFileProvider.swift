
//
//  OneDriveFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation
import CoreGraphics

/**
 Allows accessing to OneDrive stored files, either hosted on Microsoft servers or business coprporate one.
 This provider doesn't cache or save files internally, however you can set `useCache` and `cache` properties
 to use Foundation `NSURLCache` system.
 
 - Note: Uploading files and data are limited to 100MB, for now.
 */
open class OneDriveFileProvider: HTTPFileProvider, FileProviderSharing {
    override open class var type: String { return "OneDrive" }
    /// Drive name for user, default is `root`. Changing its value will effect on new operations.
    open var drive: String
    
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
       - cache: A URLCache to cache downloaded files and contents.
     */
    public init(credential: URLCredential?, serverURL: URL? = nil, drive: String = "root", cache: URLCache? = nil) {
        let baseURL = serverURL?.absoluteURL ?? URL(string: "https://api.onedrive.com/")!
        let refinedBaseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        self.drive = drive
        super.init(baseURL: refinedBaseURL, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        self.init(credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential,
                  serverURL: aDecoder.decodeObject(forKey: "baseURL") as? URL,
                  drive: aDecoder.decodeObject(forKey: "drive") as? String ?? "root")
        self.currentPath   = aDecoder.decodeObject(forKey: "currentPath") as? String ?? ""
        self.useCache = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    open override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(self.drive, forKey: "drive")
    }
    
    open override func copy(with zone: NSZone? = nil) -> Any {
        let copy = OneDriveFileProvider(credential: self.credential, serverURL: self.baseURL, drive: self.drive, cache: self.cache)
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    open override func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObject], _ error: Error?) -> Void)) {
        list(path) { (contents, cursor, error) in
            completionHandler(contents, error)
        }
    }
    
    open override func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObject?, _ error: Error?) -> Void)) {
        var request = URLRequest(url: url(of: path))
        request.httpMethod = "GET"
        request.set(httpAuthentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            var fileObject: OneDriveFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON(), let file = OneDriveFileObject(baseURL: self.baseURL, drive: self.drive, json: json) {
                    fileObject = file
                }
            }
            completionHandler(fileObject, serverError ?? error)
        }) 
        task.resume()
    }
    
    open override func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        var request = URLRequest(url: url(of: ""))
        request.httpMethod = "GET"
        request.set(httpAuthentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var totalSize: Int64 = -1
            var usedSize: Int64 = 0
            if let json = data?.deserializeJSON() {
                totalSize = (json["total"] as? NSNumber)?.int64Value ?? -1
                usedSize = (json["used"] as? NSNumber)?.int64Value ?? 0
            }
            completionHandler(totalSize, usedSize)
        }) 
        task.resume()
    }
    
    open override func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ((_ files: [FileObject], _ error: Error?) -> Void)) -> Progress? {
        var foundFiles = [OneDriveFileObject]()
        var queryStr: String?
        queryStr = query.findValue(forKey: "name") as? String ?? query.findAllValues(forKey: nil).flatMap { $0.value as? String }.first
        guard let finalQueryStr = queryStr else { return nil }
        let progress = Progress(parent: nil, userInfo: nil)
        progress.setUserInfoObject(url(of: path), forKey: .fileURLKey)
        search(path, query: finalQueryStr, recursive: recursive, progress: progress, foundItem: { (file) in
            if query.evaluate(with: file.mapPredicate()) {
                foundFiles.append(file)
                foundItemHandler?(file)
            }
        }, completionHandler: { (error) in
            completionHandler(foundFiles, error)
        })
        return progress
    }
    
    open func url(of path: String, modifier: String? = nil) -> URL {
        var rpath: String = path
        
        let driveURL = baseURL!.appendingPathComponent("drive/\(drive):/")
        
        if rpath.hasPrefix("/") {
            _=rpath.characters.removeFirst()
        }
        if rpath.isEmpty {
            if let modifier = modifier {
                return driveURL.appendingPathComponent(modifier)
            }
            return driveURL
        }
        
        rpath = rpath.trimmingCharacters(in: pathTrimSet)
        if let modifier = modifier {
            rpath = rpath + ":/" + modifier
        }
        
        return  driveURL.appendingPathComponent(rpath)
    }
    
    open override func isReachable(completionHandler: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url(of: ""))
        request.httpMethod = "HEAD"
        request.set(httpAuthentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            completionHandler(status == 200)
        })
        task.resume()
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey : Any] = [:]) -> URLRequest {
        let method: String
        let url: URL
        switch operation {
        case .fetch(path: let path):
            method = "GET"
            url = self.url(of: path, modifier: "content")
        case .modify(path: let path):
            method = "PUT"
            let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
            url = self.url(of: path, modifier: "content\(queryStr)")
        case .create(path: let path):
            method = "CREATE"
            url = self.url(of: path)
        case .copy(let source, let dest) where !source.hasPrefix("file://") && !dest.hasPrefix("file://"):
            method = "POST"
            url = self.url(of: source)
        case .copy(let source, let dest) where source.hasPrefix("file://"):
            method = "PUT"
            let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
            url = self.url(of: dest, modifier: "content\(queryStr)")
        case .copy(let source, let dest) where dest.hasPrefix("file://"):
            method = "GET"
            url = self.url(of: source, modifier: "content")
        case .move(source: let source, destination: _):
            method = "PATCH"
            url = self.url(of: source)
        case .remove(path: let path):
            method = "DELETE"
            url = self.url(of: path)
        default: // link
            fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.set(httpAuthentication: credential, with: .oAuth2)
        
        switch operation {
        case .copy(let source, let dest) where !source.hasPrefix("file://") && !dest.hasPrefix("file://"),
             .move(source: let source, destination: let dest):
            request.set(httpContentType: .json)
            let cdest = (correctPath(dest) as NSString?)!
            var requestDictionary = [String: AnyObject]()
            requestDictionary["parentReference"] = ("/drive/\(drive):" + cdest.deletingLastPathComponent) as NSString
            requestDictionary["name"] = cdest.lastPathComponent as NSString
            request.httpBody = Data(jsonDictionary: requestDictionary)
        default:
            break
        }
        
        return request
    }
    
    override func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        return FileProviderOneDriveError(code: code, path: path ?? "", errorDescription:  data.flatMap({ String(data: $0, encoding: .utf8) }))
    }
    
    override func upload_simple(_ targetPath: String, request: URLRequest, data: Data?, localFile: URL?, operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> Progress? {
        let size = data?.count ?? Int((try? localFile?.resourceValues(forKeys: [.fileSizeKey]))??.fileSize ?? -1)
        if size > 100 * 1024 * 1024 {
            let error = FileProviderOneDriveError(code: .payloadTooLarge, path: targetPath, errorDescription: nil)
            completionHandler?(error)
            self.delegateNotify(operation, error: error)
            return nil
        }
        
        return super.upload_simple(targetPath, request: request, data: data, localFile: localFile, operation: operation, completionHandler: completionHandler)
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
    
    open func publicLink(to path: String, completionHandler: @escaping ((_ link: URL?, _ attribute: FileObject?, _ expiration: Date?, _ error: Error?) -> Void)) {
        var request = URLRequest(url: self.url(of: path, modifier: "action.createLink"))
        request.httpMethod = "POST"
        let requestDictionary: [String: AnyObject] = ["type": "view" as NSString]
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            var link: URL?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON() {
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
    open func thumbnailOfFileSupported(path: String) -> Bool {
        return true
    }
    
    open func propertiesOfFileSupported(path: String) -> Bool {
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
    
    open func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
        let url: URL
        if let dimension = dimension {
            url = self.url(of: path, modifier: "thumbnails/0/=c\(dimension.width)x\(dimension.height)/content")
        } else {
            url =  self.url(of: path, modifier: "thumbnails/0/small/content")
        }
        
        var request = URLRequest(url: url)
        request.set(httpAuthentication: credential, with: .oAuth2)
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
    
    open func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) {
        var request = URLRequest(url: url(of: path))
        request.httpMethod = "GET"
        request.set(httpAuthentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderOneDriveError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code != nil ? FileProviderOneDriveError(code: code!, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8)) : nil
                if let json = data?.deserializeJSON() {
                    (dic, keys) = self.mapMediaInfo(json)
                }
            }
            completionHandler(dic, keys, serverError ?? error)
        })
        task.resume()
    }
}
