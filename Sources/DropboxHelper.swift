//
//  DropboxHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/// Error returned by Dropbox server when trying to access or do operations on a file or folder.
public struct FileProviderDropboxError: FileProviderHTTPError {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let serverDescription: String?
}

/// Containts path, url and attributes of a Dropbox file or resource.
public final class DropboxFileObject: FileObject {
    internal convenience init? (jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(json: json)
    }
    
    internal init? (json: [String: AnyObject]) {
        var json = json
        if json["name"] == nil, let metadata = json["metadata"] as? [String: AnyObject] {
            json = metadata
        }
        guard let name = json["name"] as? String else { return nil }
        guard let path = json["path_display"] as? String else { return nil }
        super.init(url: nil, name: name, path: path)
        self.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.serverTime =  (json["server_modified"] as? String).flatMap(Date.init(rfcString:))
        self.modifiedDate = (json["client_modified"] as? String).flatMap(Date.init(rfcString:))
        self.type = (json[".tag"] as? String) == "folder" ? .directory : .regular
        self.isReadOnly = (json["sharing_info"]?["read_only"] as? NSNumber)?.boolValue ?? false
        self.id = json["id"] as? String
        self.rev = json["rev"] as? String
    }
    
    /// The time contents of file has been modified on server, returns nil if not set
    open internal(set) var serverTime: Date? {
        get {
            return allValues[.serverDateKey] as? Date
        }
        set {
            allValues[.serverDateKey] = newValue
        }
    }
    
    /// The document identifier is a value assigned by the Dropbox to a file.
    /// This value is used to identify the document regardless of where it is moved on a volume.
    open internal(set) var id: String? {
        get {
            return allValues[.fileResourceIdentifierKey] as? String
        }
        set {
            allValues[.fileResourceIdentifierKey] = newValue
        }
    }
    
    /// The revision of file, which changes when a file contents are modified.
    /// Changes to attributes or other file metadata do not change the identifier.
    open internal(set) var rev: String? {
        get {
            return allValues[.generationIdentifierKey] as? String
        }
        set {
            allValues[.generationIdentifierKey] = newValue
        }
    }
}

internal extension DropboxFileProvider {
    internal func correctPath(_ path: String?) -> String? {
        guard let path = path else { return nil }
        if path.hasPrefix("id:") || path.hasPrefix("rev:") {
            return path
        }
        var p = path.hasPrefix("/") ? path : "/" + path
        if p.hasSuffix("/") {
            p.remove(at: p.index(before:p.endIndex))
        }
        return p
    }
    
    internal func listRequest(path: String, queryStr: String? = nil, recursive: Bool = false) -> ((_ token: String?) -> URLRequest?) {
        if let queryStr = queryStr {
            return { [weak self] (token) -> URLRequest? in
                guard let `self` = self else { return nil }
                let url = URL(string: "files/search", relativeTo: self.apiURL)!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(authentication: self.credential, with: .oAuth2)
                request.setValue(contentType: .json)
                var requestDictionary: [String: AnyObject] = ["path": self.correctPath(path) as NSString!]
                requestDictionary["query"] = queryStr as NSString
                requestDictionary["start"] = NSNumber(value: (token.flatMap( { Int($0) } ) ?? 0))
                request.httpBody = Data(jsonDictionary: requestDictionary)
                return request
            }
        } else {
            return { [weak self] (token) -> URLRequest? in
                guard let `self` = self else { return nil }
                var requestDictionary = [String: AnyObject]()
                let url: URL
                if let token = token {
                    url = URL(string: "files/list_folder/continue", relativeTo: self.apiURL)!
                    requestDictionary["cursor"] = token as NSString?
                } else {
                    url = URL(string: "files/list_folder", relativeTo: self.apiURL)!
                    requestDictionary["path"] = self.correctPath(path) as NSString?
                    requestDictionary["recursive"] = NSNumber(value: recursive)
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(authentication: self.credential, with: .oAuth2)
                request.setValue(contentType: .json)
                request.httpBody = Data(jsonDictionary: requestDictionary)
                return request
            }
        }
    }
}

internal extension DropboxFileProvider {
    static let dateFormatter = DateFormatter()
    static let decimalFormatter = NumberFormatter()
    
    func mapMediaInfo(_ json: [String: Any]) -> (dictionary: [String: Any], keys: [String]) {
        var dic = [String: Any]()
        var keys = [String]()
        if let dimensions = json["dimensions"] as? [String: Any], let height = dimensions["height"] as? UInt64, let width = dimensions["width"] as? UInt64 {
            keys.append("Dimensions")
            dic["Dimensions"] = "\(width)x\(height)"
        }
        if let location = json["location"] as? [String: Any], let latitude = location["latitude"] as? Double, let longitude = location["longitude"] as? Double {
            
            DropboxFileProvider.decimalFormatter.numberStyle = .decimal
            DropboxFileProvider.decimalFormatter.maximumFractionDigits = 5
            keys.append("Location")
            let latStr = DropboxFileProvider.decimalFormatter.string(from: NSNumber(value: latitude))!
            let longStr = DropboxFileProvider.decimalFormatter.string(from: NSNumber(value: longitude))!
            dic["Location"] = "\(latStr), \(longStr)"
        }
        if let timeTakenStr = json["time_taken"] as? String, let timeTaken = Date(rfcString: timeTakenStr) {
            keys.append("Date taken")
            DropboxFileProvider.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dic["Date taken"] = DropboxFileProvider.dateFormatter.string(from: timeTaken)
        }
        if let duration = json["duration"] as? UInt64 {
            keys.append("Duration")
            dic["Duration"] = TimeInterval(duration).formatshort
        }
        return (dic, keys)
    }
}
