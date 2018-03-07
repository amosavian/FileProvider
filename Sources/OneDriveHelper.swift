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
    public let serverDescription: String?
}

/// Containts path, url and attributes of a OneDrive file or resource.
public final class OneDriveFileObject: FileObject {
    internal convenience init? (baseURL: URL?, route: OneDriveFileProvider.Route, jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(baseURL: baseURL, route: route, json: json)
    }
    
    internal init? (baseURL: URL?, route: OneDriveFileProvider.Route, json: [String: AnyObject]) {
        guard let name = json["name"] as? String else { return nil }
        guard let id = json["id"] as? String else { return nil }
        let path: String
        if let refpath = json["parentReference"]?["path"] as? String {
            let parentPath: String
            if let colonIndex = refpath.index(of: ":") {
                #if swift(>=4.0)
                parentPath = String(refpath[refpath.index(after: colonIndex)...])
                #else
                parentPath = refpath.substring(from: refpath.index(after: colonIndex))
                #endif
            } else {
                parentPath = refpath
            }
             path = (parentPath as NSString).appendingPathComponent(name)
        } else {
            path = "id:\(id)"
        }
        let url = baseURL.map { OneDriveFileObject.url(of: path, modifier: nil, baseURL: $0, route: route) }
        super.init(url: url, name: name, path: path)
        self.id = id
        self.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.childrensCount = json["folder"]?["childCount"] as? Int
        self.modifiedDate = (json["lastModifiedDateTime"] as? String).flatMap { Date(rfcString: $0) }
        self.creationDate = (json["createdDateTime"] as? String).flatMap { Date(rfcString: $0) }
        self.type = json["folder"] != nil ? .directory : .regular
        self.contentType = (json["file"]?["mimeType"] as? String).flatMap(ContentMIMEType.init(rawValue:)) ?? .stream
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
    
    /// Calculated hash from OneDrive server. Hex string SHA1 in personal or Base65 string [QuickXOR](https://dev.onedrive.com/snippets/quickxorhash.htm) in business drives.
    open internal(set) var hash: String? {
        get {
            return allValues[.documentIdentifierKey] as? String
        }
        set {
            allValues[.documentIdentifierKey] = newValue
        }
    }
    
    static func url(of path: String, modifier: String?, baseURL: URL, route: OneDriveFileProvider.Route) -> URL {
        var url: URL = baseURL
        let isId = path.hasPrefix("id:")
        var rpath: String = path.replacingOccurrences(of: "id:", with: "", options: .anchored)
        
        //url.appendPathComponent("v1.0")
        url.appendPathComponent(route.drivePath)
        
        if rpath.isEmpty {
            url.appendPathComponent("root")
        } else if isId {
            url.appendPathComponent("items")
        } else {
            url.appendPathComponent("root:")
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
    
    static func relativePathOf(url: URL, baseURL: URL?, route: OneDriveFileProvider.Route) -> String {
        let base = baseURL?.appendingPathComponent(route.drivePath).path ?? ""
        
        let crudePath = url.path.replacingOccurrences(of: base, with: "", options: .anchored)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        switch crudePath {
        case hasPrefix("items/"):
            let components = (crudePath as NSString).pathComponents
            return components.dropFirst().first.map { "id:\($0)" } ?? ""
        case hasPrefix("root:"):
            return crudePath.components(separatedBy: ":").dropFirst().first ?? ""
        default:
            return ""
        }
    }
}

internal extension OneDriveFileProvider {
    internal func upload_multipart_data(_ targetPath: String, data: Data, operation: FileOperationType,
                                        overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        return self.upload_multipart(targetPath, operation: operation, size: Int64(data.count), overwrite: overwrite, dataProvider: {
            let range = $0.clamped(to: 0..<Int64(data.count))
            return data[range]
        }, completionHandler: completionHandler)
    }
    
    internal func upload_multipart_file(_ targetPath: String, file: URL, operation: FileOperationType,
                                        overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        // upload task can't handle uploading file
        
        return self.upload_multipart(targetPath, operation: operation, size: file.fileSize, overwrite: overwrite, dataProvider: { range in
            guard let handle = FileHandle(forReadingAtPath: file.path) else {
                throw self.cocoaError(targetPath, code: .fileNoSuchFile)
            }
            
            defer {
                handle.closeFile()
            }
            
            let offset = range.lowerBound
            handle.seek(toFileOffset: UInt64(offset))
            guard Int64(handle.offsetInFile) == offset else {
                throw self.cocoaError(targetPath, code: .fileReadTooLarge)
            }
            
            return handle.readData(ofLength: range.count)
        }, completionHandler: completionHandler)
    }
    
    private func upload_multipart(_ targetPath: String, operation: FileOperationType, size: Int64, overwrite: Bool,
                                  dataProvider: @escaping (Range<Int64>) throws -> Data, completionHandler: SimpleCompletionHandler) -> Progress? {
        guard size > 0 else { return nil }
        
        let progress = Progress(totalUnitCount: size)
        progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
        progress.kind = .file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        
        let createURL = self.url(of: targetPath, modifier: "createUploadSession")
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue(authentication: self.credential, with: .oAuth2)
        createRequest.setValue(contentType: .json)
        if overwrite {
            createRequest.httpBody = Data(jsonDictionary: ["item": ["@microsoft.graph.conflictBehavior": "replace"] as NSDictionary])
        } else {
            createRequest.httpBody = Data(jsonDictionary: ["item": ["@microsoft.graph.conflictBehavior": "fail"] as NSDictionary])
        }
        let createSessionTask = session.dataTask(with: createRequest) { (data, response, error) in
            if let error = error {
                completionHandler?(error)
                return
            }
            
            if let data = data, let json = data.deserializeJSON(),
                let uploadURL = (json["uploadUrl"] as? String).flatMap(URL.init(string:)) {
                self.upload_multipart(url: uploadURL, operation: operation, size: size, progress: progress, dataProvider: dataProvider, completionHandler: completionHandler)
            }
        }
        createSessionTask.resume()
        
        return progress
    }
    
    private func upload_multipart(url: URL, operation: FileOperationType, size: Int64, range: Range<Int64>? = nil, uploadedSoFar: Int64 = 0,
                                  progress: Progress, dataProvider: @escaping (Range<Int64>) throws -> Data, completionHandler: SimpleCompletionHandler) {
        guard !progress.isCancelled else { return }
        var progress = progress
        
        let maximumSize: Int64 = 10_485_760 // Recommended by OneDrive documentations and divides evenly by 320 KiB, max 60MiB.
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(authentication: self.credential, with: .oAuth2)
        
        let finalRange: Range<Int64>
        if let range = range {
            if range.count > maximumSize {
                finalRange = range.lowerBound..<(range.upperBound + maximumSize)
            } else {
                finalRange = range
            }
        } else {
            finalRange = 0..<min(maximumSize, size)
        }
        request.setValue(contentRange: finalRange, totalBytes: size)
        
        let data: Data
        do {
            data = try dataProvider(finalRange)
        } catch {
            dispatch_queue.async {
                completionHandler?(error)
            }
            self.delegateNotify(operation, error: error)
            return
        }
        let task = session.uploadTask(with: request, from: data)
        
        var dictionary: [String: AnyObject] = ["type": operation.description as NSString]
        dictionary["source"] = operation.source as NSString?
        dictionary["dest"] = operation.destination as NSString?
        dictionary["uploadedBytes"] = uploadedSoFar as NSNumber
        dictionary["totalBytes"] = data.count as NSNumber
        task.taskDescription = String(jsonDictionary: dictionary)
        task.addObserver(self.sessionDelegate!, forKeyPath: #keyPath(URLSessionTask.countOfBytesSent), options: .new, context: &progress)
        progress.cancellationHandler = { [weak task, weak self] in
            task?.cancel()
            var deleteRequest = URLRequest(url: url)
            deleteRequest.httpMethod = "DELETE"
            self?.session.dataTask(with: deleteRequest).resume()
        }
        progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
        
        var allData = Data()
        dataCompletionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { data in
            allData.append(data)
        }
        // We retain self here intentionally to allow resuming upload, This behavior may change anytime!
        completionHandlersForTasks[session.sessionDescription!]?[task.taskIdentifier] = { [weak task] error in
            if let error = error {
                progress.cancel()
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
                return
            }
            
            guard let json = allData.deserializeJSON() else {
                let error = URLError(.badServerResponse, userInfo: [NSURLErrorKey: url, NSURLErrorFailingURLErrorKey: url, NSURLErrorFailingURLStringErrorKey: url.absoluteString])
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
                return
            }
            
            if let _ = json["error"] {
                let code = ((task?.response as? HTTPURLResponse)?.statusCode).flatMap(FileProviderHTTPErrorCode.init(rawValue:)) ?? .badRequest
                let error = self.serverError(with: code, path: self.relativePathOf(url: url), data: allData)
                completionHandler?(error)
                self.delegateNotify(operation, error: error)
                return
            }
            
            if let ranges = json["nextExpectedRanges"] as? [String], let firstRange = ranges.first {
                let uploaded = uploadedSoFar + Int64(finalRange.count)
                let comp = firstRange.components(separatedBy: "-")
                let lower = comp.first.flatMap(Int64.init) ?? uploaded
                let upper = comp.dropFirst().first.flatMap(Int64.init) ?? Int64.max
                let range = Range<Int64>(uncheckedBounds: (lower: lower, upper: upper))
                self.upload_multipart(url: url, operation: operation, size: size, range: range, uploadedSoFar: uploaded, progress: progress,
                                      dataProvider: dataProvider, completionHandler: completionHandler)
                return
            }
            
            if let _ = json["id"] as? String {
                completionHandler?(nil)
                self.delegateNotify(operation)
            }
        }
        
        task.resume()
    }
    
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
                var value = value
                if key == "bitrate" || key == "isVariableBitrate" { continue }
                let casedKey = spaceCamelCase(key)
                switch casedKey {
                case "Duration":
                    value = (value as? Int64).map { (TimeInterval($0) / 1000).formatshort } as Any
                case "Bitrate":
                    value = (value as? Int64).map { "\($0)kbps" } as Any
                default:
                    break
                }
                add(key: casedKey, value: value)
            }
        }
        
        add(key: "Bitrate", value: (json["video"] as? NSDictionary)?["bitrate"] as? Int)
        
        return (dic, keys)
    }
}
