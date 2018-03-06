//
//  WebDAVFileProvider.swift
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
 Allows accessing to WebDAV server files. This provider doesn't cache or save files internally, however you can
 set `useCache` and `cache` properties to use Foundation `NSURLCache` system.
 
 WebDAV system supported by many cloud services including [Box.com](https://www.box.com/home) 
 and [Yandex disk](https://disk.yandex.com) and [ownCloud](https://owncloud.org).
 
 - Important: Because this class uses `URLSession`, it's necessary to disable App Transport Security
     in case of using this class with unencrypted HTTP connection.
     [Read this to know how](http://iosdevtips.co/post/121756573323/ios-9-xcode-7-http-connect-server-error).
*/
open class WebDAVFileProvider: HTTPFileProvider, FileProviderSharing {
    override open class var type: String { return "WebDAV" }
    
    /// An enum which defines HTTP Authentication method, usually you should it default `.digest`.
    /// If the server uses OAuth authentication, credential must be set with token as `password`, like Dropbox.
    public var credentialType: URLRequest.AuthenticationType = .digest
    
    /**
     Initializes WebDAV provider.
     
     - Parameters:
       - baseURL: Location of WebDAV server.
       - credential: An `URLCredential` object with `user` and `password`.
       - cache: A URLCache to cache downloaded files and contents.
    */
    public init? (baseURL: URL, credential: URLCredential?, cache: URLCache? = nil) {
        if  !["http", "https"].contains(baseURL.uw_scheme.lowercased()) {
            return nil
        }
        let refinedBaseURL = (baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent(""))
        super.init(baseURL: refinedBaseURL.absoluteURL, credential: credential, cache: cache)
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(forKey: "baseURL") as? URL else {
            return nil
        }
        self.init(baseURL: baseURL,
                  credential: aDecoder.decodeObject(forKey: "credential") as? URLCredential)
        self.useCache        = aDecoder.decodeBool(forKey: "useCache")
        self.validatingCache = aDecoder.decodeBool(forKey: "validatingCache")
    }
    
    override open func copy(with zone: NSZone? = nil) -> Any {
        let copy = WebDAVFileProvider(baseURL: self.baseURL!, credential: self.credential, cache: self.cache)!
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
    override open func contentsOfDirectory(path: String, completionHandler: @escaping (([FileObject], Error?) -> Void)) {
        let query = NSPredicate(format: "TRUEPREDICATE")
        _ = searchFiles(path: path, recursive: false, query: query, including: [], foundItemHandler: nil, completionHandler: completionHandler)
    }
    
    /**
     Returns an Array of `FileObject`s identifying the the directory entries via asynchronous completion handler.
     
     If the directory contains no entries or an error is occured, this method will return the empty array.
     
     - Parameter path: path to target directory. If empty, root will be iterated.
     - Parameter including: An array which determines which file properties should be considered to fetch.
     - Parameter completionHandler: a closure with result of directory entries or error.
     - Parameter contents: An array of `FileObject` identifying the the directory entries.
     - Parameter error: Error returned by system.
     */
    open func contentsOfDirectory(path: String, including: [URLResourceKey], completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) {
        let query = NSPredicate(format: "TRUEPREDICATE")
        _ = searchFiles(path: path, recursive: false, query: query, including: including, foundItemHandler: nil, completionHandler: completionHandler)
    }
    
    override open func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
        self.attributesOfItem(path: path, including: [], completionHandler: completionHandler)
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
    open func attributesOfItem(path: String, including: [URLResourceKey], completionHandler: @escaping (_ attributes: FileObject?, _ error: Error?) -> Void) {
        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(contentType: .xml, charset: .utf8)
        request.httpBody = WebDavFileObject.xmlProp(including)
        runDataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderHTTPError?
            if let code = (response as? HTTPURLResponse)?.statusCode, code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = self.serverError(with: rCode, path: path, data: data)
            }
            if let data = data {
                let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                if let attr = xresponse.first {
                    completionHandler(WebDavFileObject(attr), responseError ?? error)
                    return
                }
            }
            completionHandler(nil, responseError ?? error)
        })
    }
    
    /// Returns volume/provider information asynchronously.
    /// - Parameter volumeInfo: Information of filesystem/Provider returned by system/server.
    override open func storageProperties(completionHandler: @escaping (_ volumeInfo: VolumeObject?) -> Void) {
        // Not all WebDAV clients implements RFC2518 which allows geting storage quota.
        // In this case you won't get error. totalSize is NSURLSessionTransferSizeUnknown
        // and used space is zero.
        guard let baseURL = baseURL else {
            return
        }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(contentType: .xml, charset: .utf8)
        request.httpBody = WebDavFileObject.xmlProp([.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .creationDateKey])
        runDataTask(with: request, completionHandler: { (data, response, error) in
            guard let data = data, let attr = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL).first else {
                completionHandler(nil)
                return
            }
            
            let volume = VolumeObject(allValues: [:])
            volume.creationDate = attr.prop["creationdate"].flatMap { Date(rfcString: $0) }
            volume.availableCapacity = attr.prop["quota-available-bytes"].flatMap({ Int64($0) }) ?? 0
            if let usage = attr.prop["quota-used-bytes"].flatMap({ Int64($0) }) {
                volume.totalCapacity = volume.availableCapacity + usage
            }
            completionHandler(volume)
        })
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
    open override func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping ([FileObject], Error?) -> Void) -> Progress? {
        return searchFiles(path: path, recursive: recursive, query: query, including: [], foundItemHandler: foundItemHandler, completionHandler: completionHandler)
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
       - including: An array which determines which file properties should be considered to fetch.
       - foundItemHandler: Closure which is called when a file is found
       - completionHandler: Closure which will be called after finishing search. Returns an arry of `FileObject` or error if occured.
       - files: all files meat the `query` criteria.
       - error: `Error` returned by server if occured.
     - Returns: An `Progress` to get progress or cancel progress. Use `completedUnitCount` to iterate count of found items.
     */
    @discardableResult
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, including: [URLResourceKey], foundItemHandler: ((FileObject) -> Void)?, completionHandler: @escaping (_ files: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        // Depth infinity is disabled on some servers. Implement workaround?!
        request.setValue(recursive ? "infinity" : "1", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(contentType: .xml, charset: .utf8)
        request.httpBody = WebDavFileObject.xmlProp(including)
        let progress = Progress(totalUnitCount: -1)
        progress.setUserInfoObject(url, forKey: .fileURLKey)
        
        let queryIsTruePredicate = query.predicateFormat == "TRUEPREDICATE"
        let task = session.dataTask(with: request) { (data, response, error) in
            // FIXME: paginating results
            var responseError: FileProviderHTTPError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = self.serverError(with: rCode, path: path, data: data)
            }
            guard let data = data else {
                completionHandler([], responseError ?? error)
                return
            }
            
            let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
            var fileObjects = [WebDavFileObject]()
            for attr in xresponse where attr.href.path != url.path {
                let fileObject = WebDavFileObject(attr)
                if !queryIsTruePredicate && !query.evaluate(with: fileObject.mapPredicate()) {
                    continue
                }
                
                fileObjects.append(fileObject)
                progress.completedUnitCount = Int64(fileObjects.count)
                foundItemHandler?(fileObject)
            }
            completionHandler(fileObjects, responseError ?? error)
        }
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
        return progress
    }
    
    override open func isReachable(completionHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        var request = URLRequest(url: baseURL!)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(contentType: .xml, charset: .utf8)
        request.httpBody = WebDavFileObject.xmlProp([.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        runDataTask(with: request, completionHandler: { (data, response, error) in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            if status >= 400, let code = FileProviderHTTPErrorCode(rawValue: status) {
                let errorDesc = data.flatMap({ String(data: $0, encoding: .utf8) })
                let error = FileProviderWebDavError(code: code, path: "", serverDescription: errorDesc, url: self.baseURL!)
                completionHandler(false, error)
                return
            }
            completionHandler(status < 300, error)
        })
    }
    
    open func publicLink(to path: String, completionHandler: @escaping ((URL?, FileObject?, Date?, Error?) -> Void)) {
        guard self.baseURL?.host?.contains("dav.yandex.") ?? false else {
            dispatch_queue.async {
                completionHandler(nil, nil, nil, self.urlError(path, code: .resourceUnavailable))
            }
            return
        }
        
        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPPATCH"
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(contentType: .xml, charset: .utf8)
        let body = "<propertyupdate xmlns=\"DAV:\">\n<set><prop>\n<public_url xmlns=\"urn:yandex:disk:meta\">true</public_url>\n</prop></set>\n</propertyupdate>"
        request.httpBody = body.data(using: .utf8)
        runDataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderHTTPError?
            if let code = (response as? HTTPURLResponse)?.statusCode, code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = self.serverError(with: rCode, path: path, data: data)
            }
            if let data = data {
                let xresponse = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                if let urlStr = xresponse.first?.prop["public_url"], let url = URL(string: urlStr) {
                    completionHandler(url, nil, nil, nil)
                    return
                }
            }
            completionHandler(nil, nil, nil, responseError ?? error)
        })
    }
    
    override func request(for operation: FileOperationType, overwrite: Bool = true, attributes: [URLResourceKey: Any] = [:]) -> URLRequest {
        let method: String
        let url: URL
        let sourceURL = self.url(of: operation.source)
        
        switch operation {
        case .fetch:
            method = "GET"
            url = sourceURL
        case .create:
            if sourceURL.absoluteString.hasSuffix("/") {
                method = "MKCOL"
                url = sourceURL
            } else {
                fallthrough
            }
        case .modify:
            method = "PUT"
            url = sourceURL
            break
        case .copy(let source, let dest):
            if source.hasPrefix("file://") {
                method = "PUT"
                url = self.url(of: dest)
            } else if dest.hasPrefix("file://") {
                method = "GET"
                url = sourceURL
            } else {
                method = "COPY"
                url = sourceURL
            }
        case .move:
            method = "MOVE"
            url = sourceURL
        case .remove:
            method = "DELETE"
            url = sourceURL
        default:
            fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")
        if let dest = operation.destination, !dest.hasPrefix("file://") {
            request.setValue(self.url(of:dest).absoluteString, forHTTPHeaderField: "Destination")
        }
        
        return request
    }
    
    override func serverError(with code: FileProviderHTTPErrorCode, path: String?, data: Data?) -> FileProviderHTTPError {
        return FileProviderWebDavError(code: code, path: path ?? "", serverDescription:  data.flatMap({ String(data: $0, encoding: .utf8) }), url: self.url(of: path ?? ""))
    }
    
    override func multiStatusHandler(source: String, data: Data, completionHandler: SimpleCompletionHandler) {
        let xresponses = DavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
        for xresponse in xresponses where (xresponse.status ?? 0) >= 300 {
            let code = xresponse.status.flatMap { FileProviderHTTPErrorCode(rawValue: $0) } ?? .internalServerError
            let error = self.serverError(with: code, path: source, data: data)
            completionHandler?(error)
        }
    }
    
    /*
    fileprivate func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        /* There is no unified api for monitoring WebDAV server content change/update
         * Microsoft Exchange uses SUBSCRIBE method, Apple uses push notification system.
         * while both is unavailable in a mobile platform.
         * A messy approach is listing a directory with an interval period and compare
         * with previous results
         */
        NotImplemented()
    }
    fileprivate func unregisterNotifcation(path: String) {
        NotImplemented()
    }*/
    // TODO: implements methods for lock mechanism
}

extension WebDAVFileProvider: ExtendedFileProvider {
    #if os(macOS) || os(iOS) || os(tvOS)
    open func thumbnailOfFileSupported(path: String) -> Bool {
        guard self.baseURL?.host?.contains("dav.yandex.") ?? false else {
            return false
        }
        let supportedExt: [String] = ["jpg", "jpeg", "png", "gif"]
        return supportedExt.contains((path as NSString).pathExtension)
    }
    
    @discardableResult
    open func thumbnailOfFile(path: String, dimension: CGSize?, completionHandler: @escaping ((ImageClass?, Error?) -> Void)) -> Progress? {
        guard self.baseURL?.host?.contains("dav.yandex.") ?? false else {
            dispatch_queue.async {
                completionHandler(nil, self.urlError(path, code: .resourceUnavailable))
            }
            return nil
        }
        
        let dimension = dimension ?? CGSize(width: 64, height: 64)
        let url = URL(string: self.url(of: path).absoluteString + "?preview&size=\(dimension.width)x\(dimension.height)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authentication: credential, with: credentialType)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderHTTPError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = self.serverError(with: rCode, path: url.relativePath, data: data)
                completionHandler(nil, responseError ?? error)
                return
            }
            
            completionHandler(data.flatMap({ ImageClass(data: $0) }), nil)
        })
        task.resume()
        return nil
    }
    #endif
    
    open func propertiesOfFileSupported(path: String) -> Bool {
        return false
    }
    
    @discardableResult
    open func propertiesOfFile(path: String, completionHandler: @escaping (([String : Any], [String], Error?) -> Void)) -> Progress? {
        dispatch_queue.async {
            completionHandler([:], [], self.urlError(path, code: .resourceUnavailable))
        }
        return nil
    }
}

// MARK: WEBDAV XML response implementation

struct DavResponse {
    let href: URL
    let hrefString: String
    let status: Int?
    let prop: [String: String]
    
    static let urlAllowed = CharacterSet(charactersIn: " ").inverted
    
    init? (_ node: AEXMLElement, baseURL: URL?) {
        
        func standardizePath(_ str: String) -> String {
            #if swift(>=4.0)
            let trimmedStr = str.hasPrefix("/") ? String(str[str.index(after: str.startIndex)...]) : str
            #else
            let trimmedStr = str.hasPrefix("/") ? str.substring(from: str.index(after: str.startIndex)) : str
            #endif
            return trimmedStr.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? str
        }
        
        // find node names with namespace
        var hreftag = "href"
        var statustag = "status"
        var propstattag = "propstat"
        for node in node.children {
            if node.name.lowercased().hasSuffix("href") {
                hreftag = node.name
            }
            if node.name.lowercased().hasSuffix("status") {
                statustag = node.name
            }
            if node.name.lowercased().hasSuffix("propstat") {
                propstattag = node.name
            }
        }
        
        guard let hrefString = node[hreftag].value else { return nil }
        
        // Percent-encoding space, some servers return invalid urls which space is not encoded to %20
        let hrefStrPercented = hrefString.addingPercentEncoding(withAllowedCharacters: DavResponse.urlAllowed) ?? hrefString
        // trying to figure out relative path out of href
        let hrefAbsolute = URL(string: hrefStrPercented, relativeTo: baseURL)?.absoluteURL
        let relativePath: String
        if hrefAbsolute?.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) == baseURL?.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) {
            relativePath = hrefAbsolute?.path.replacingOccurrences(of: baseURL?.absoluteURL.path ?? "", with: "", options: .anchored, range: nil) ?? hrefString
        } else {
            relativePath = hrefAbsolute?.absoluteString.replacingOccurrences(of: baseURL?.absoluteString ?? "", with: "", options: .anchored, range: nil) ?? hrefString
        }
        let hrefURL = URL(string: standardizePath(relativePath), relativeTo: baseURL) ?? baseURL
        
        guard let href = hrefURL?.standardized else { return nil }
        
        // reading status and properties
        var status: Int?
        let statusDesc = (node[statustag].string).components(separatedBy: " ")
        if statusDesc.count > 2 {
            status = Int(statusDesc[1])
        }
        var propDic = [String: String]()
        let propStatNode = node[propstattag]
        for node in propStatNode.children where node.name.lowercased().hasSuffix("status"){
            statustag = node.name
            break
        }
        let statusDesc2 = (propStatNode[statustag].string).components(separatedBy: " ")
        if statusDesc2.count > 2 {
            status = Int(statusDesc2[1])
        }
        var proptag = "prop"
        for tnode in propStatNode.children where tnode.name.lowercased().hasSuffix("prop") {
            proptag = tnode.name
            break
        }
        for propItemNode in propStatNode[proptag].children {
            let key = propItemNode.name.components(separatedBy: ":").last!.lowercased()
            guard propDic.index(forKey: key) == nil else { continue }
            propDic[key] = propItemNode.value
            if key == "resourcetype" && propItemNode.xml.contains("collection") {
                propDic["getcontenttype"] = ContentMIMEType.directory.rawValue
            }
        }
        self.href = href
        self.hrefString = hrefString
        self.status = status
        self.prop = propDic
    }
    
    static func parse(xmlResponse: Data, baseURL: URL?) -> [DavResponse] {
        guard let xml = try? AEXMLDocument(xml: xmlResponse) else { return [] }
        var result = [DavResponse]()
        var rootnode = xml.root
        var responsetag = "response"
        for node in rootnode.all ?? [] where node.name.lowercased().hasSuffix("multistatus") {
            rootnode = node
        }
        for node in rootnode.children where node.name.lowercased().hasSuffix("response") {
            responsetag = node.name
            break
        }
        for responseNode in rootnode[responsetag].all ?? [] {
            if let davResponse = DavResponse(responseNode, baseURL: baseURL) {
                result.append(davResponse)
            }
        }
        return result
    }
}

/// Containts path, url and attributes of a WebDAV file or resource.
public final class WebDavFileObject: FileObject {
    internal init(_ davResponse: DavResponse) {
        let href = davResponse.href
        let name = davResponse.prop["displayname"] ?? davResponse.href.lastPathComponent
        let relativePath = href.relativePath
        let path = relativePath.hasPrefix("/") ? relativePath : ("/" + relativePath)
        super.init(url: href, name: name, path: path)
        self.size = Int64(davResponse.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
        self.creationDate = davResponse.prop["creationdate"].flatMap { Date(rfcString: $0) }
        self.modifiedDate = davResponse.prop["getlastmodified"].flatMap { Date(rfcString: $0) }
        self.contentType = davResponse.prop["getcontenttype"].flatMap(ContentMIMEType.init(rawValue:)) ?? .stream
        self.isHidden = (Int(davResponse.prop["ishidden"] ?? "0") ?? 0) > 0
        self.isReadOnly = (Int(davResponse.prop["isreadonly"] ?? "0") ?? 0) > 0
        self.type = (self.contentType == .directory) ? .directory : .regular
        self.entryTag = davResponse.prop["getetag"]
    }
    
    /// MIME type of the file.
    open internal(set) var contentType: ContentMIMEType {
        get {
            return (allValues[.mimeTypeKey] as? String).flatMap(ContentMIMEType.init(rawValue:)) ?? .stream
        }
        set {
            allValues[.mimeTypeKey] = newValue.rawValue
        }
    }
    
    /// HTTP E-Tag, can be used to mark changed files.
    open internal(set) var entryTag: String? {
        get {
            return allValues[.entryTagKey] as? String
        }
        set {
            allValues[.entryTagKey] = newValue
        }
    }
    
    internal class func resourceKeyToDAVProp(_ key: URLResourceKey) -> String? {
        switch key {
        case URLResourceKey.fileSizeKey:
            return "getcontentlength"
        case URLResourceKey.creationDateKey:
            return "creationdate"
        case URLResourceKey.contentModificationDateKey:
            return "getlastmodified"
        case URLResourceKey.fileResourceTypeKey, URLResourceKey.mimeTypeKey:
            return "getcontenttype"
        case URLResourceKey.isHiddenKey:
            return "ishidden"
        case URLResourceKey.entryTagKey:
            return "getetag"
        case URLResourceKey.volumeTotalCapacityKey:
            // WebDAV doesn't have total capacity, but it's can be calculated via used capacity
            return "quota-used-bytes"
        case URLResourceKey.volumeAvailableCapacityKey:
            return "quota-available-bytes"
        default:
            return nil
        }
    }
    
    internal class func propString(_ keys: [URLResourceKey]) -> String {
        var propKeys = ""
        for item in keys {
            if let prop = WebDavFileObject.resourceKeyToDAVProp(item) {
                propKeys += "<D:prop><D:\(prop)/></D:prop>"
            }
        }
        if propKeys.isEmpty {
            propKeys = "<D:allprop/>"
        } else {
            propKeys += "<D:prop><D:resourcetype/></D:prop>"
        }
        return propKeys
    }
    
    internal class func xmlProp(_ keys: [URLResourceKey]) -> Data {
        return "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n\(WebDavFileObject.propString(keys))\n</D:propfind>".data(using: .utf8)!
    }
}

/// Error returned by WebDAV server when trying to access or do operations on a file or folder.
public struct FileProviderWebDavError: FileProviderHTTPError {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let serverDescription: String?
    /// URL of resource caused error.
    public let url: URL
}
