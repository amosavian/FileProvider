//
//  DropboxHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian on 5/18/95.
//
//

import Foundation

public struct FileProviderDropboxError: ErrorType, CustomStringConvertible {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    
    public var description: String {
        return code.description
    }
}

public final class DropboxFileObject: FileObject {
    public let serverTime: NSDate?
    public let id: String?
    public let rev: String?
    
    public init(name: String, path: String, size: Int64 = -1, serverTime: NSDate? = nil, modifiedDate: NSDate? = nil, fileType: FileType = .Regular, isHidden: Bool = false, isReadOnly: Bool = false, id: String? = nil, rev: String? = nil) {
        self.serverTime = serverTime
        self.id = id
        self.rev = rev
        super.init(absoluteURL: NSURL(string: path), name: name, path: path, size: size, createdDate: nil, modifiedDate: modifiedDate, fileType: fileType, isHidden: isHidden, isReadOnly: isReadOnly)
    }
}

internal extension DropboxFileProvider {
    func list(path: String, cursor: String? = nil, prevContents: [DropboxFileObject] = [], recursive: Bool = false, completionHandler: ((contents: [FileObject], cursor: String?, error: ErrorType?) -> Void)) {
        var requestDictionary = [String: AnyObject]()
        let url: NSURL
        if let cursor = cursor {
            url = NSURL(string: "https://api.dropboxapi.com/2/files/list_folder/continue")!
            requestDictionary["cursor"] = cursor
        } else {
            url = NSURL(string: "https://api.dropboxapi.com/2/files/list_folder")!
            requestDictionary["path"] = correctPath(path)
            requestDictionary["recursive"] = NSNumber(bool: recursive)
        }
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.HTTPBody = dictionaryToJSON(requestDictionary)?.dataUsingEncoding(NSUTF8StringEncoding)
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: path)
            }
            if let data = data, let jsonStr = String(data: data, encoding: NSUTF8StringEncoding) {
                let json = self.jsonToDictionary(jsonStr)
                if let entries = json?["entries"] as? [AnyObject] where entries.count > 0 {
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
                        completionHandler(contents: files, cursor: ncursor, error: responseError ?? error)
                    }
                    return
                }
            }
            completionHandler(contents: [], cursor: nil, error: responseError ?? error)
        }
        task.resume()
    }
    
    func upload_simple(targetPath: String, data: NSData, modifiedDate: NSDate = NSDate(), overwrite: Bool, operation: FileOperation, completionHandler: SimpleCompletionHandler) {
        assert(data.length < 150*1024*1024, "Maximum size of allowed size to upload is 150MB")
        var requestDictionary = [String: AnyObject]()
        let url: NSURL
        url = NSURL(string: "https://content.dropboxapi.com/2/files/upload")!
        requestDictionary["path"] = correctPath(targetPath)
        requestDictionary["mode"] = overwrite ? "overwrite" : "add"
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssz"
        requestDictionary["client_modified"] = dateFormatter.stringFromDate(modifiedDate)
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(dictionaryToJSON(requestDictionary), forHTTPHeaderField: "Dropbox-API-Arg")
        request.HTTPBody = data
        let task = session.uploadTaskWithRequest(request, fromData: data) { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: targetPath)
            }
            defer {
                self.delegateNotify(.Create(path: targetPath), error: responseError ?? error)
            }
            completionHandler?(error: responseError ?? error)
        }
        var dic: [String: AnyObject] = ["type": operation.description]
        switch operation {
        case .Create(path: let s):
            dic["source"] = s
        case .Copy(source: let s, destination: let d):
            dic["source"] = s
            dic["dest"] = d
        case .Modify(path: let s):
            dic["source"] = s
        case .Move(source: let s, destination: let d):
            dic["source"] = s
            dic["dest"] = d
        default:
            break
        }
        task.taskDescription = self.dictionaryToJSON(dic)
        task.resume()
    }
    
    func search(startPath: String = "", query: String, start: Int = 0, maxResultPerPage: Int = 25, maxResults: Int = -1, foundItem:((file: DropboxFileObject) -> Void), completionHandler: ((error: ErrorType?) -> Void)) {
        let url = NSURL(string: "https://api.dropboxapi.com/2/files/search")!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.setValue("Bearer \(credential?.password ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var requestDictionary: [String: AnyObject] = ["path": startPath]
        requestDictionary["query"] = query
        requestDictionary["start"] = start
        requestDictionary["max_results"] = maxResultPerPage
        request.HTTPBody = dictionaryToJSON(requestDictionary)?.dataUsingEncoding(NSUTF8StringEncoding)
        let task = session.dataTaskWithRequest(request) { (data, response, error) in
            var responseError: FileProviderDropboxError?
            if let code = (response as? NSHTTPURLResponse)?.statusCode where code >= 300, let rCode = FileProviderHTTPErrorCode(rawValue: code) {
                responseError = FileProviderDropboxError(code: rCode, path: startPath)
            }
            if let data = data, let jsonStr = String(data: data, encoding: NSUTF8StringEncoding) {
                let json = self.jsonToDictionary(jsonStr)
                if let entries = json?["matches"] as? [AnyObject] where entries.count > 0 {
                    for entry in entries {
                        if let entry = entry as? [String: AnyObject], let file = self.mapToFileObject(entry) {
                            foundItem(file: file)
                        }
                    }
                    let rstart = json?["start"] as? Int
                    let hasmore = (json?["more"] as? NSNumber)?.boolValue ?? false
                    if hasmore, let rstart = rstart {
                        self.search(startPath, query: query, start: rstart + entries.count, maxResultPerPage: maxResultPerPage, foundItem: foundItem, completionHandler: completionHandler)
                    } else {
                        completionHandler(error: responseError ?? error)
                    }
                    return
                }
            }
            completionHandler(error: responseError ?? error)
        }
        task.resume()
    }
}

internal extension DropboxFileProvider {
    func mapToFileObject(jsonStr: String) -> DropboxFileObject? {
        guard let json = self.jsonToDictionary(jsonStr) else { return nil }
        return self.mapToFileObject(json)
    }
    
    func mapToFileObject(json: [String: AnyObject]) -> DropboxFileObject? {
        guard let name = json["name"] as? String else { return nil }
        guard let path = json["path_display"] as? String else { return nil }
        let size = (json["size"] as? NSNumber)?.longLongValue ?? -1
        let serverTime = resolveDate(json["server_modified"] as? String ?? "")
        let modifiedDate = resolveDate(json["client_modified"] as? String ?? "")
        let isDirectory = (json[".tag"] as? String) == "folder"
        let isReadonly = (json["sharing_info"]?["read_only"] as? NSNumber)?.boolValue ?? false
        let id = json["id"] as? String
        let rev = json["id"] as? String
        return DropboxFileObject(name: name, path: path, size: size, serverTime: serverTime, modifiedDate: modifiedDate, fileType: isDirectory ? .Directory : .Regular, isReadOnly: isReadonly, id: id, rev: rev)
    }
    
    func delegateNotify(operation: FileOperation, error: ErrorType?) {
        dispatch_async(dispatch_get_main_queue(), {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
}