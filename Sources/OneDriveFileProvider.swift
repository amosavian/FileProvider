
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
 
 - Note: You can pass file id instead of file path, e.g `"id:1234abcd"`, to point to a file or folder by ID.
 
 - Note: Uploading files and data are limited to 100MB, for now.
 */
open class OneDriveFileProvider: HTTPFileProvider, FileProviderSharing {
    override open class var type: String { return "OneDrive" }
    
    /// Route to access file container on OneDrive. For default logined user use `.me` otherwise you can acesss
    /// container based on drive id, group id, site id or user id for another user's default container
    public enum Route: RawRepresentable {
        /// Access to default container for current user
        case me
        /// Access to a specific drive by id
        case drive(uuid: UUID)
        /// Access to a default drive of a group by their id
        case group(uuid: UUID)
        /// Access to a default drive of a site by their id
        case site(uuid: UUID)
        /// Access to a default drive of a user by their id
        case user(uuid: UUID)
        
        public init?(rawValue: String) {
            let components = rawValue.components(separatedBy: ";")
            guard let type = components.first else {
                return nil
            }
            if type == "me" {
                self = .me
            }
            guard let uuid = components.last.flatMap({ UUID(uuidString: $0) }) else {
                return nil
            }
            switch type {
            case "drive":
                self = .drive(uuid: uuid)
            case "group":
                self = .group(uuid: uuid)
            case "site":
                self = .site(uuid: uuid)
            case "user":
                self = .user(uuid: uuid)
            default:
                return nil
            }
        }
        
        public var rawValue: String {
            switch self {
            case .me:
                return "me;"
            case .drive(uuid: let uuid):
                return "drive;" + uuid.uuidString
            case .group(uuid: let uuid):
                return "group;" + uuid.uuidString
            case .site(uuid: let uuid):
                return "site;" + uuid.uuidString
            case .user(uuid: let uuid):
                return "user;" + uuid.uuidString
            }
        }
        
        /// Return path component in URL for selected drive
        var drivePath: String {
            switch self {
                case .me:
                return "me/drive"
                case .drive(uuid: let uuid):
                return "drives/" + uuid.uuidString
                case .group(uuid: let uuid):
                return "groups/" + uuid.uuidString + "/drive"
                case .site(uuid: let uuid):
                return "sites/" + uuid.uuidString + "/drive"
                case .user(uuid: let uuid):
                return "users/" + uuid.uuidString + "/drive"
            }
        }
    }
    /// Route for container, default is `.me`.
    open let route: Route
    
    /**
     Initializer for Onedrive provider with given client ID and Token.
     These parameters must be retrieved via [Authentication for the OneDrive API](https://dev.onedrive.com/auth/readme.htm).
     
     There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. The latter is easier to use and prefered.
     
     - Parameters:
       - credential: a `URLCredential` object with Client ID set as `user` and Token set as `password`.
       - serverURL: server url, Set it if you are trying to connect OneDrive Business server, otherwise leave it
         `nil` to connect to OneDrive Personal user.
       - drive: drive name for user on server, default value is `root`.
       - cache: A URLCache to cache downloaded files and contents.
     */
    @available(*, deprecated, message: "use init(credential:, serverURL:, route:, cache:) instead.")
    public init(credential: URLCredential?, serverURL: URL? = nil, drive: String?, cache: URLCache? = nil) {
        let baseURL = serverURL?.absoluteURL ?? URL(string: "https://api.onedrive.com/")!
        let refinedBaseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        self.route = drive.flatMap({ UUID(uuidString: $0) }).flatMap({ Route.drive(uuid: $0) }) ?? .me
        super.init(baseURL: refinedBaseURL, credential: credential, cache: cache)
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
       - route: drive name for user on server, default value is `.me`.
       - cache: A URLCache to cache downloaded files and contents.
     */
    public init(credential: URLCredential?, serverURL: URL? = nil, route: Route = .me, cache: URLCache? = nil) {
        let baseURL = serverURL?.absoluteURL ?? URL(string: "https://api.onedrive.com/")!
        let refinedBaseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        self.route = route
        super.init(baseURL: refinedBaseURL, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        let route: Route
        if let driveId = aDecoder.decodeObject(forKey: "drive") as? String, let uuid = UUID(uuidString: driveId) {
            route = .drive(uuid: uuid)
        } else {
            route = (aDecoder.decodeObject(forKey: "route") as? String).flatMap({ Route(rawValue: $0) }) ?? .me
        }
        self.init(credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential,
                  serverURL: aDecoder.decodeObject(forKey: "baseURL") as? URL,
                  route: route)
        self.useCache = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    open override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(self.route.rawValue, forKey: "route")
    }
    
    open override func copy(with zone: NSZone? = nil) -> Any {
        let copy = OneDriveFileProvider(credential: self.credential, serverURL: self.baseURL, route: self.route, cache: self.cache)
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        copy.useCache = self.useCache
        copy.validatingCache = self.validatingCache
        return copy
    }
    
    open override func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        _ = paginated(path, requestHandler: { [weak self] (token) -> URLRequest? in
            guard let `self` = self else { return nil }
            let url = token.flatMap(URL.init(string:)) ?? self.url(of: path, modifier: "children")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authentication: self.credential, with: .oAuth2)
            return request
        }, pageHandler: { [weak self] (data, _) -> (files: [FileObject], error: Error?, newToken: String?) in
            guard let `self` = self else { return ([], nil, nil) }
            
            guard let json = data?.deserializeJSON(), let entries = json["value"] as? [AnyObject] else {
                let err = self.urlError(path, code: .badServerResponse)
                return ([], err, nil)
            }
            
            var files = [FileObject]()
            for entry in entries {
                if let entry = entry as? [String: AnyObject], let file = OneDriveFileObject(baseURL: self.baseURL, route: self.route, json: entry) {
                    files.append(file)
                }
            }
            return (files, nil, json["@odata.nextLink"] as? String)
        }, completionHandler: completionHandler)
    }
    
    open override func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
        var request = URLRequest(url: url(of: path))
        request.httpMethod = "GET"
        request.setValue(authentication: self.credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            var fileObject: OneDriveFileObject?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: path, data: data) }
                if let json = data?.deserializeJSON(), let file = OneDriveFileObject(baseURL: self.baseURL, route: self.route, json: json) {
                    fileObject = file
                }
            }
            completionHandler(fileObject, serverError ?? error)
        }) 
        task.resume()
    }
    
    open override func storageProperties(completionHandler: @escaping  (_ volumeInfo: VolumeObject?) -> Void) {
        var request = URLRequest(url: url(of: ""))
        request.httpMethod = "GET"
        request.setValue(authentication: self.credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON() else {
                completionHandler(nil)
                return
            }
            
            let volume = VolumeObject(allValues: [:])
            volume.url = request.url
            volume.name = json["name"] as? String
            volume.creationDate = (json["createdDateTime"] as? String).flatMap { Date(rfcString: $0) }
            volume.totalCapacity = (json["quota"]?["total"] as? NSNumber)?.int64Value ?? -1
            volume.availableCapacity = (json["quota"]?["remaining"] as? NSNumber)?.int64Value ?? 0
            completionHandler(volume)
        }) 
        task.resume()
    }
    
    open override func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let queryStr = query.findValue(forKey: "name") as? String ?? query.findAllValues(forKey: nil).flatMap { $0.value as? String }.first
        
        return paginated(path, requestHandler: { [weak self] (token) -> URLRequest? in
            guard let `self` = self else { return nil }
            
            let url: URL
            if let next = token.flatMap(URL.init(string:)) {
                url = next
            } else {
                let bURL = self.baseURL!.appendingPathComponent(self.route.drivePath).appendingPathComponent("root/search")
                var components = URLComponents(url: bURL, resolvingAgainstBaseURL: false)!
                let qItem = URLQueryItem(name: "q", value: (queryStr ?? "*"))
                components.queryItems = [qItem]
                if recursive {
                    components.queryItems?.append(URLQueryItem(name: "expand", value: "children"))
                }
                url = components.url!
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }, pageHandler: { [weak self] (data, progress) -> (files: [FileObject], error: Error?, newToken: String?) in
            guard let `self` = self else { return ([], nil, nil) }
            guard let json = data?.deserializeJSON(), let entries = json["value"] as? [AnyObject] else {
                let err = self.urlError(path, code: .badServerResponse)
                return ([], err, nil)
            }
            
            var foundFiles = [FileObject]()
            for entry in entries {
                if let entry = entry as? [String: AnyObject], let file = OneDriveFileObject(baseURL: self.baseURL, route: self.route, json: entry), query.evaluate(with: file.mapPredicate()) {
                    foundFiles.append(file)
                    foundItemHandler?(file)
                }
            }
            
            return (foundFiles, nil, json["@odata.nextLink"] as? String)
        }, completionHandler: completionHandler)
    }
    
    open func url(of path: String, modifier: String? = nil) -> URL {
        var url: URL = baseURL!
        var rpath: String = path
        let isId = path.hasPrefix("id:")
        
        url.appendPathComponent(route.drivePath)
        
        if isId {
            url.appendPathComponent("root:")
        } else {
            url.appendPathComponent("items")
        }
        
        rpath = rpath.trimmingCharacters(in: pathTrimSet)
        
        switch (modifier == nil, rpath.isEmpty, isId) {
        case (true, false, _):
            url.appendPathComponent(rpath)
        case (true, true, _):
            break
        case (false, true, _):
            url.appendPathComponent(modifier!)
        case (false, false, true):
            url.appendPathComponent(rpath)
            url.appendPathComponent(modifier!)
        case (false, false, false):
            url.appendPathComponent(rpath + ":")
            url.appendPathComponent(modifier!)
        }
        
        return url
    }
    
    open override func isReachable(completionHandler: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url(of: ""))
        request.httpMethod = "HEAD"
        request.setValue(authentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            completionHandler(status == 200)
        })
        task.resume()
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = false, attributes: [URLResourceKey : Any] = [:]) -> URLRequest {
        
        func correctPath(_ path: String) -> String {
            if path.hasPrefix("id:") {
                return path
            }
            var p = path.hasPrefix("/") ? path : "/" + path
            if p.hasSuffix("/") {
                p.remove(at: p.index(before:p.endIndex))
            }
            return p
        }
        
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
        request.setValue(authentication: self.credential, with: .oAuth2)
        // Remove gzip to fix availability of progress per (Oleg Marchik)[https://github.com/evilutioner] PR (#61)
        request.setValue(acceptEncoding: .deflate)
        request.addValue(acceptEncoding: .identity)
        
        switch operation {
        case .copy(let source, let dest) where !source.hasPrefix("file://") && !dest.hasPrefix("file://"),
             .move(source: let source, destination: let dest):
            request.setValue(contentType: .json)
            let cdest = correctPath(dest) as NSString
            var parentRefrence: [String: AnyObject] = [:]
            if cdest.hasPrefix("id:") {
                parentRefrence["id"] = cdest.components(separatedBy: "/").first as NSString?
                switch self.route {
                case .drive(uuid: let uuid):
                    parentRefrence["driveId"] = uuid.uuidString as NSString
                default:
                    break
                }
            } else {
                parentRefrence["path"] = cdest.deletingLastPathComponent as NSString
            }
            var requestDictionary = [String: AnyObject]()
            requestDictionary["parentReference"] = parentRefrence as NSDictionary
            requestDictionary["name"] = (cdest as NSString).lastPathComponent as NSString
            request.httpBody = Data(jsonDictionary: requestDictionary)
        default:
            break
        }
        
        return request
    }
    
    override func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        let errorDesc: String?
        if let response = data?.deserializeJSON() {
            errorDesc = response["error"]?["message"] as? String
        } else {
            errorDesc = data.flatMap({ String(data: $0, encoding: .utf8) })
        }
        return FileProviderOneDriveError(code: code, path: path ?? "", errorDescription: errorDesc)
    }
    
    override var maxUploadSimpleSupported: Int64 {
        return 104_857_600 // 100MB
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
            var serverError: FileProviderHTTPError?
            var link: URL?
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: path, data: data) }
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
        request.setValue(authentication: credential, with: .oAuth2)
        let task = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                let responseError = self.serverError(with: rCode, path: path, data: data)
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
        request.setValue(authentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var serverError: FileProviderHTTPError?
            var dic = [String: Any]()
            var keys = [String]()
            if let response = response as? HTTPURLResponse {
                let code = FileProviderHTTPErrorCode(rawValue: response.statusCode)
                serverError = code.flatMap { self.serverError(with: $0, path: path, data: data) }
                if let json = data?.deserializeJSON() {
                    (dic, keys) = self.mapMediaInfo(json)
                }
            }
            completionHandler(dic, keys, serverError ?? error)
        })
        task.resume()
    }
}
