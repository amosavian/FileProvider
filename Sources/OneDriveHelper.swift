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
        var rpath = (URL(string:path)?.appendingPathComponent(name).absoluteString)!
        if rpath.hasPrefix("/") {
            _=rpath.characters.removeFirst()
        }
        let url = URL(string: rpath, relativeTo: baseURL) ?? URL(string: rpath)!
        
        super.init(url: url, name: name, path: rpath.removingPercentEncoding ?? path)
    }
    
    internal convenience init? (baseURL: URL?, drive: String, jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(baseURL: baseURL, drive: drive, json: json)
    }
    
    internal convenience init? (baseURL: URL?, drive: String, json: [String: AnyObject]) {
        guard let name = json["name"] as? String else { return nil }
        guard let path = (json["parentReference"] as? NSDictionary)?["path"] as? String else { return nil }
        var lPath = path.replacingOccurrences(of: "/drive/\(drive):", with: "/", options: .anchored, range: nil)
        lPath = lPath.replacingOccurrences(of: "/:", with: "", options: .anchored)
        lPath = lPath.replacingOccurrences(of: "//", with: "", options: .anchored)
        self.init(baseURL: baseURL, name: name, path: lPath)
        self.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.modifiedDate = Date(rfcString: json["lastModifiedDateTime"] as? String ?? "")
        self.creationDate = Date(rfcString: json["createdDateTime"] as? String ?? "")
        self.type = json["folder"] != nil ? .directory : .regular
        self.id = json["id"] as? String
        self.entryTag = json["eTag"] as? String
    }
    
    /// The document identifier is a value assigned by the OneDrive to a file.
    /// This value is used to identify the document regardless of where it is moved on a volume.
    /// The identifier persists across system restarts.
    open internal(set) var id: String? {
        get {
            return allValues[.documentIdentifierKey] as? String
        }
        set {
            allValues[.documentIdentifierKey] = newValue
        }
    }
    
    /// MIME type of file contents returned by OneDrive server.
    open internal(set) var contentType: String {
        get {
            return allValues[.mimeTypeKey] as? String ?? ""
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
}

// codebeat:disable[ARITY]
internal extension OneDriveFileProvider {
    func list(_ path: String, cursor: URL? = nil, prevContents: [OneDriveFileObject] = [], completionHandler: @escaping ((_ contents: [FileObject], _ cursor: String?, _ error: Error?) -> Void)) {
        let url = cursor ?? self.url(of: path, modifier: "children")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.set(httpAuthentication: credential, with: .oAuth2)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderOneDriveError?
            var files = prevContents
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderOneDriveError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let json = data?.deserializeJSON() {
                if let entries = json["value"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = OneDriveFileObject(baseURL: self.baseURL, drive: self.drive, json: entry) {
                            files.append(file)
                        }
                    }
                    let ncursor: URL? = (json["@odata.nextLink"] as? String).flatMap { URL(string: $0) }
                    let hasmore = ncursor != nil
                    if hasmore {
                        self.list(path, cursor: ncursor, prevContents: files, completionHandler: completionHandler)
                        return
                    }
                }
            }
            completionHandler(files, nil, responseError ?? error)
        })
        task.taskDescription = FileOperationType.fetch(path: path).json
        task.resume()
    }
    
    func search(_ startPath: String = "", query: String, recursive: Bool, next: URL? = nil, progress: Progress, foundItem: @escaping ((_ file: OneDriveFileObject) -> Void), completionHandler: @escaping ((_ error: Error?) -> Void)) {
        if progress.isCancelled {
            return
        }
        
        let url: URL
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let expanded = recursive ? "&expand=children" : ""
        url = next ?? self.url(of: startPath, modifier: "view.search?q=\(q)\(expanded)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.set(httpAuthentication: credential, with: .oAuth2)
        
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderOneDriveError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderOneDriveError(code: rCode, path: startPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let json = data?.deserializeJSON() {
                if let entries = json["value"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = OneDriveFileObject(baseURL: self.baseURL, drive: self.drive, json: entry) {
                            foundItem(file)
                        }
                    }
                    let next: URL? = (json["@odata.nextLink"] as? String).flatMap { URL(string: $0) }
                    if !progress.isCancelled, let next = next {
                        self.search(startPath, query: query, recursive: recursive, next: next, progress: progress, foundItem: foundItem, completionHandler: completionHandler)
                    } else {
                        completionHandler(responseError ?? error)
                    }
                    return
                }
            }
            completionHandler(responseError ?? error)
        })
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.resume()
    }
}
// codebeat:enable[ARITY]

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
