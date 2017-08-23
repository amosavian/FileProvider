//
//  FTPHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

internal extension FTPFileProvider {
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
        let terminalcommand = command + "\r\n"
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
                    completionHandler(response.trimmingCharacters(in: .whitespacesAndNewlines), nil)
                } else {
                    completionHandler(nil, self.throwError("", code: URLError.cannotParseResponse))
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
        
        var isSecure = false
        // Implicit FTP Connection
        if self.baseURL?.port == 990 || self.baseURL?.scheme == "ftps" {
            task.startSecureConnection()
            isSecure = true
        }
        
        let credential = self.credential
        
        task.readData(ofMinLength: 4, maxLength: 2048, timeout: timeout) { (data, eof, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let data = data, let response = String(data: data, encoding: .utf8) else {
                completionHandler(self.throwError("", code: URLError.cannotParseResponse))
                return
            }
            
            guard response.hasPrefix("22") else {
                let error = FileProviderFTPError(message: response)
                completionHandler(error)
                return
            }
            
            let loginHandle: () -> Void = {
                self.execute(command: "USER \(credential?.user ?? "anonymous")", on: task) { (response, error) in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    
                    guard let response = response else {
                        completionHandler(self.throwError("", code: URLError.badServerResponse))
                        return
                    }
                    
                    // successfully logged in
                    if response.hasPrefix("23") {
                        completionHandler(nil)
                        return
                    }
                    
                    // needs password
                    if FileProviderFTPError(message: response).code == 331 {
                        self.execute(command: "PASS \(credential?.password ?? "fileprovider@")", on: task) { (response, error) in
                            if response?.hasPrefix("23") ?? false {
                                completionHandler(nil)
                            } else {
                                completionHandler(self.throwError("", code: URLError.userAuthenticationRequired))
                            }
                        }
                        return
                    }
                    
                    let error = FileProviderFTPError(message: response)
                    completionHandler(error)
                    return
                }
            }
            
            if !isSecure && self.baseURL?.scheme == "ftpes" {
                // Explicit FTP Connection, by upgrading connection to FTP/SSL
                self.execute(command: "AUTH TLS", on: task, minLength: 0, completionHandler: { (response, error) in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    
                    if let response = response, response.hasPrefix("23") {
                        task.startSecureConnection()
                        isSecure = true
                        self.execute(command: "PBSZ 0\r\nPROT P", on: task, completionHandler: { (response, error) in
                            if let error = error {
                                completionHandler(error)
                                return
                            }
                            
                            loginHandle()
                        })
                    }
                })
            } else if isSecure {
                self.execute(command: "PBSZ 0\r\nPROT P", on: task, completionHandler: { (response, error) in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    
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
                completionHandler(self.throwError(path, code: URLError.badServerResponse))
                return
            }
            
            // successfully logged in
            if response.hasPrefix("25") {
                completionHandler(nil)
            }
            // not logged in
            else if response.hasPrefix("55") {
                let error = FileProviderFTPError(message: response)
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
            
            guard let response = response, let destString = response.components(separatedBy: " ").flatMap({ $0 }).last.flatMap({ String($0) }) else {
                completionHandler(nil, self.throwError("", code: URLError.badServerResponse))
                return
            }
            
            let destArray = destString.components(separatedBy: ",").flatMap({ UInt32(trimmedNumber($0)) })
            guard destArray.count == 6 else {
                completionHandler(nil, self.throwError("", code: URLError.badServerResponse))
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
            if self.baseURL?.scheme == "ftps" || self.baseURL?.scheme == "ftpes" || self.baseURL?.port == 990 {
                passiveTask.startSecureConnection()
            }
            completionHandler(passiveTask, nil)
        }
    }
    
    func ftpActive(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        let service = NetService(domain: "", type: "_tcp.", name: "", port: 0)
        service.publish(options: .listenForConnections)
        let startTime = Date()
        while service.port < 1 && startTime.timeIntervalSinceNow > -self.session.configuration.timeoutIntervalForRequest {
            usleep(100_000)
        }
        let activeTask = self.session.fpstreamTask(withNetService: service)
        activeTask.resume()
        if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
            activeTask.startSecureConnection()
        }
        
        self.execute(command: "PORT \(service.port)", on: task) { (response, error) in
            if let error = error {
                activeTask.cancel()
                completionHandler(nil, error)
                return
            }
            
            guard let response = response else {
                activeTask.cancel()
                completionHandler(nil, self.throwError("", code: URLError.badServerResponse))
                return
            }
            
            guard !response.hasPrefix("5") else {
                activeTask.cancel()
                completionHandler(nil, self.throwError("", code: URLError.cannotConnectToHost))
                return
            }
            
            completionHandler(activeTask, nil)
        }
    }
    
    func ftpDataConnect(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        if self.passiveMode {
            self.ftpPassive(task, completionHandler: completionHandler)
        } else {
            dispatch_queue.async {
                self.ftpActive(task, completionHandler: completionHandler)
            }
        }
    }
    
    func ftpRest(_ task: FileProviderStreamTask, startPosition: Int64, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "REST \(startPosition)", on: task) { (response, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Successful
            guard let response = response else {
                completionHandler(self.throwError("", code: URLError.badServerResponse))
                return
            }
            
            if response.hasPrefix("35") {
                completionHandler(nil)
            } else {
                let error = FileProviderFTPError(message: response, path: "")
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
                completionHandler([], self.throwError(path, code: URLError.badServerResponse))
                return
            }
            
            var success = false
            let command = useMLST ? "MLSD \(path)" : "LIST \(path)"
            self.execute(command: command, on: task, minLength: 20, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                
                DispatchQueue.global().async {
                    var finalData = Data()
                    var eof = false
                    var error: Error?
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        dataTask.readData(ofMinLength: 1, maxLength: 65535, timeout: timeout, completionHandler: { (data, seof, serror) in
                            if let data = data {
                                finalData.append(data)
                            }
                            eof = seof
                            error = serror
                            group.leave()
                        })
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        if let error = error {
                            if !((error as NSError).domain == URLError.errorDomain && (error as NSError).code == URLError.cancelled.rawValue) {
                                completionHandler([], error)
                            }
                            return
                        }
                        
                        if waitResult == .timedOut {
                            completionHandler([], self.throwError(path, code: URLError.timedOut))
                            return
                        }
                    }
                    
                    guard let response = String(data: finalData, encoding: .utf8) else {
                        completionHandler([], self.throwError(path, code: URLError.badServerResponse))
                        return
                    }
                    
                    let contents: [String] = response.components(separatedBy: "\n").flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    success = true
                    completionHandler(contents, nil)
                    return
                }
            }) { (response, error) in
                if let error = error {
                    completionHandler([], error)
                    return
                }
                
                guard let response = response else {
                    completionHandler([], self.throwError(path, code: URLError.cannotParseResponse))
                    return
                }
                
                if response.hasPrefix("500") && useMLST {
                    dataTask.cancel()
                    self.serverSupportsRFC3659 = false
                    completionHandler([], self.throwError(path, code: URLError.unsupportedURL))
                    return
                }
                
                if !success && !(response.hasPrefix("25") || response.hasPrefix("15")) {
                    let error = FileProviderFTPError(message: response, path: path)
                    self.dispatch_queue.async {
                        completionHandler([], error)
                    }
                    return
                }
            }
        }
    }
    
    func recursiveList(path: String, useMLST: Bool, foundItemsHandler: ((_ contents: [FileObject]) -> Void)? = nil, completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let progress = Progress(totalUnitCount: 0)
        let queue = DispatchQueue(label: "\(self.type).recursiveList")
        queue.async {
            let group = DispatchGroup()
            var result = [FileObject]()
            var success = true
            group.enter()
            self.contentsOfDirectory(path: path, completionHandler: { (files, error) in
                success = success && (error == nil)
                if let error = error {
                    completionHandler([], error)
                    group.leave()
                    return
                }
                
                result.append(contentsOf: files)
                progress.completedUnitCount = Int64(files.count)
                foundItemsHandler?(files)
                
                let directories: [FileObject] = files.filter { $0.isDirectory }
                progress.becomeCurrent(withPendingUnitCount: Int64(directories.count))
                for dir in directories {
                    group.enter()
                    _=self.recursiveList(path: dir.path, useMLST: useMLST, foundItemsHandler: foundItemsHandler, completionHandler: { (contents, error) in
                        success = success && (error == nil)
                        if let error = error {
                            completionHandler([], error)
                            group.leave()
                            return
                        }
                        
                        foundItemsHandler?(files)
                        result.append(contentsOf: contents)
                        
                        group.leave()
                    })
                }
                progress.resignCurrent()
                group.leave()
            })
            group.wait()
            
            if success {
                self.dispatch_queue.async {
                    completionHandler(result, nil)
                }
            }
        }
        return progress
    }
    
    func ftpRetrieveData(_ task: FileProviderStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1, onTask: ((_ task: FileProviderStreamTask) -> Void)?, onProgress: ((_ bytesReceived: Int64, _ totalReceived: Int64, _ expectedBytes: Int64) -> Void)?, completionHandler: @escaping (_ data: Data?, _ error: Error?) -> Void) {
        
        // Check cache
        if useCache, let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL, let cachedResponse = self.cache?.cachedResponse(for: URLRequest(url: url)), cachedResponse.data.count > 0 {
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
                    completionHandler(nil, self.throwError(filePath, code: URLError.badServerResponse))
                    return
                }
                
                // Send retreive command
                let len = 19 /* TYPE response */ + 65 + String(position).characters.count /* REST Response */ + 53 + filePath.characters.count + String(totalSize).characters.count /* RETR open response */ + 26 /* RETR Transfer complete message. */
                self.execute(command: "TYPE I" + "\r\n" + "REST \(position)" + "\r\n" + "RETR \(filePath)", on: task, minLength: len, afterSend: { error in
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
                                completionHandler(nil, self.throwError(filePath, code: URLError.timedOut))
                                return
                            }
                        }
                        
                        if let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL {
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
                        completionHandler(nil, self.throwError(filePath, code: URLError.cannotParseResponse))
                        return
                    }
                    
                    if !(response.hasPrefix("1") || !response.hasPrefix("2")) {
                        let error = FileProviderFTPError(message: response)
                        
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
        if useCache, let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL, let cachedResponse = self.cache?.cachedResponse(for: URLRequest(url: url)), cachedResponse.data.count > 0 {
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
                    completionHandler(nil, self.throwError(filePath, code: URLError.badServerResponse))
                    return
                }
                
                // Send retreive command
                let len = 19 /* TYPE response */ + 65 + String(position).characters.count /* REST Response */ + 53 + filePath.characters.count + String(totalSize).characters.count /* RETR open response */ + 26 /* RETR Transfer complete message. */
                self.execute(command: "TYPE I"  + "\r\n" + "REST \(position)" + "\r\n" + "RETR \(filePath)", on: task, minLength: len, afterSend: { error in
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
                                error = self.throwError("", code: URLError.timedOut)
                                completionHandler(nil, error)
                                return
                            }
                        }
                        
                        if let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL {
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
                        completionHandler(nil, self.throwError(filePath, code: URLError.cannotParseResponse))
                        return
                    }
                    
                    if !(response.hasPrefix("1") || response.hasPrefix("2")) {
                        let error = FileProviderFTPError(message: response)
                        
                        self.dispatch_queue.async {
                            completionHandler(nil, error)
                        }
                        return
                    }
                }
            }
        }
    }
    
    func ftpStore(_ task: FileProviderStreamTask, filePath: String, fromData: Data?, fromFile: URL?, onTask: ((_ task: FileProviderStreamTask) -> Void)?,  onProgress: ((_ bytesSent: Int64, _ totalSent: Int64, _ expectedBytes: Int64) -> Void)?, completionHandler: @escaping (_ error: Error?) -> Void) {
        let timeout = self.session.configuration.timeoutIntervalForRequest
        operation_queue.addOperation {
            guard let size: Int64 = (fromData != nil ? Int64(fromData!.count) : nil) ?? fromFile?.fileSize else { return }
            
            var error: Error?
            let chunkSize: Int
            switch size {
            case 0..<262_144: chunkSize = 32_768 // 0KB To 256KB, page size is 32KB
            case 262_144..<1_048_576: chunkSize = 65_536 // 256KB To 1MB, page size is 64KB
            case 1_048_576..<10_485_760: chunkSize = 131_072 // 1MB To 10MB, page size is 128KB
            case 10_048_576..<33_554_432: chunkSize = 262_144 // 1MB To 10MB, page size is 256KB
            default: chunkSize = 524_288 // Larger than 32MB, page size is 512KB
            }
            
            var fileHandle: FileHandle?
            if let file = fromFile {
                fileHandle = FileHandle(forReadingAtPath: file.path)
            }
            defer {
                fileHandle?.closeFile()
            }
            
            var eof = false
            var sent: Int64 = 0
            
            while !eof {
                let subdata: Data
                if let data = fromData {
                    let endIndex = min(data.count, Int(sent) + chunkSize)
                    eof = endIndex == data.count
                    subdata = data.subdata(in: Int(sent)..<endIndex)
                }else if let fileHandle = fileHandle {
                    subdata = fileHandle.readData(ofLength: chunkSize)
                    eof = Int64(fileHandle.offsetInFile) == size
                } else {
                    return
                }
                if subdata.count == 0 { continue }
                
                let group = DispatchGroup()
                group.enter()
                self.ftpStore(task, data: subdata, to: filePath, from: sent, onTask: onTask, completionHandler: { (serror) in
                    error = serror
                    sent += Int64(subdata.count)
                    group.leave()
                    onProgress?(Int64(subdata.count), sent, size)
                })
                let waitResult = group.wait(timeout: .now() + timeout)
                
                if waitResult == .timedOut {
                    error = self.throwError(filePath, code: URLError.timedOut)
                    completionHandler(error)
                    return
                }
                if let error = error {
                    completionHandler(error)
                    return
                }
            }
            completionHandler(nil)
        }
    }
    
    func ftpStore(_ task: FileProviderStreamTask, data: Data, to filePath: String, from position: Int64, onTask: ((_ task: FileProviderStreamTask) -> Void)?, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.ftpDataConnect(task) { (dataTask, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let dataTask = dataTask else {
                completionHandler(self.throwError(filePath, code: URLError.badServerResponse))
                return
            }
            
            // Send retreive command
            var success = false
            let len = 19 /* TYPE response */ + 65 + String(position).characters.count /* REST Response */ + 44 + filePath.characters.count /* STOR open response */ + 10 /* RETR Transfer complete message. */
            self.execute(command: "TYPE I"  + "\r\n" + "REST \(position)"  + "\r\n" + "STOR \(filePath)", on: task, minLength: len, afterSend: { error in
                // starting passive task
                let timeout = self.session.configuration.timeoutIntervalForRequest
                if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
                    task.startSecureConnection()
                }
                onTask?(dataTask)
                
                if data.count == 0 { return }
                
                dataTask.write(data, timeout: timeout, completionHandler: { (error) in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    success = true
                    
                    dataTask.closeRead()
                    dataTask.closeWrite()
                })
            }) { (response, error) in
                guard success else { return }
                
                if let error = error {
                    completionHandler(error)
                    return
                }
                
                guard let response = response else {
                    completionHandler(self.throwError(filePath, code: URLError.cannotParseResponse))
                    return
                }
                
                if !(response.hasPrefix("1") || response.hasPrefix("2")) {
                    let error = FileProviderFTPError(message: response)
                    
                    self.dispatch_queue.async {
                        completionHandler(error)
                    }
                    return
                }
                
                completionHandler(nil)
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
        var correctedPath: String
        let name: String
        if nameOrPath.hasPrefix("/") {
            correctedPath = nameOrPath.replacingOccurrences(of: baseURL!.path, with: "", options: .anchored)
            name = (nameOrPath as NSString).lastPathComponent
        } else {
            name = nameOrPath
            correctedPath = (path as NSString).appendingPathComponent(nameOrPath)
        }
        if correctedPath.hasPrefix("/") {
            correctedPath.characters.removeFirst()
        }
        
        var attributes = [String: String]()
        for component in components {
            let keyValue = component.components(separatedBy: "=") .flatMap { $0.isEmpty ? nil : $0 }
            guard keyValue.count >= 2, !keyValue[0].isEmpty else { continue }
            attributes[keyValue[0].lowercased()] = keyValue.dropFirst().joined(separator: "=")
        }
        
        let file = FileObject(url: url(of: correctedPath), name: name, path: correctedPath)
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
    
    init(code: Int, path: String, errorDescription: String?) {
        self.code = code
        self.path = path
        self.errorDescription = errorDescription
    }
    
    init(message response: String, path: String = "") {
        let message = response.components(separatedBy: .newlines).last ?? "No Response"
        let spaceIndex = message.characters.index(of: "-") ?? message.characters.index(of: " ") ?? message.startIndex
        self.code = Int(message.substring(to: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        self.path = path
        if code > 0 {
            self.errorDescription = message.substring(from: spaceIndex).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.errorDescription = message
        }
    }
}
