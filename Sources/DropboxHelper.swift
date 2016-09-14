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
    public let serverTime: Date?
    public let id: String?
    public let rev: String?
    
    // codebeat:disable[ARITY]
    public init(name: String, path: String, size: Int64 = -1, serverTime: Date? = nil, modifiedDate: Date? = nil, fileType: FileType = .regular, isHidden: Bool = false, isReadOnly: Bool = false, id: String? = nil, rev: String? = nil) {
        self.serverTime = serverTime
        self.id = id
        self.rev = rev
        super.init(absoluteURL: URL(string: path), name: name, path: path, size: size, createdDate: nil, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
    // codebeat:enable[ARITY]
}

// codebeat:disable[ARITY]
internal extension DropboxFileProvider {
    func list(_ path: String, cursor: String? = nil, prevContents: [DropboxFileObject] = [], recursive: Bool = false, completionHandler: @escaping ((_ contents: [FileObject], _ cursor: String?, _ error: Error?) -> Void)) {
        var requestDictionary = [String: AnyObject]()
        let url: URL
        if let cursor = cursor {
            url = URL(string: "https://api.dropboxapi.com/2/files/list_folder/continue")!
            requestDictionary["cursor"] = cursor as AnyObject?
        } else {
            url = URL(string: "https://api.dropboxapi.com/2/files/list_folder")!
            requestDictionary["path"] = correctPath(path) as NSString?
            requestDictionary["recursive"] = recursive as AnyObject?
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: String.Encoding.utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: path, errorDescription: String(data: data ?? Data(), encoding: String.Encoding.utf8))
            }
            if let data = data, let jsonStr = String(data: data, encoding: String.Encoding.utf8) {
                let json = jsonToDictionary(jsonStr)
                if let entries = json?["entries"] as? [AnyObject] , entries.count > 0 {
                    var files = prevContents
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = self.mapToFileObject(entry) {
                            files.append(file)
                        }
                    }
                    let ncursor = json?["cursor"] as? String
                    let hasmore = (json?["has_more"] as? NSNumber)?.boolValue ?? false
                    if hasmore {
                        self.list(path, cursor: ncursor, prevContents: files, completionHandler: completionHandler)
                    } else {
                        completionHandler(files, ncursor, responseError ?? error)
                    }
                    return
                }
            }
            completionHandler([], nil, responseError ?? error)
        }) 
        task.resume()
    }
    
    func upload_simple(_ targetPath: String, data: Data, modifiedDate: Date = Date(), overwrite: Bool, operation: FileOperation, completionHandler: SimpleCompletionHandler) {
        assert(data.count < 150*1024*1024, "Maximum size of allowed size to upload is 150MB")
        var requestDictionary = [String: AnyObject]()
        let url: URL
        url = URL(string: "https://content.dropboxapi.com/2/files/upload")!
        requestDictionary["path"] = correctPath(targetPath) as NSString?
        requestDictionary["mode"] = (overwrite ? "overwrite" : "add") as NSString
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssz"
        requestDictionary["client_modified"] = dateFormatter.string(from: modifiedDate) as AnyObject?
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data
        let task = session.uploadTask(with: request, from: data, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: targetPath, errorDescription: String(data: data ?? Data(), encoding: String.Encoding.utf8))
            }
            defer {
                self.delegateNotify(.create(path: targetPath), error: responseError ?? error)
            }
            completionHandler?(responseError ?? error)
        }) 
        var dic: [String: AnyObject] = ["type": operation.description as AnyObject]
        switch operation {
        case .create(path: let s):
            dic["source"] = s as NSString
        case .copy(source: let s, destination: let d):
            dic["source"] = s as NSString
            dic["dest"] = d as NSString
        case .modify(path: let s):
            dic["source"] = s as NSString
        case .move(source: let s, destination: let d):
            dic["source"] = s as NSString
            dic["dest"] = d as NSString
        default:
            break
        }
        task.taskDescription = dictionaryToJSON(dic)
        task.resume()
    }
    
    func search(_ startPath: String = "", query: String, start: Int = 0, maxResultPerPage: Int = 25, maxResults: Int = -1, foundItem:@escaping ((_ file: DropboxFileObject) -> Void), completionHandler: @escaping ((_ error: Error?) -> Void)) {
        let url = URL(string: "https://api.dropboxapi.com/2/files/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestDictionary: [String: AnyObject] = ["path": startPath as AnyObject]
        requestDictionary["query"] = query as AnyObject?
        requestDictionary["start"] = start as AnyObject?
        requestDictionary["max_results"] = maxResultPerPage as AnyObject?
        request.httpBody = dictionaryToJSON(requestDictionary)?.data(using: String.Encoding.utf8)
        let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? HTTPURLResponse)?.statusCode , code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: startPath, errorDescription: String(data: data ?? Data(), encoding: String.Encoding.utf8))
            }
            if let data = data, let jsonStr = String(data: data, encoding: String.Encoding.utf8) {
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
        let size = (json["size"] as? NSNumber)?.int64Value ?? -1
        let serverTime = resolve(dateString: json["server_modified"] as? String ?? "")
        let modifiedDate = resolve(dateString: json["client_modified"] as? String ?? "")
        let isDirectory = (json[".tag"] as? String) == "folder"
        let isReadonly = (json["sharing_info"]?["read_only"] as? NSNumber)?.boolValue ?? false
        let id = json["id"] as? String
        let rev = json["id"] as? String
        return DropboxFileObject(name: name, path: path, size: size, serverTime: serverTime, modifiedDate: modifiedDate, fileType: isDirectory ? .directory : .regular, isReadOnly: isReadonly, id: id, rev: rev)
    }
    
    func delegateNotify(_ operation: FileOperation, error: Error?) {
        DispatchQueue.main.async(execute: {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
}
