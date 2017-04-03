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
    
    func delegateNotify(_ operation: FileOperationType, error: Error?) {
        DispatchQueue.main.async(execute: {
            if error == nil {
                self.delegate?.fileproviderSucceed(self, operation: operation)
            } else {
                self.delegate?.fileproviderFailed(self, operation: operation)
            }
        })
    }
    
    func readDataUntilEOF(of task: FileProviderStreamTask, minLength: Int, receivedData: Data? = nil, timeout: TimeInterval, completionHandler: @escaping (_ data: Data?, _ errror:Error?) -> Void) {
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
    
    func execute(command: String, on task: FileProviderStreamTask, minLength: Int = 4, afterSend: ((_ error: Error?) -> Void)? = nil, completionHandler: @escaping (_ response: String?, _ error: Error?) -> Void) {
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
    
    func ftpLogin(_ task: FileProviderStreamTask, completionHandler: @escaping (_ error: Error?) -> Void) {
        let timeout = session.configuration.timeoutIntervalForRequest
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
                let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                completionHandler(error)
                return
            }
            
            let loginHandle = {
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
                        return
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
                        return
                    }
                    
                    let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                    let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                    let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                    let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                    completionHandler(error)
                    return
                }
            }
            
            if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
                self.execute(command: "AUTH TLS", on: task, minLength: 0, completionHandler: { (response, error) in
                    task.startSecureConnection()
                    loginHandle()
                })
            } else {
                loginHandle()
            }
        }
    }
    
    func ftpCwd(_ task: FileProviderStreamTask, to path: String, completionHandler: @escaping (_ error: Error?) -> Void) {
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
                let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                completionHandler(error)
                return
            }
        }
    }
    
    func ftpPassive(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        func trimmedNumber(_ s : String) -> String {
            let characterSet = Set("+*#0123456789".characters)
            return String(s.characters.lazy.filter(characterSet.contains))
        }
        
        self.execute(command: "PASV", on: task) { (response, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            guard let response = response, let destString = response.components(separatedBy: " ").flatMap({ $0 }).last else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(nil, error)
                return
            }
            
            let destArray = destString.components(separatedBy: ",").flatMap({ UInt32(trimmedNumber($0)) })
            guard destArray.count == 6 else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(nil, error)
                return
            }
            
            // first 4 elements are ip, 2 next are port, as byte
            var host = destArray.prefix(4).flatMap({ String($0) }).joined(separator: ".")
            let port = Int(destArray[4] << 8 + destArray[5])
            // IPv6 workaround
            if host == "127.555.555.555" {
                host = self.baseURL!.host!
            }
            
            let passiveTask = self.session.fpstreamTask(withHostName: host, port: port)
            passiveTask.resume()
            if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
                task.startSecureConnection()
            }
            completionHandler(passiveTask, nil)
        }
    }
    
    func ftpActive(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        NotImplemented()
        let port = 0
        self.execute(command: "PORT \(port)", on: task) { (response, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            guard let response = response else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(nil, error)
                return
            }
            
            guard !response.hasPrefix("5") else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.cannotConnectToHost.rawValue, userInfo: nil)
                completionHandler(nil, error)
                return
            }
            
            let activeTask = self.session.fpstreamTask(withHostName: self.baseURL!.host!, port: 20)
            activeTask.resume()
            if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
                task.startSecureConnection()
            }
            completionHandler(activeTask, nil)
        }
    }
    
    func ftpDataConnect(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        if self.passiveMode {
            self.ftpPassive(task, completionHandler: completionHandler)
        } else {
            self.ftpActive(task, completionHandler: completionHandler)
        }
    }
    
    func ftpRest(_ task: FileProviderStreamTask, startPosition: Int64, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "REST \(startPosition)", on: task) { (response, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Successful
            if response?.hasPrefix("35") ?? false {
                completionHandler(nil)
            } else {
                let spaceIndex = response?.characters.index(of: "-") ?? response?.startIndex
                let code = Int((response?.substring(to: spaceIndex!).trimmingCharacters(in: .whitespacesAndNewlines))!) ?? -1
                let description = response?.substring(from: spaceIndex!).trimmingCharacters(in: .whitespacesAndNewlines)
                let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                completionHandler(error)
                return
            }
        }
    }
    
    func ftpList(_ task: FileProviderStreamTask, of path: String, useMLST: Bool, completionHandler: @escaping (_ contents: [String], _ error: Error?) -> Void) {
        self.ftpDataConnect(task) { (dataTask, error) in
            if let error = error {
                completionHandler([], error)
                return
            }
            
            guard let dataTask = dataTask else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler([], error)
                return
            }
            
            let command = useMLST ? "MLSD \(path)" : "LIST \(path)"
            self.execute(command: command, on: task, minLength: 70, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                
                DispatchQueue.global().async {
                    var finalData = Data()
                    var eof = false
                    var error: Error?
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        dataTask.readData(ofMinLength: 0, maxLength: 65535, timeout: timeout, completionHandler: { (data, seof, serror) in
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
                
                guard let response = response else {
                    let badResponseError = NSError(domain: URLError.errorDomain, code: URLError.cannotParseResponse.rawValue, userInfo: nil)
                    completionHandler([], badResponseError)
                    return
                }
                
                if response.hasPrefix("50") && useMLST {
                    self.ftpList(task, of: path, useMLST: false, completionHandler: completionHandler)
                    return
                }
                
                if !response.hasPrefix("25") {
                    let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                    let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                    let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                    let error = FileProviderFTPError(code: code, path: "", errorDescription: description)

                    self.dispatch_queue.async {
                        completionHandler([], error)
                    }
                    return
                }
            }
        }
    }
    
    func ftpRecursiveList(_ task: FileProviderStreamTask, of path: String, useMLST: Bool, completionHandler: @escaping (_ contents: [String], _ error: Error?) -> Void) {
        // TODO: Implement recursive listing for search and removing function
    }
    
    func ftpRetrieveData(_ task: FileProviderStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1, onTask: ((_ task: FileProviderStreamTask) -> Void)?, onProgress: ((_ bytesReceived: Int64, _ totalReceived: Int64, _ expectedBytes: Int64) -> Void)?, completionHandler: @escaping (_ data: Data?, _ error: Error?) -> Void) {
        
        // Check cache
        if useCache, let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL, let cachedResponse = self.cache?.cachedResponse(for: URLRequest(url: url)), cachedResponse.data.count > 0 {
            dispatch_queue.async {
                completionHandler(cachedResponse.data, nil)
            }
            return
        }
        
        self.attributesOfItem(path: filePath) { (file, error) in
            let totalSize = file?.size ?? -1
            // Retreive data from server
            self.ftpDataConnect(task) { (dataTask, error) in
                if let error = error {
                    completionHandler(nil, error)
                    return
                }
                
                guard let dataTask = dataTask else {
                    let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                    completionHandler(nil, error)
                    return
                }
                
                // Send retreive command
                self.execute(command: "TYPE L" + FTPFileProvider.carriage + "REST \(position)" + FTPFileProvider.carriage + "RETR \(filePath)", on: task, minLength: 75, afterSend: { error in
                    // starting passive task
                    onTask?(dataTask)
                    
                    let timeout = self.session.configuration.timeoutIntervalForRequest
                    DispatchQueue.global().async {
                        var finalData = Data()
                        var eof = false
                        var error: Error?
                        while !eof {
                            let group = DispatchGroup()
                            group.enter()
                            dataTask.readData(ofMinLength: 0, maxLength: 65535, timeout: timeout, completionHandler: { (data, seof, serror) in
                                if let data = data {
                                    finalData.append(data)
                                    onProgress?(Int64(data.count), Int64(finalData.count), totalSize)
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
                        
                        if let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL {
                            let urlresponse = URLResponse(url: url, mimeType: nil, expectedContentLength: finalData.count, textEncodingName: nil)
                            let cachedResponse = CachedURLResponse(response: urlresponse, data: finalData)
                            let request = URLRequest(url: url)
                            self.cache?.storeCachedResponse(cachedResponse, for: request)
                        }
                        
                        completionHandler(finalData, nil)
                        return
                    }
                }) { (response, error) in
                    if let error = error {
                        completionHandler(nil, error)
                        return
                    }
                    
                    guard let response = response else {
                        let badResponseError = NSError(domain: URLError.errorDomain, code: URLError.cannotParseResponse.rawValue, userInfo: nil)
                        completionHandler(nil, badResponseError)
                        return
                    }
                    
                    if !(response.hasPrefix("1") || !response.hasPrefix("2")) {
                        let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                        let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                        let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                        let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                        
                        self.dispatch_queue.async {
                            completionHandler(nil, error)
                        }
                        return
                    }
                }
            }
        }
    }
    
    func ftpRetrieveFile(_ task: FileProviderStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1, onTask: ((_ task: FileProviderStreamTask) -> Void)?, onProgress: ((_ bytesReceived: Int64, _ totalReceived: Int64, _ expectedBytes: Int64) -> Void)?, completionHandler: @escaping (_ file: URL?, _ error: Error?) -> Void) {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
        
        // Check cache
        if useCache, let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL, let cachedResponse = self.cache?.cachedResponse(for: URLRequest(url: url)), cachedResponse.data.count > 0 {
            dispatch_queue.async {
                do {
                    try cachedResponse.data.write(to: tempURL)
                    completionHandler(tempURL, nil)
                } catch {
                    completionHandler(nil, error)
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
            return
        }
        
        self.attributesOfItem(path: filePath) { (file, error) in
            let totalSize = file?.size ?? -1
            // Retreive data from server
            self.ftpDataConnect(task) { (dataTask, error) in
                if let error = error {
                    completionHandler(nil, error)
                    return
                }
                
                guard let dataTask = dataTask else {
                    let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                    completionHandler(nil, error)
                    return
                }
                
                // Send retreive command
                self.execute(command: "TYPE I"  + FTPFileProvider.carriage + "REST \(position)" + FTPFileProvider.carriage + "RETR \(filePath)", on: task, minLength: 75, afterSend: { error in
                    // starting passive task
                    onTask?(dataTask)
                    
                    let timeout = self.session.configuration.timeoutIntervalForRequest
                    DispatchQueue.global().async {
                        var finalData = Data()
                        var eof = false
                        var error: Error?
                        while !eof {
                            let group = DispatchGroup()
                            group.enter()
                            dataTask.readData(ofMinLength: 0, maxLength: 65535, timeout: timeout, completionHandler: { (data, seof, serror) in
                                if let data = data {
                                    finalData.append(data)
                                    onProgress?(Int64(data.count), Int64(finalData.count), totalSize)
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
                        
                        if let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL {
                            let urlresponse = URLResponse(url: url, mimeType: nil, expectedContentLength: finalData.count, textEncodingName: nil)
                            let cachedResponse = CachedURLResponse(response: urlresponse, data: finalData)
                            let request = URLRequest(url: url)
                            self.cache?.storeCachedResponse(cachedResponse, for: request)
                        }
                        
                        self.dispatch_queue.async {
                            do {
                                try finalData.write(to: tempURL)
                                completionHandler(tempURL, nil)
                            } catch {
                                completionHandler(nil, error)
                            }
                            try? FileManager.default.removeItem(at: tempURL)
                        }
                        return
                    }
                }) { (response, error) in
                    if let error = error {
                        completionHandler(nil, error)
                        return
                    }
                    
                    guard let response = response else {
                        let badResponseError = NSError(domain: URLError.errorDomain, code: URLError.cannotParseResponse.rawValue, userInfo: nil)
                        completionHandler(nil, badResponseError)
                        return
                    }
                    
                    if !(response.hasPrefix("1") || !response.hasPrefix("2")) {
                        let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                        let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                        let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                        let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                        
                        self.dispatch_queue.async {
                            completionHandler(nil, error)
                        }
                        return
                    }
                }
            }
        }
    }
    
    func ftpStore(_ task: FileProviderStreamTask, filePath: String, fromData: Data?, fromFile: URL?, onTask: ((_ task: FileProviderStreamTask) -> Void)?, completionHandler: @escaping (_ error: Error?) -> Void) {
        
        self.ftpDataConnect(task) { (dataTask, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let dataTask = dataTask else {
                let error = NSError(domain: URLError.errorDomain, code: URLError.badServerResponse.rawValue, userInfo: nil)
                completionHandler(error)
                return
            }
            
            // Send retreive command
            self.execute(command: "TYPE L"  + FTPFileProvider.carriage + "STOR \(filePath)", on: task, minLength: 75, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
                    task.startSecureConnection()
                }
                onTask?(dataTask)
                
                DispatchQueue.global().async {
                    var error: Error?
                    
                    if let data = fromData {
                        dataTask.write(data, timeout: timeout, completionHandler: { (error) in
                            completionHandler(error)
                        })
                        dataTask.closeWrite()
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
                        dataTask.write(data, timeout: timeout, completionHandler: { (serror) in
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
                    dataTask.closeWrite()
                    completionHandler(nil)
                    return
                }
            }) { (response, error) in
                if let error = error {
                    completionHandler(error)
                    return
                }
                
                guard let response = response else {
                    let badResponseError = NSError(domain: URLError.errorDomain, code: URLError.cannotParseResponse.rawValue, userInfo: nil)
                    completionHandler(badResponseError)
                    return
                }
                
                if !(response.hasPrefix("1") || !response.hasPrefix("2")) {
                    let spaceIndex = response.characters.index(of: "-") ?? response.startIndex
                    let code = Int(response.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
                    let description = response.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                    let error = FileProviderFTPError(code: code, path: "", errorDescription: description)
                    
                    self.dispatch_queue.async {
                        completionHandler(error)
                    }
                    return
                }
            }
        }
    }
    
    func ftpQuit(_ task: FileProviderStreamTask) {
        self.execute(command: "QUIT", on: task) { (_, _) in
            //task.closeRead()
            //task.closeWrite()
        }
    }
    
    func ftpPath(_ apath: String) -> String {
        var path = apath.isEmpty ? self.currentPath : apath
        
        // path of base url should be concreted into file path!
        path = baseURL!.appendingPathComponent(path).path
        
        // Fixing slashes
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
        
        let file = FileObject(url: url(of: path), name: name, path: path)
        switch String(posixPermission.characters.first!) {
        case "d": file.type = .directory
        case "l": file.type = .symbolicLink
        default:  file.type = .regular
        }
        file.isReadOnly = !posixPermission.contains("w")
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
        let correctedPath: String, name: String
        if nameOrPath.hasPrefix("/") {
            correctedPath = nameOrPath.replacingOccurrences(of: baseURL!.path, with: "", options: .anchored)
            name = (nameOrPath as NSString).lastPathComponent
        } else {
            name = nameOrPath
            correctedPath = (path as NSString).appendingPathComponent(nameOrPath)
        }
        
        var attributes = [String: String]()
        for component in components {
            let keyValue = component.components(separatedBy: "=") .flatMap { $0.isEmpty ? nil : $0 }
            guard keyValue.count >= 2, !keyValue[0].isEmpty else { continue }
            attributes[keyValue[0].lowercased()] = keyValue.dropFirst().joined(separator: "=")
        }
        
        let file = FileObject(url: url(of: path), name: name, path: correctedPath)
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
                case "cdir", "pdir": return nil // . and .. files are redundant in listing
                default: file.type = .unknown
                }
                
            case "unique":
                file.allValues[.fileResourceIdentifierKey] = attribute
                
            case "modify":
                file.modifiedDate = dateFormatter.date(from: attribute)
            
            case "create":
                file.creationDate = dateFormatter.date(from: attribute)
                
            case "perm":
                file.allValues[.isReadableKey] = attribute.contains("r") || attribute.contains("l")
                file.allValues[.isWritableKey] = attribute.contains("w") || attribute.contains("a")
                
            case "size":
                file.size = Int64(attribute) ?? -1
                
            case "media-type":
                file.allValues[.mimeTypeKey] = attribute
                
            default:
                break
            }
        }
        
        return file
    }
}

/// Contains error code and description returned by FTP/S provider.
public struct FileProviderFTPError: Error {
    /// HTTP status code returned for error by server.
    public let code: Int
    /// Path of file/folder casued that error
    public let path: String
    /// Contents returned by server as error description
    public let errorDescription: String?
}
