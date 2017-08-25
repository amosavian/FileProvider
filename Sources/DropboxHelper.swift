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
    public let errorDescription: String?
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
        self.serverTime = Date(rfcString: json["server_modified"] as? String ?? "")
        self.modifiedDate = Date(rfcString: json["client_modified"] as? String ?? "")
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
    /// The identifier persists across system restarts.
    open internal(set) var id: String? {
        get {
            return allValues[.documentIdentifierKey] as? String
        }
        set {
            allValues[.documentIdentifierKey] = newValue
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

// codebeat:disable[ARITY]
internal extension DropboxFileProvider {
    
    
    func list(_ path: String, cursor: String? = nil, prevContents: [DropboxFileObject] = [], recursive: Bool = false, session: URLSession? = nil, progress: Progress, progressHandler: ((_ contents: [FileObject], _ nextCursor: String?, _ error: Error?) -> Void)? = nil, completionHandler: @escaping ((_ contents: [FileObject], _ cursor: String?, _ error: Error?) -> Void)) {
        if progress.isCancelled { return }
        
        var requestDictionary = [String: AnyObject]()
        let url: URL
        if let cursor = cursor {
            url = URL(string: "files/list_folder/continue", relativeTo: apiURL)!
            requestDictionary["cursor"] = cursor as NSString?
        } else {
            url = URL(string: "files/list_folder", relativeTo: apiURL)!
            requestDictionary["path"] = correctPath(path) as NSString?
            requestDictionary["recursive"] = recursive as NSNumber?
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(httpContentType: .json)
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = (session ?? self.session).dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            var files = [DropboxFileObject]()
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let json = data?.deserializeJSON() {
                if let entries = json["entries"] as? [AnyObject] , entries.count > 0 {
                    files.reserveCapacity(entries.count)
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = DropboxFileObject(json: entry) {
                            files.append(file)
                            progress.totalUnitCount = Int64(files.count)
                        }
                    }
                    let ncursor = json["cursor"] as? String
                    let hasmore = (json["has_more"] as? NSNumber)?.boolValue ?? false
                    if hasmore && !progress.isCancelled {
                        progressHandler?(files, ncursor, responseError ?? error)
                        self.list(path, cursor: ncursor, prevContents: prevContents + files, progress: progress, completionHandler: completionHandler)
                        return
                    }
                }
            }
            progressHandler?(files, nil, responseError ?? error)
            completionHandler(prevContents + files, nil, responseError ?? error)
        })
        progress.cancellationHandler = { [weak task] in
            task?.cancel()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        task.taskDescription = FileOperationType.fetch(path: path).json
        task.resume()
    }
    
    func search(_ startPath: String = "", query: String, start: Int = 0, maxResultPerPage: Int = 25, maxResults: Int = -1, progress: Progress, foundItem:@escaping ((_ file: DropboxFileObject) -> Void), completionHandler: @escaping ((_ error: Error?) -> Void)) {
        if progress.isCancelled { return }
        
        let url = URL(string: "files/search", relativeTo: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.set(httpAuthentication: credential, with: .oAuth2)
        request.set(httpContentType: .json)
        var requestDictionary: [String: AnyObject] = ["path": startPath as NSString]
        requestDictionary["query"] = query as NSString
        requestDictionary["start"] = start as NSNumber
        requestDictionary["max_results"] = maxResultPerPage as NSNumber
        request.httpBody = Data(jsonDictionary: requestDictionary)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: startPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let json = data?.deserializeJSON() {
                if let entries = json["matches"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = DropboxFileObject(json: entry) {
                            foundItem(file)
                            progress.completedUnitCount += 1
                        }
                    }
                    let rstart = json["start"] as? Int
                    let hasmore = (json["more"] as? NSNumber)?.boolValue ?? false
                    if hasmore && !progress.isCancelled, let rstart = rstart {
                        self.search(startPath, query: query, start: rstart + entries.count, maxResultPerPage: maxResultPerPage, progress: progress, foundItem: foundItem, completionHandler: completionHandler)
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
