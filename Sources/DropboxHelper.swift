//
//  DropboxHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian on 5/18/95.
//
//

import Foundation

public struct FileProviderDropboxError: Error, CustomStringConvertible {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let errorDescription: String?
    
    public var description: String {
        return code.description
    }
}

public final class DropboxFileObject: FileObject {
    internal init(name: String, path: String) {
        super.init(absoluteURL: URL(string: path), name: name, path: path)
    }
    
    open internal(set) var serverTime: Date? {
        get {
            return allValues["NSURLServerDateKey"] as? Date
        }
        set {
            allValues["NSURLServerDateKey"] = newValue
        }
    }
    
    open internal(set) var id: String? {
        get {
            return allValues["NSURLDropboxDocumentIdentifyKey"] as? String
        }
        set {
            allValues["NSURLDropboxDocumentIdentifyKey"] = newValue
        }
    }
    
    open internal(set) var rev: String? {
        get {
            return allValues[URLResourceKey.generationIdentifierKey.rawValue] as? String
        }
        set {
            allValues[URLResourceKey.generationIdentifierKey.rawValue] = newValue
        }
    }
}

 // codebeat:disable[ARITY]
internal extension DropboxFileProvider {
    func list(_ path: String, cursor: String? = nil, prevContents: [DropboxFileObject] = [], recursive: Bool = false, completionHandler: @escaping ((_ contents: [FileObject], _ cursor: String?, _ error: Error?) -> Void)) {
        var requestDictionary = [String: AnyObject]()
        let url: URL
        if let cursor = cursor {
            url = URL(string: "https://api.dropboxapi.com/2/files/list_folder/continue")!
            requestDictionary["cursor"] = cursor as NSString?
        } else {
            url = URL(string: "https://api.dropboxapi.com/2/files/list_folder")!
            requestDictionary["path"] = correctPath(path) as NSString?
            requestDictionary["recursive"] = recursive as NSNumber?
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            var files = prevContents
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let data = data, let jsonStr = String(data: data, encoding: .utf8) {
                let json = jsonToDictionary(jsonStr)
                if let entries = json?["entries"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = self.mapToFileObject(entry) {
                            files.append(file)
                        }
                    }
                    let ncursor = json?["cursor"] as? String
                    let hasmore = (json?["has_more"] as? NSNumber)?.boolValue ?? false
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
        assert(data.count < 150*1024*1024, "Maximum size of allowed size to upload is 150MB")
        var requestDictionary = [String: Any]()
        let url: URL
        url = URL(string: "https://content.dropboxapi.com/2/files/upload")!
        requestDictionary["path"] = correctPath(targetPath) as NSString?
        requestDictionary["mode"] = (overwrite ? "overwrite" : "add") as NSString
        requestDictionary["client_modified"] = string(from:modifiedDate)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(dictionaryToJSON(requestDictionary as [String : AnyObject]), forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: targetPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.create(path: targetPath), error: responseError ?? error)
        })
        task.taskDescription = operation.json
        task.resume()
        return RemoteOperationHandle(operationType: operation, tasks: [task])
    }
    
    func upload_simple(_ targetPath: String, localFile: URL, modifiedDate: Date = Date(), overwrite: Bool, operation: FileOperationType, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        var requestDictionary = [String: Any]()
        let url: URL
        url = URL(string: "https://content.dropboxapi.com/2/files/upload")!
        requestDictionary["path"] = correctPath(targetPath) as NSString?
        requestDictionary["mode"] = (overwrite ? "overwrite" : "add") as NSString
        requestDictionary["client_modified"] = string(from:modifiedDate)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(dictionaryToJSON(requestDictionary as [String : AnyObject]), forHTTPHeaderField: "Dropbox-API-Arg")
        let task = session.uploadTask(with: request, fromFile: localFile, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: targetPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            completionHandler?(responseError ?? error)
            self.delegateNotify(.create(path: targetPath), error: responseError ?? error)
        })
        task.taskDescription = operation.json
        task.resume()
        return RemoteOperationHandle(operationType: operation, tasks: [task])
    }
    
    func search(_ startPath: String = "", query: String, start: Int = 0, maxResultPerPage: Int = 25, maxResults: Int = -1, foundItem:@escaping ((_ file: DropboxFileObject) -> Void), completionHandler: @escaping ((_ error: Error?) -> Void)) {
        let url = URL(string: "https://api.dropboxapi.com/2/files/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestDictionary: [String: AnyObject] = ["path": startPath as NSString]
        requestDictionary["query"] = query as NSString
        requestDictionary["start"] = start as NSNumber
        requestDictionary["max_results"] = maxResultPerPage as NSNumber
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: .utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: startPath, errorDescription: String(data: data ?? Data(), encoding: .utf8))
            }
            if let data = data, let jsonStr = String(data: data, encoding: .utf8) {
                let json = jsonToDictionary(jsonStr)
                if let entries = json?["matches"] as? [AnyObject] , entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = self.mapToFileObject(entry) {
                            foundItem(file)
                        }
                    }
                    let rstart = json?["start"] as? Int
                    let hasmore = (json?["more"] as? NSNumber)?.boolValue ?? false
                    if hasmore, let rstart = rstart {
                        self.search(startPath, query: query, start: rstart + entries.count, maxResultPerPage: maxResultPerPage, foundItem: foundItem, completionHandler: completionHandler)
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

internal extension DropboxFileProvider {
    func mapToFileObject(_ jsonStr: String) -> DropboxFileObject? {
        guard let json = jsonToDictionary(jsonStr) else { return nil }
        return self.mapToFileObject(json)
    }
    
    func mapToFileObject(_ json: [String: AnyObject]) -> DropboxFileObject? {
        guard let name = json["name"] as? String else { return nil }
        guard let path = json["path_display"] as? String else { return nil }
        let fileObject = DropboxFileObject(name: name, path: path)
        fileObject.size = (json["size"] as? NSNumber)?.int64Value ?? -1
        fileObject.serverTime = resolve(dateString: json["server_modified"] as? String ?? "")
        fileObject.modifiedDate = resolve(dateString: json["client_modified"] as? String ?? "")
        fileObject.type = (json[".tag"] as? String) == "folder" ? .directory : .regular
        fileObject.isReadOnly = (json["sharing_info"]?["read_only"] as? NSNumber)?.boolValue ?? false
        fileObject.id = json["id"] as? String
        fileObject.rev = json["id"] as? String
        return fileObject
    }
    
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
            let latStr = DropboxFileProvider.decimalFormatter.string(from: NSNumber(value: latitude))
            let longStr = DropboxFileProvider.decimalFormatter.string(from: NSNumber(value: longitude))
            dic["Location"] = "\(latStr), \(longStr)"
        }
        if let timeTakenStr = json["time_taken"] as? String, let timeTaken = self.resolve(dateString: timeTakenStr) {
            keys.append("Date taken")
            DropboxFileProvider.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dic["Date taken"] = DropboxFileProvider.dateFormatter.string(from: timeTaken)
        }
        if let duration = json["duration"] as? UInt64 {
            keys.append("Duration")
            dic["Duration"] = DropboxFileProvider.formatshort(interval: TimeInterval(duration))
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
