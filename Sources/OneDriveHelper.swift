//
//  OneDriveHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

public struct FileProviderOneDriveError: Error, CustomStringConvertible {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let errorDescription: String?
    
    public var description: String {
        return code.description
    }
}

public final class OneDriveFileObject: FileObject {
    internal init(name: String, path: String) {
        super.init(absoluteURL: URL(string: path), name: name, path: path)
    }
    
    
    open internal(set) var id: String? {
        get {
            return allValues["NSURLDocumentIdentifyKey"] as? String
        }
        set {
            allValues["NSURLDocumentIdentifyKey"] = newValue
        }
    }
    
    open internal(set) var contentType: String {
        get {
            return allValues["NSURLContentTypeKey"] as? String ?? ""
        }
        set {
            allValues["NSURLContentTypeKey"] = newValue
        }
    }
    
    open internal(set) var entryTag: String? {
        get {
            return allValues["NSURLEntryTagKey"] as? String
        }
        set {
            allValues["NSURLEntryTagKey"] = newValue
        }
    }
}

// codebeat:disable[ARITY]
internal extension OneDriveFileProvider {
    func list(_ path: String, cursor: String? = nil, prevContents: [OneDriveFileObject] = [], completionHandler: @escaping ((_ contents: [FileObject], _ cursor: String?, _ error: Error?) -> Void)) {
        let url: URL
        if let cursor = cursor {
            url = URL(string: cursor)!
        } else {
            url = URL(string: escaped(path: path), relativeTo: driveURL)!
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderOneDriveError?
            var files = prevContents
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderOneDriveError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let data = data, let jsonStr = String(data: data, encoding: .utf8) {
                let json = jsonToDictionary(jsonStr)
                if let entries = json?["value"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = self.mapToFileObject(entry) {
                            files.append(file)
                        }
                    }
                    let ncursor = json?["@odata.nextLink"] as? String
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
    
    func upload_simple(_ targetPath: String, data: Data, modifiedDate: Date = Date(), overwrite: Bool, operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        assert(data.count < 100*1024*1024, "Maximum size of allowed size to upload is 100MB")
        let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
        let url = URL(string: escaped(path: targetPath) + ":/content" + queryStr, relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderOneDriveError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderOneDriveError(code: rCode, path: targetPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.create(path: targetPath), error: responseError ?? error)
        })
        task.taskDescription = operation.json
        task.resume()
        return RemoteOperationHandle(operationType: operation, tasks: [task])
    }
    
    func upload_simple(_ targetPath: String, localFile: URL, modifiedDate: Date = Date(), overwrite: Bool, operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
        let url = URL(string: escaped(path: targetPath) + ":/content" + queryStr, relativeTo: driveURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: localFile, completionHandler: { (data, response, error) in
            var responseError: FileProviderOneDriveError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderOneDriveError(code: rCode, path: targetPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.create(path: targetPath), error: responseError ?? error)
        })
        task.taskDescription = operation.json
        task.resume()
        return RemoteOperationHandle(operationType: operation, tasks: [task])
    }
    
    func search(_ startPath: String = "", query: String, next: String? = nil, foundItem:@escaping ((_ file: OneDriveFileObject) -> Void), completionHandler: @escaping ((_ error: Error?) -> Void)) {
        let url: URL
        if let next = next {
            url = URL(string: next)!
        } else if self.escaped(path: startPath) == "" {
            url = URL(string: "/drive/\(drive)/view.search?q=\(query)", relativeTo: baseURL)!
        } else {
            url = URL(string: "\(escaped(path: startPath))/view.search?q=\(query)", relativeTo: driveURL)!
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderOneDriveError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderOneDriveError(code: rCode, path: startPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let data = data, let jsonStr = String(data: data, encoding: .utf8) {
                let json = jsonToDictionary(jsonStr)
                if let entries = json?["value"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = self.mapToFileObject(entry) {
                            foundItem(file)
                        }
                    }
                    let next = json?["@odata.nextLink"] as? String
                    let hasmore = next != nil
                    if hasmore, let next = next {
                        self.search(startPath, query: query, next: next, foundItem: foundItem, completionHandler: completionHandler)
                    } else {
                        completionHandler(responseError ?? error)
                    }
                    return
                }
            }
            completionHandler(responseError ?? error)
        }) 
        task.resume()
    }
}
// codebeat:enable[ARITY]

internal extension OneDriveFileProvider {
    func mapToFileObject(_ jsonStr: String) -> OneDriveFileObject? {
        guard let json = jsonToDictionary(jsonStr) else { return nil }
        return self.mapToFileObject(json)
    }
    
    func mapToFileObject(_ json: [String: AnyObject]) -> OneDriveFileObject? {
        guard let name = json["name"] as? String else { return nil }
        guard let path = (json["parentReference"] as? NSDictionary)?["path"] as? String else { return nil }
        let lPath = path.replacingOccurrences(of: "/drive/\(drive):", with: "/", options: .anchored, range: nil)
        let fileObject = OneDriveFileObject(name: name, path: lPath)
        if let webURL = json["webUrl"] as? String, let absolluteURL = URL(string: webURL) {
            fileObject.absoluteURL = absolluteURL
        }
        fileObject.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        fileObject.modifiedDate = resolve(dateString: json["lastModifiedDateTime"] as? String ?? "")
        fileObject.creationDate = resolve(dateString: json["createdDateTime"] as? String ?? "")
        fileObject.type = (json["folder"] as? String) != nil ? .directory : .regular
        fileObject.id = json["id"] as? String
        fileObject.entryTag = json["eTag"] as? String
        return fileObject
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
        
        if let parent = json["image"] as? [String: Any] ?? json["video"] as? [String: Any], let height = parent["height"] as? UInt64, let width = parent["width"] as? UInt64 {
            keys.append("Dimensions")
            dic["Dimensions"] = "\(width)x\(height)"
        }
        if let location = json["location"] as? [String: Any], let latitude = location["latitude"] as? Double, let longitude = location["longitude"] as? Double {
            
            OneDriveFileProvider.decimalFormatter.numberStyle = .decimal
            OneDriveFileProvider.decimalFormatter.maximumFractionDigits = 5
            keys.append("Location")
            let latStr = OneDriveFileProvider.decimalFormatter.string(from: NSNumber(value: latitude))
            let longStr = OneDriveFileProvider.decimalFormatter.string(from: NSNumber(value: longitude))
            dic["Location"] = "\(latStr), \(longStr)"
        }
        if let parent = json["image"] as? [String: Any] ?? json["video"] as? [String: Any], let duration = parent["duration"] as? UInt64 {
            keys.append("Duration")
            dic["Duration"] = OneDriveFileProvider.formatshort(interval: TimeInterval(duration) / 1000)
        }
        if let timeTakenStr = json["takenDateTime"] as? String, let timeTaken = self.resolve(dateString: timeTakenStr) {
            keys.append("Date taken")
            OneDriveFileProvider.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dic["Date taken"] = OneDriveFileProvider.dateFormatter.string(from: timeTaken)
        }
        
        if let photo = json["photo"] as? [String: Any] {
            if let devicemake = photo["cameraMake"] as? String {
                keys.append("Device make")
                dic["Device make"] = devicemake
            }
            if let devicemodel = photo["cameraModel"] as? String {
                keys.append("Device model")
                dic["Device model"] = devicemodel
            }
            if let focallen = photo["focalLength"] as? Double {
                keys.append("Focal length")
                dic["Focal length"] = focallen
            }
            if let fnum = photo["fNumber"] as? Double {
                keys.append("F number")
                dic["F number"] = fnum
            }
            if let expNom = photo["exposureNumerator"] as? Double, let expDen = photo["exposureDenominator"] as? Double {
                keys.append("Exposure time")
                dic["Exposure time"] = "\(Int(expNom))/\(Int(expDen))"
            }
            if let iso = photo["iso"] as? Int64 {
                keys.append("ISO speed")
                dic["ISO speed"] = iso
            }

        }
        
        if let audio = json["audio"] as? [String: Any] {
            for (key, value) in audio {
                if key == "bitrate" || key == "isVariableBitrate" { continue }
                let casedKey = spaceCamelCase(key)
                keys.append(casedKey)
                dic[casedKey] = value
            }
        }
        
        if let video = json["video"] as? [String: Any] {
            if let bitRate = video["bitrate"] as? Int {
                keys.append("Bitrate")
                dic["Bitrate"] = bitRate
            }
        }
        
        return (dic, keys)
    }
    
    func delegateNotify(_ operation: FileOperationType, error: Error?) {
        DispatchQueue.main.async(execute: {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
}
