//
//  OneDriveFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif
    
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
    
    /// Microsoft Graph URL
    public static var graphURL = URL(string: "https://graph.microsoft.com/")!
    
    /// Microsoft Graph URL
    public static var graphVersion = "v1.0"
    
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
    public convenience init(credential: URLCredential?, serverURL: URL? = nil, drive: String?, cache: URLCache? = nil) {
        let route: Route = drive.flatMap({ UUID(uuidString: $0) }).flatMap({ Route.drive(uuid: $0) }) ?? .me
        self.init(credential: credential, serverURL: serverURL, route: route, cache: cache)
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
        let baseURL = (serverURL?.absoluteURL ?? OneDriveFileProvider.graphURL)
            .appendingPathComponent(OneDriveFileProvider.graphVersion, isDirectory: true)
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
    
    /// Returns volume/provider information asynchronously.
    /// - Parameter volumeInfo: Information of filesystem/Provider returned by system/server.
    open override func storageProperties(completionHandler: @escaping  (_ volumeInfo: VolumeObject?) -> Void) {
        let url = URL(string: route.drivePath, relativeTo: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authentication: self.credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let json = data?.deserializeJSON() else {
                completionHandler(nil)
                return
            }
            
            let volume = VolumeObject(allValues: [:])
            volume.url = request.url
            volume.uuid = json["id"] as? String
            volume.name = json["name"] as? String
            volume.creationDate = (json["createdDateTime"] as? String).flatMap { Date(rfcString: $0) }
            volume.totalCapacity = (json["quota"]?["total"] as? NSNumber)?.int64Value ?? -1
            volume.availableCapacity = (json["quota"]?["remaining"] as? NSNumber)?.int64Value ?? 0
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
    
    /**
     Returns an independent url to access the file. Some providers like `Dropbox` due to their nature.
     don't return an absolute url to be used to access file directly.
     - Parameter path: Relative path of file or directory.
     - Returns: An url, can be used to access to file directly.
     */
    open override func url(of path: String) -> URL {
        return OneDriveFileObject.url(of: path, modifier: nil, baseURL: baseURL!, route: route)
    }
    
    /**
     Returns an independent url to access the file. Some providers like `Dropbox` due to their nature.
     don't return an absolute url to be used to access file directly.
     - Parameter path: Relative path of file or directory.
     - Parameter modifier: Added to end of url to indicate what it can used for, e.g. `contents` to fetch data.
     - Returns: An url, can be used to access to file directly.
     */
    open func url(of path: String, modifier: String? = nil) -> URL {
        return OneDriveFileObject.url(of: path, modifier: modifier, baseURL: baseURL!, route: route)
    }
    
    open override func relativePathOf(url: URL) -> String {
        return OneDriveFileObject.relativePathOf(url: url, baseURL: baseURL, route: route)
    }
    
    /// Checks the connection to server or permission on local
    ///
    /// - Note: To prevent race condition, use this method wisely and avoid it as far possible.
    ///
    /// - Parameter success: indicated server is reachable or not.
    open override func isReachable(completionHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        var request = URLRequest(url: url(of: ""))
        request.httpMethod = "HEAD"
        request.setValue(authentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            if status >= 400, let code = FileProviderHTTPErrorCode(rawValue: status) {
                let errorDesc = data.flatMap({ String(data: $0, encoding: .utf8) })
                let error = FileProviderOneDriveError(code: code, path: "", serverDescription: errorDesc)
                completionHandler(false, error)
                return
            }
            completionHandler(status == 200, error)
        })
        task.resume()
    }
    
    /**
     Uploads a file from local file url to designated path asynchronously.
     Method will fail if source is not a local url with `file://` scheme.
     
     - Note: It's safe to assume that this method only works on individual files and **won't** copy folders recursively.
     
     - Parameters:
       - localFile: a file url to file.
       - to: destination path of file, including file/directory name.
       - overwrite: Destination file should be overwritten if file is already exists. **Default** is `false`.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress.
     */
    @discardableResult
    open override func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        // check file is not a folder
        guard (try? localFile.resourceValues(forKeys: [.fileResourceTypeKey]))?.fileResourceType ?? .unknown == .regular else {
            dispatch_queue.async {
                completionHandler?(self.urlError(localFile.path, code: .fileIsDirectory))
            }
            return nil
        }
        
        let operation = FileOperationType.copy(source: localFile.absoluteString, destination: toPath)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        return self.upload_multipart_file(toPath, file: localFile, operation: operation, overwrite: overwrite, completionHandler: completionHandler)
    }
    
    /**
     Write the contents of the `Data` to a location asynchronously.
     It will return error if file is already exists.
     Not attomically by default, unless the provider enforces it.
     
     - Parameters:
       - path: Path of target file.
       - contents: Data to be written into file, pass nil to create empty file.
       - completionHandler: If an error parameter was provided, a presentable `Error` will be returned.
     - Returns: An `Progress` to get progress or cancel progress. Doesn't work on `LocalFileProvider`.
     */
    @discardableResult
    open override func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        let operation = FileOperationType.modify(path: path)
        guard fileOperationDelegate?.fileProvider(self, shouldDoOperation: operation) ?? true == true else {
            return nil
        }
        return upload_multipart_data(path, data: data ?? Data(), operation: operation, overwrite: overwrite, completionHandler: completionHandler)
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
        case .create(path: let path) where path.hasSuffix("/"):
            method = "POST"
            let parent =  (path as NSString).deletingLastPathComponent
            url = self.url(of: parent, modifier: "children")
        case .modify(path: let path):
            method = "PUT"
            let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
            url = URL(string: self.url(of: path, modifier: "content").absoluteString + queryStr)!
        case .copy(source: let source, destination: let dest) where source.hasPrefix("file://"):
            method = "PUT"
            let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
            url = URL(string: self.url(of: dest, modifier: "content").absoluteString + queryStr)!
        case .copy(source: let source, destination: let dest) where dest.hasPrefix("file://"):
            method = "GET"
            url = self.url(of: source, modifier: "content")
        case .copy(source: let source, destination: _):
            method = "POST"
            url = self.url(of: source, modifier: "copy")
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
        // Remove gzip to fix availability of progress re. (Oleg Marchik)[https://github.com/evilutioner] PR (#61)
        if method == "GET" {
            request.setValue(acceptEncoding: .deflate)
            request.addValue(acceptEncoding: .identity)
        }
        
        switch operation {
        case .create(path: let path) where path.hasSuffix("/"):
            request.setValue(contentType: .json)
            var requestDictionary = [String: AnyObject]()
            let name = (path as NSString).lastPathComponent
            requestDictionary["name"] = name as NSString
            requestDictionary["folder"] = NSDictionary()
            requestDictionary["@microsoft.graph.conflictBehavior"] = "fail" as NSString
            request.httpBody = Data(jsonDictionary: requestDictionary)
        case .copy(let source, let dest) where !source.hasPrefix("file://") && !dest.hasPrefix("file://"),
             .move(source: let source, destination: let dest):
            request.setValue(contentType: .json, charset: .utf8)
            let cdest = correctPath(dest) as NSString
            var parentReference: [String: AnyObject] = [:]
            if cdest.hasPrefix("id:") {
                parentReference["id"] = cdest.components(separatedBy: "/").first?.replacingOccurrences(of: "id:", with: "", options: .anchored) as NSString?
            } else {
                parentReference["path"] = ("/drive/root:" as NSString).appendingPathComponent(cdest.deletingLastPathComponent) as NSString
            }
            switch self.route {
            case .drive(uuid: let uuid):
                parentReference["driveId"] = uuid.uuidString as NSString
            default:
                //parentReference["driveId"] = cachedDriveID as NSString? ?? ""
                break
            }
            var requestDictionary = [String: AnyObject]()
            requestDictionary["parentReference"] = parentReference as NSDictionary
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
        return FileProviderOneDriveError(code: code, path: path ?? "", serverDescription: errorDesc)
    }
    
    override var maxUploadSimpleSupported: Int64 {
        return 4_194_304 // 4MB!
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
        var request = URLRequest(url: self.url(of: path, modifier: "createLink"))
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
    open func propertiesOfFileSupported(path: String) -> Bool {
        return true
    }
    
    @discardableResult
    open func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String : Any], _ keys: [String], _ error: Error?) -> Void)) -> Progress? {
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
        return nil
    }
    
    #if os(macOS) || os(iOS) || os(tvOS)
    open func thumbnailOfFileSupported(path: String) -> Bool {
        let fileExt = (path as NSString).pathExtension.lowercased()
        switch fileExt {
        case "jpg", "jpeg", "bmp", "gif", "png", "tif", "tiff":
            return true
        case "mp3", "aac", "m4a", "wma":
            return true
        case "mp4", "mpg", "3gp", "mov", "avi", "wmv":
            return true
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pdf":
            return true
        default:
            return false
        }
    }
    
    @discardableResult
    open func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) -> Progress? {
        let thumbQuery: String
        switch dimension.map( {max($0.width, $0.height) } ) ?? 0 {
        case 0...96:   thumbQuery = "small"
        case 97...176: thumbQuery = "medium"
        default:       thumbQuery = "large"
        }
        let url = self.url(of: path, modifier: "thumbnails")
            .appendingPathComponent("0").appendingPathComponent(thumbQuery)
            .appendingPathComponent("content")
        var request = URLRequest(url: url)
        request.setValue(authentication: credential, with: .oAuth2)
        let task = self.session.dataTask(with: request, completionHandler: { (data, response, error) in
            var image: ImageClass? = nil
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 400, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                let responseError = self.serverError(with: rCode, path: path, data: data)
                completionHandler(nil, responseError)
                return
            }
            image = data.flatMap(ImageClass.init(data:))
            completionHandler(image, error)
        })
        task.resume()
        return nil
    }
    #endif
}
