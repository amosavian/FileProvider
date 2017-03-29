//
//  FTPHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

extension FTPFileProvider {
    private static let carriage = "\r\n"
    
    func readDataUntilEOF(of task: FPSStreamTask, minLength: Int, receivedData: Data? = nil, timeout: TimeInterval, completionHandler: @escaping (_ data: Data?, _ errror:Error?) -> Void) {
        task.readData(ofMinLength: minLength, maxLength: 65535, timeout: timeout) { (data, eof, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            var receivedData = receivedData
            if let data = data {
                if receivedData != nil {
                    receivedData!.append(data)
                } else {
                    receivedData = data
                }
            }
            
            if eof {
                completionHandler(receivedData, nil)
            } else {
                self.readDataUntilEOF(of: task, minLength: 0, receivedData: receivedData, timeout: timeout, completionHandler: completionHandler)
            }
            
        }
    }
    
    func execute(command: String, on task: FPSStreamTask, minLength: Int = 4, afterSend: ((_ error: Error?) -> Void)? = nil, completionHandler: @escaping (_ response: String?, _ error: Error?) -> Void) {
        let timeout = session.configuration.timeoutIntervalForRequest
        let terminalcommand = command + FTPFileProvider.carriage
        task.write(terminalcommand.data(using: .utf8)!, timeout: timeout) { (error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            afterSend?(error)
            
            if task.state == .suspended {
                task.resume()
            }
            
            task.readData(ofMinLength: minLength, maxLength: 1024, timeout: timeout) { (data, eof, error) in
                if let error = error {
                    completionHandler(nil, error)
                    return
                }
                
                if let data = data, let response = String(data: data, encoding: .utf8) {
                    completionHandler(response.trimmingCharacters(in: CharacterSet(charactersIn: FTPFileProvider.carriage)), nil)
                } else {
                    let badResponseError = NSError(domain: URLError.errorDomain, code: URLError.cannotParseResponse.rawValue, userInfo: nil)
                    completionHandler(nil, badResponseError)
                    return
                }
            }
        }
    }
    
    func ftpLogin(_ task: FPSStreamTask, completionHandler: @escaping (_ error: Error?) -> Void) {
        let timeout = session.configuration.timeoutIntervalForRequest
        if baseURL?.scheme == "ftps" {
            task.startSecureConnection()
        }
        if task.state == .suspended {
            task.resume()
        }
        
        let credential = self.credential
        
        task.readData(ofMinLength: 4, maxLength: 2048, timeout: timeout) { (data, eof, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let data = data, let response = String(data: data, encoding: .utf8) else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.cannotParseResponse.rawValue, userInfo: nil)
                completionHandler(error)
                return
            }
            
            guard response.hasPrefix("22") else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.cannotConnectToHost.rawValue, userInfo: nil)
                completionHandler(error)
                return
            }
            
            self.execute(command: "USER \(credential?.user ?? "anonymous")", on: task) { (response, error) in
                if let error = error {
                    completionHandler(error)
                    return
                }
                
                guard let response = response else {
                    let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                    completionHandler(error)
                    return
                }
                
                // successfully logged in
                if response.hasPrefix("23") {
                    
                    completionHandler(nil)
                }
                
                // needs password
                if response.hasPrefix("33") {
                    self.execute(command: "PASS \(credential?.password ?? "fileprovider@")", on: task) { (response, error) in
                        if response?.hasPrefix("2") ?? false {
                            completionHandler(nil)
                        } else {
                            let error = NSError(domain: URLError.errorDomain, code: URLError.userAuthenticationRequired.rawValue, userInfo: nil)
                            completionHandler(error)
                        }
                    }
                }
            }
        }
    }
    
    func ftpCwd(_ task: FPSStreamTask, to path: String, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "CWD \(path)", on: task) { (response, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let response = response else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(error)
                return
            }
            
            // successfully logged in
            if response.hasPrefix("25") {
                completionHandler(nil)
            }
            // not logged in
            else if response.hasPrefix("55") {
                let error = NSError(domain: URLError.errorDomain, code: URLError.fileDoesNotExist.rawValue, userInfo: nil)
                completionHandler(error)
            }
        }
    }
    
    func ftpPassive(_ task: FPSStreamTask, completionHandler: @escaping (_ host: String?, _ port: Int?, _ error: Error?) -> Void) {
        func trimmedNumber(_ s : String) -> String {
            let characterSet = Set("+*#0123456789".characters)
            return String(s.characters.lazy.filter(characterSet.contains))
        }
        
        self.execute(command: "PASV", on: task) { (response, error) in
            if let error = error {
                completionHandler(nil, nil, error)
                return
            }
            
            guard let response = response, let destString = response.components(separatedBy: " ").flatMap({ $0 }).last else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(nil, nil, error)
                return
            }
            
            let destArray = destString.components(separatedBy: ",").flatMap({ UInt32(trimmedNumber($0)) })
            guard destArray.count == 6 else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(nil, nil, error)
                return
            }
            
            // first 4 elements are ip, 2 next are port, as byte
            let ip = destArray.prefix(4).flatMap({ String($0) }).joined(separator: ".")
            let port = Int(destArray[4] << 8 + destArray[5])
            // IPv6 workaround
            if ip == "127.555.555.555" {
                completionHandler(self.baseURL?.host, port, nil)
            }
            completionHandler(ip, port, nil)
        }
    }
    
    func ftpRest(_ task: FPSStreamTask, startPosition: Int64, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "REST \(startPosition)", on: task) { (response, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Successful
            if response?.hasPrefix("35") ?? false {
                completionHandler(nil)
            } else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.resourceUnavailable.rawValue, userInfo: nil)
                completionHandler(error)
            }
        }
    }
    
    func ftpList(_ task: FPSStreamTask, of path: String, useMLST: Bool, completionHandler: @escaping (_ contents: [String], _ error: Error?) -> Void) {
        self.ftpPassive(task) { (host, port, error) in
            if let error = error {
                completionHandler([], error)
                return
            }
            
            guard let host = host, let port = port else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler([], error)
                return
            }
            
            let command = useMLST ? "MLSD \(path)" : "LIST \(path)"
            self.execute(command: command, on: task, minLength: 70, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                let passiveTask = self.session.fpstreamTask(withHostName: host, port: port)
                passiveTask.resume()
                
                DispatchQueue.global().async {
                    var finalData = Data()
                    var eof = false
                    var error: Error?
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        passiveTask.readData(ofMinLength: 0, maxLength: 65535, timeout: timeout, completionHandler: { (data, seof, serror) in
                            if let data = data {
                                finalData.append(data)
                            }
                            eof = seof
                            error = serror
                            group.leave()
                        })
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        if let error = error {
                            completionHandler([], error)
                            return
                        }
                        
                        if waitResult == .timedOut {
                            error = NSError(domain: URLError.errorDomain, code: URLError.timedOut.rawValue, userInfo: nil)
                            completionHandler([], error)
                            return
                        }
                    }
                    
                    guard let response = String(data: finalData, encoding: .utf8) else {
                        error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                        completionHandler([], error)
                        return
                    }
                    
                    let contents = response.components(separatedBy: "\n").flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    
                    completionHandler(contents, nil)
                    return
                }
            }) { (response, error) in
                if let error = error {
                    completionHandler([], error)
                    return
                }
            }
        }
    }
    
    func ftpRetrieve(_ task: FPSStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1, completionHandler: @escaping (_ data: Data?, _ error: Error?) -> Void) {
        // Retrieving data should be in passive mode
        // FIXME: retreiven't begain
        self.ftpPassive(task) { (host, port, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            guard let host = host, let port = port else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(nil, error)
                return
            }
            
            // Send retreive command
            // FIXME: use crlf instead of length
            self.execute(command: "REST \(position)\r\nRETR \(filePath)", on: task, minLength: 75, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                let passiveTask = self.session.fpstreamTask(withHostName: host, port: port)
                passiveTask.resume()
                
                DispatchQueue.global().async {
                    var finalData = Data()
                    var eof = false
                    var error: Error?
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        passiveTask.readData(ofMinLength: 0, maxLength: 65535, timeout: timeout, completionHandler: { (data, seof, serror) in
                            if let data = data {
                                finalData.append(data)
                            }
                            eof = seof || (length > 0 && finalData.count >= length)
                            if length > 0 && finalData.count > length {
                                finalData.count = length
                            }
                            error = serror
                            group.leave()
                        })
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        if let error = error {
                            completionHandler(nil, error)
                            return
                        }
                        
                        if waitResult == .timedOut {
                            error = NSError(domain: URLError.errorDomain, code: URLError.timedOut.rawValue, userInfo: nil)
                            completionHandler(nil, error)
                            return
                        }
                    }
                    completionHandler(finalData, nil)
                    return
                }
            }) { (response, error) in
                if let error = error {
                    completionHandler(nil, error)
                    return
                }
                
            }
        }
    }
    
    func ftpStore(_ task: FPSStreamTask, filePath: String, fromData: Data?, fromFile: URL?, completionHandler: @escaping (_ error: Error?) -> Void) {
        // Retrieving data should be in passive mode
        // FIXME: retreiven't begain
        self.ftpPassive(task) { (host, port, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let host = host, let port = port else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(error)
                return
            }
            
            // Send retreive command
            // FIXME: use crlf instead of length
            self.execute(command: "STOR \(filePath)", on: task, minLength: 75, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                let passiveTask = self.session.fpstreamTask(withHostName: host, port: port)
                passiveTask.resume()
                
                DispatchQueue.global().async {
                    var error: Error?
                    
                    if let data = fromData {
                        passiveTask.write(data, timeout: timeout, completionHandler: { (error) in
                            completionHandler(error)
                        })
                        return
                    }
                    
                    guard let file = fromFile, let fileHandle = FileHandle(forReadingAtPath: file.path) else { return }
                    
                    
                    fileHandle.seek(toFileOffset: 0)
                    var eof = false
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        let data = fileHandle.readData(ofLength: 65536)
                        eof = data.count < 65536
                        passiveTask.write(data, timeout: timeout, completionHandler: { (serror) in
                            error = serror
                            group.leave()
                        })
                        
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        if let error = error {
                            completionHandler(error)
                            return
                        }
                        
                        if waitResult == .timedOut {
                            error = NSError(domain: URLError.errorDomain, code: URLError.timedOut.rawValue, userInfo: nil)
                            completionHandler(error)
                            return
                        }
                    }
                    completionHandler(nil)
                    return
                }
            }) { (response, error) in
                if let error = error {
                    completionHandler(error)
                    return
                }
                
            }
        }
    }
    
    func ftpQuit(_ task: FPSStreamTask) {
        self.execute(command: "QUIT", on: task) { (_, _) in
            return
        }
    }
    
    func ftpPath(_ apath: String) -> String {
        var path = apath.isEmpty ? self.currentPath : apath
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        if path.hasSuffix("/"){
            path.characters.removeLast()
        }
        
        if path.isEmpty {
            path = "/"
        }
        return path
    }
    
    func parseUnixList(_ text: String, in path: String) -> FileObject? {
        let gregorian = Calendar(identifier: .gregorian)
        let nearDateFormatter = DateFormatter()
        nearDateFormatter.calendar = gregorian
        nearDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        nearDateFormatter.dateFormat = "MMM dd hh:ss yyyy"
        let farDateFormatter = DateFormatter()
        farDateFormatter.calendar = gregorian
        farDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        farDateFormatter.dateFormat = "MMM dd yyyy"
        let thisYear = gregorian.component(.year, from: Date())
        
        let components = text.components(separatedBy: " ").flatMap { $0.isEmpty ? nil : $0 }
        guard components.count >= 9 else { return nil }
        let posixPermission = components[0]
        let linksCount = Int(components[1]) ?? 0
        //let owner = components[2]
        //let groupOwner = components[3]
        let size = Int64(components[4]) ?? -1
        let date = components[5..<8].joined(separator: " ")
        let name = components[8..<components.count].joined(separator: " ")
        
        guard name != "." && name != ".." else { return nil }
        var path = (path as NSString).appendingPathComponent(name)
        if path.hasPrefix("/") {
            path.characters.removeFirst()
        }
        guard let url = URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path, relativeTo: self.baseURL!) else {
            return nil
        }
        
        let file = FileObject(url: url, name: name, path: path)
        switch String(posixPermission.characters.first!) {
        case "d": file.type = .directory
        case "l": file.type = .symbolicLink
        default:  file.type = .regular
        }
        file.isReadOnly = !posixPermission.contains("w")
        file.modifiedDate = nil //FIXME
        file.size = file.isDirectory ? -1 : size
        file.allValues[.linkCountKey] = linksCount
        
        if let parsedDate = nearDateFormatter.date(from: date + " " + String(thisYear)) {
            if parsedDate > Date() {
                file.modifiedDate = gregorian.date(byAdding: .year, value: -1, to: parsedDate)
            } else {
                file.modifiedDate = parsedDate
            }
        } else if let parsedDate = farDateFormatter.date(from: date) {
            file.modifiedDate = parsedDate
        }
        
        return file
    }
    
    func parseMLST(_ text: String, in path: String) -> FileObject? {
        var components = text.components(separatedBy: ";").flatMap { $0.isEmpty ? nil : $0 }
        guard components.count > 1 else { return nil }
        
        let nameOrPath = components.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let completePath: String, name: String
        if nameOrPath.hasPrefix("/") {
            completePath = nameOrPath
            name = (nameOrPath as NSString).lastPathComponent
        } else {
            name = nameOrPath
            completePath = (path as NSString).appendingPathComponent(nameOrPath)
        }
        guard let url = URL(string: completePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? completePath, relativeTo: self.baseURL!) else {
            return nil
        }
        
        var attributes = [String: String]()
        for component in components {
            let keyValue = component.components(separatedBy: "=") .flatMap { $0.isEmpty ? nil : $0 }
            guard keyValue.count >= 2, !keyValue[0].isEmpty else { continue }
            attributes[keyValue[0].lowercased()] = keyValue.dropFirst().joined(separator: "=")
        }
        
        let file = FileObject(url: url, name: name, path: completePath)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMddhhmmss"
        for (key, attribute) in attributes {
            switch key {
            case "type":
                switch attribute.lowercased() {
                case "file": file.type = .regular
                case "dir": file.type = .directory
                case "link": file.type = .symbolicLink
                case "os.unix=block": file.type = .blockSpecial
                case "cdir", "pdir": return nil
                default: file.type = .unknown
                }
                
            case "unique":
                file.allValues[URLResourceKey.fileResourceIdentifierKey] = attribute
                
            case "modify":
                file.modifiedDate = dateFormatter.date(from: attribute)
            
            case "create":
                file.creationDate = dateFormatter.date(from: attribute)
                
            case "perm":
                file.allValues[.isReadableKey] = attribute.contains("r") || attribute.contains("l")
                file.allValues[.isWritableKey] = attribute.contains("w") || attribute.contains("r")
                
            case "size":
                file.size = Int64(attribute) ?? -1
                
            case "media-type":
                file.allValues[.mimeType] = attribute
                
            default:
                break
            }
        }
        
        return file
    }
}
