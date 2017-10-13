//
//  OneDriveHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

/// Error returned by OneDrive server when trying to access or do operations on a file or folder.
public struct FileProviderOneDriveError: FileProviderHTTPError {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let errorDescription: String?
}

/// Containts path, url and attributes of a OneDrive file or resource.
public final class OneDriveFileObject: FileObject {
    internal init(baseURL: URL?, name: String, path: String) {
        let rpath = (URL(string:path)?.appendingPathComponent(name).absoluteString)!.replacingOccurrences(of: "/", with: "", options: .anchored)
        let url = URL(string: rpath, relativeTo: baseURL) ?? URL(string: rpath)!
        
        super.init(url: url, name: name, path: rpath.removingPercentEncoding ?? path)
    }
    
    internal convenience init? (baseURL: URL?, route: OneDriveFileProvider.Route, jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(baseURL: baseURL, route: route, json: json)
    }
    
    internal convenience init? (baseURL: URL?, route: OneDriveFileProvider.Route, json: [String: AnyObject]) {
        guard let name = json["name"] as? String else { return nil }
        guard let path = json["parentReference"]?["path"] as? String else { return nil }
        var lPath = path.replacingOccurrences(of: route.drivePath, with: "", options: .anchored, range: nil)
        lPath = lPath.replacingOccurrences(of: "/:", with: "", options: .anchored)
        lPath = lPath.replacingOccurrences(of: "//", with: "", options: .anchored)
        self.init(baseURL: baseURL, name: name, path: lPath)
        self.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.childrensCount = json["folder"]?["childCount"] as? Int
        self.modifiedDate = (json["lastModifiedDateTime"] as? String).flatMap { Date(rfcString: $0) }
        self.creationDate = (json["createdDateTime"] as? String).flatMap { Date(rfcString: $0) }
        self.type = json["folder"] != nil ? .directory : .regular
        self.contentType = json["file"]?["mimeType"] as? String ?? "application/octet-stream"
        self.id = json["id"] as? String
        self.entryTag = json["eTag"] as? String
        let hashes = json["file"]?["hashes"] as? NSDictionary
        // checks for both sha1 or quickXor. First is available in personal drives, second in business one.
        self.hash = (hashes?["sha1Hash"] as? String) ?? (hashes?["quickXorHash"] as? String)
    }
    
    /// The document identifier is a value assigned by the OneDrive to a file.
    /// This value is used to identify the document regardless of where it is moved on a volume.
    open internal(set) var id: String? {
        get {
            return allValues[.fileResourceIdentifierKey] as? String
        }
        set {
            allValues[.fileResourceIdentifierKey] = newValue
        }
    }
    
    /// MIME type of file contents returned by OneDrive server.
    open internal(set) var contentType: String {
        get {
            return allValues[.mimeTypeKey] as? String ?? "application/octet-stream"
        }
        set {
            allValues[.mimeTypeKey] = newValue
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
    
    /// Calculated hash from OneDrive server. Hex string SHA1 in personal or Base65 string [QuickXOR](https://dev.onedrive.com/snippets/quickxorhash.htm) in business drives.
    open internal(set) var hash: String? {
        get {
            return allValues[.documentIdentifierKey] as? String
        }
        set {
            allValues[.documentIdentifierKey] = newValue
        }
    }
}

internal extension OneDriveFileProvider {
    static let dateFormatter = DateFormatter()
    static let decimalFormatter = NumberFormatter()
    
    func mapMediaInfo(_ json: [String: Any]) -> (dictionary: [String: Any], keys: [String]) {
        
        func spaceCamelCase(_ text: String) -> String {
            var newString: String = ""
            
            let upperCase = CharacterSet.uppercaseLetters
            for scalar in text.unicodeScalars {
                if upperCase.contains(scalar) {
                    newString.append(" ")
                }
                let character = Character(scalar)
                newString.append(character)
            }
            
            return newString.capitalized
        }
        
        var dic = [String: Any]()
        var keys = [String]()
        
        func add(key: String, value: Any?) {
            if let value = value {
                keys.append(key)
                dic[key] = value
            }
        }
        
        if let parent = json["image"] as? [String: Any] ?? json["video"] as? [String: Any], let height = parent["height"] as? UInt64, let width = parent["width"] as? UInt64 {
            add(key: "Dimensions", value: "\(width)x\(height)")
        }
        if let location = json["location"] as? [String: Any], let latitude = location["latitude"] as? Double, let longitude = location["longitude"] as? Double {
            OneDriveFileProvider.decimalFormatter.numberStyle = .decimal
            OneDriveFileProvider.decimalFormatter.maximumFractionDigits = 5
            let latStr = OneDriveFileProvider.decimalFormatter.string(from: NSNumber(value: latitude))!
            let longStr = OneDriveFileProvider.decimalFormatter.string(from: NSNumber(value: longitude))!
            add(key: "Location", value: "\(latStr), \(longStr)")
        }
        if let parent = json["image"] as? [String: Any] ?? json["video"] as? [String: Any], let duration = parent["duration"] as? UInt64 {
            add(key: "Duration", value: (TimeInterval(duration) / 1000).formatshort)
        }
        if let timeTakenStr = json["takenDateTime"] as? String, let timeTaken = Date(rfcString: timeTakenStr) {
            OneDriveFileProvider.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            add(key: "Date taken", value:  OneDriveFileProvider.dateFormatter.string(from: timeTaken))
        }
        
        if let photo = json["photo"] as? [String: Any] {
            add(key: "Device make", value: photo["cameraMake"] as? String)
            add(key: "Device model", value: photo["cameraModel"] as? String)
            add(key: "focalLength", value: photo["focalLength"] as? Double)
            add(key: "fNumber", value: photo["fNumber"] as? Double)
            if let expNom = photo["exposureNumerator"] as? Double, let expDen = photo["exposureDenominator"] as? Double {
                add(key: "Exposure time", value: "\(Int(expNom))/\(Int(expDen))")
            }
            add(key: "ISO speed", value: photo["iso"] as? Int64)
        }
        
        if let audio = json["audio"] as? [String: Any] {
            for (key, value) in audio {
                if key == "bitrate" || key == "isVariableBitrate" { continue }
                let casedKey = spaceCamelCase(key)
                add(key: casedKey, value: value)
            }
        }
        
        add(key: "Bitrate", value: (json["video"] as? NSDictionary)?["bitrate"] as? Int)
        
        return (dic, keys)
    }
}
