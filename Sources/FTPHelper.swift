//
//  FTPHelper.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation

internal extension FTPFileProvider {
    func execute(command: String, on task: FileProviderStreamTask, minLength: Int = 4,
                 afterSend: ((_ error: Error?) -> Void)? = nil,
                 completionHandler: @escaping (_ response: String?, _ error: Error?) -> Void) {
        let timeout = session.configuration.timeoutIntervalForRequest
        let terminalcommand = command + "\r\n"
        task.write(terminalcommand.data(using: .utf8)!, timeout: timeout) { (error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            if task.state == .suspended {
                task.resume()
            }
            
            self.readData(on: task, minLength: minLength, maxLength: 4096, timeout: timeout, afterSend: afterSend, completionHandler: completionHandler)
        }
    }
    
    func readData(on task: FileProviderStreamTask,
                  minLength: Int = 4, maxLength: Int = 4096, timeout: TimeInterval,
                  afterSend: ((_ error: Error?) -> Void)? = nil,
                  completionHandler: @escaping (_ response: String?, _ error: Error?) -> Void) {
        task.readData(ofMinLength: minLength, maxLength: maxLength, timeout: timeout) { (data, eof, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            
            if let data = data, let response = String(data: data, encoding: .utf8) {
                let lines = response.components(separatedBy: "\n").compactMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let last = lines.last, last.hasPrefix("1") {
                    // 1XX: Need to wait for some other response
                    let timeout = self.session.configuration.timeoutIntervalForResource
                    self.readData(on: task, minLength: minLength, maxLength: maxLength, timeout: timeout, afterSend: afterSend, completionHandler: completionHandler)
                    
                    // Call afterSend
                    afterSend?(error)
                    return
                }
                completionHandler(response.trimmingCharacters(in: .whitespacesAndNewlines), nil)
            } else {
                completionHandler(nil, URLError(.cannotParseResponse, url: self.url(of: "")))
            }
        }
    }
    
    func ftpUserPass(_ task: FileProviderStreamTask, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "USER \(credential?.user ?? "anonymous")", on: task) { (response, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            guard let response = response else {
                completionHandler(URLError(.badServerResponse, url: self.url(of: "")))
                return
            }
            
            // successfully logged in
            if response.hasPrefix("23") {
                completionHandler(nil)
                return
            }
            
            // needs password
            if response.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("33") {
                self.execute(command: "PASS \(self.credential?.password ?? "fileprovider@")", on: task) { (response, error) in
                    if response?.hasPrefix("23") ?? false {
                        completionHandler(nil)
                    } else {
                        let error: Error = response.flatMap(FileProviderFTPError.init(message:)) ?? URLError(.userAuthenticationRequired, url: self.url(of: ""))
                        completionHandler(error)
                    }
                }
                return
            }
            
            let error = FileProviderFTPError(message: response)
            completionHandler(error)
        }
    }
    
    fileprivate func ftpEstablishSecureDataConnection(_ task: FileProviderStreamTask, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "PBSZ 0", on: task, completionHandler: { (response, error) in
            if let error = error {
                completionHandler(error)
                return
            }
            
            let prot = self.securedDataConnection ? "PROT P" : "PROT C"
            self.execute(command: prot, on: task, completionHandler: { (response, error) in
                if let error = error {
                    completionHandler(error)
                    return
                }
                
                completionHandler(nil)
            })
        })
    }
    
    func ftpLogin(_ task: FileProviderStreamTask, completionHandler: @escaping (_ error: Error?) -> Void) {
        let timeout = session.configuration.timeoutIntervalForRequest
        
        var isSecure = false
        // Implicit FTP Connection
        if self.baseURL?.port == 990 || self.baseURL?.scheme == "ftps" {
            task.startSecureConnection()
            isSecure = true
        }
        if task.state == .suspended {
            task.resume()
        }
        
        task.readData(ofMinLength: 4, maxLength: 2048, timeout: timeout) { (data, eof, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let data = data, let response = String(data: data, encoding: .utf8) else {
                    throw URLError(.cannotParseResponse, url: self.url(of: ""))
                }
                
                guard response.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("22") else {
                    throw FileProviderFTPError(message: response)
                }
            } catch {
                completionHandler(error)
                return
            }
            
            if !isSecure && self.baseURL?.scheme == "ftpes" {
                // Explicit FTP Connection, by upgrading connection to FTP/SSL
                self.execute(command: "AUTH TLS", on: task, completionHandler: { (response, error) in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    
                    if let response = response, response.hasPrefix("23") {
                        task.startSecureConnection()
                        isSecure = true
                        self.ftpEstablishSecureDataConnection(task) { error in
                            if let error = error {
                                completionHandler(error)
                                return
                            }
                            
                            self.ftpUserPass(task, completionHandler: completionHandler)
                        }
                    }
                })
            } else if isSecure {
                self.ftpEstablishSecureDataConnection(task) { error in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    
                    self.ftpUserPass(task, completionHandler: completionHandler)
                }
            } else {
                self.ftpUserPass(task, completionHandler: completionHandler)
            }
        }
    }
    
    func ftpPassive(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        func trimmedNumber(_ s : String) -> String {
            return s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        }
        
        self.execute(command: "PASV", on: task) { (response, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let response = response, let destString = response.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ").last else {
                    throw URLError(.badServerResponse, url: self.url(of: ""))
                }
                
                let destArray = destString.components(separatedBy: ",").compactMap({ UInt32(trimmedNumber($0)) })
                guard destArray.count == 6 else {
                    throw URLError(.badServerResponse, url: self.url(of: ""))
                }
                
                // first 4 elements are ip, 2 next are port, as byte
                var host = destArray.prefix(4).compactMap(String.init).joined(separator: ".")
                let portHi = Int(destArray[4]) << 8
                let portLo = Int(destArray[5])
                let port = portHi + portLo
                // IPv6 workaround
                if host == "127.555.555.555" {
                    host = self.baseURL!.host!
                }
                
                let passiveTask = self.session.fpstreamTask(withHostName: host, port: port)
                if self.baseURL?.scheme == "ftps" || self.baseURL?.scheme == "ftpes" || self.baseURL?.port == 990 {
                    passiveTask.serverTrustPolicy = task.serverTrustPolicy
                    passiveTask.startSecureConnection()
                }
                passiveTask.securityLevel = .tlSv1
                passiveTask.resume()
                completionHandler(passiveTask, nil)
            } catch {
                completionHandler(nil, error)
                return
            }
            
        }
    }
    
    func ftpExtendedPassive(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        func trimmedNumber(_ s : String) -> String {
            return s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        }
        
        self.execute(command: "EPSV", on: task) { (response, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let response = response, let destString = response.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ").last else {
                    throw URLError(.badServerResponse, url: self.url(of: ""))
                }
                
                if response.trimmingCharacters(in: .whitespaces).hasPrefix("50") {
                    self.ftpPassive(task, completionHandler: completionHandler)
                    return
                }
                
                let destArray = destString.components(separatedBy: "|")
                guard destArray.count >= 4, let port = Int(trimmedNumber(destArray[3])) else {
                    throw URLError(.badServerResponse, url: self.url(of: ""))
                }
                var host = destArray[2]
                if host.isEmpty {
                    host = self.baseURL?.host ?? ""
                }
                
                let passiveTask = self.session.fpstreamTask(withHostName: host, port: port)
                if self.baseURL?.scheme == "ftps" || self.baseURL?.scheme == "ftpes" || self.baseURL?.port == 990 {
                    passiveTask.serverTrustPolicy = task.serverTrustPolicy
                    passiveTask.startSecureConnection()
                }
                passiveTask.securityLevel = .tlSv1
                passiveTask.resume()
                completionHandler(passiveTask, nil)
            } catch {
                completionHandler(nil, error)
                return
            }
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
        if self.baseURL?.scheme == "ftps" || self.baseURL?.port == 990 {
            activeTask.serverTrustPolicy = task.serverTrustPolicy
            activeTask.startSecureConnection()
        }
        activeTask.resume()
        
        self.execute(command: "PORT \(service.port)", on: task) { (response, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let response = response else {
                    throw URLError(.badServerResponse, url: self.url(of: ""))
                }
                
                guard !response.hasPrefix("5") else {
                    throw URLError(.cannotConnectToHost, url: self.url(of: ""))
                }
                
                completionHandler(activeTask, nil)
            } catch {
                activeTask.cancel()
                completionHandler(nil, error)
            }
        }
    }
    
    func ftpDataConnect(_ task: FileProviderStreamTask, completionHandler: @escaping (_ dataTask: FileProviderStreamTask?, _ error: Error?) -> Void) {
        switch self.mode {
        case .default:
            if self.baseURL?.port == 990 || self.baseURL?.scheme == "ftps" || self.baseURL?.scheme == "ftpes" {
                self.ftpExtendedPassive(task, completionHandler: completionHandler)
            } else {
                self.ftpPassive(task, completionHandler: completionHandler)
            }
        case .passive:
            self.ftpPassive(task, completionHandler: completionHandler)
        case .extendedPassive:
            self.ftpExtendedPassive(task, completionHandler: completionHandler)
        case .active:
            dispatch_queue.async {
                self.ftpActive(task, completionHandler: completionHandler)
            }
        }
    }
    
    func ftpList(_ task: FileProviderStreamTask, of path: String, useMLST: Bool,
                 completionHandler: @escaping (_ contents: [String], _ error: Error?) -> Void) {
        self.ftpDataConnect(task) { (dataTask, error) in

            if let error = error {
                completionHandler([], error)
                return
            }
            
            guard let dataTask = dataTask else {
                completionHandler([], URLError(.badServerResponse, url: self.url(of: path)))
                return
            }
            
            let success_lock = NSLock()
            var success = false
            let command = useMLST ? "MLSD \(path)" : "LIST \(path)"
            self.execute(command: command, on: task) { (response, error) in
                do {
                    if let error = error {
                        throw error
                    }
                    
                    guard let response = response else {
                        throw URLError(.cannotParseResponse, url: self.url(of: path))
                    }
                    
                    if response.hasPrefix("500") && useMLST {
                        dataTask.cancel()
                        self.supportsRFC3659 = false
                        throw URLError(.unsupportedURL, url: self.url(of: path))
                    }
                    
                    let timeout = self.session.configuration.timeoutIntervalForRequest
                    var finalData = Data()
                    var eof = false
                    let error_lock = NSLock()
                    var error: Error?
                    
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        dataTask.readData(ofMinLength: 1, maxLength: Int.max, timeout: timeout) { (data, seof, serror) in
                            if let data = data {
                                finalData.append(data)
                            }
                            eof = seof
                            error_lock.lock()
                            error = serror
                            error_lock.unlock()
                            group.leave()
                        }
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        error_lock.lock()
                        if let error = error {
                            error_lock.unlock()
                            if (error as? URLError)?.code != .cancelled {
                                throw error
                            }
                            return
                        }
                        error_lock.unlock()
                        
                        if waitResult == .timedOut {
                            throw URLError(.timedOut, url: self.url(of: path))
                        }
                    }
                    
                    guard let dataResponse = String(data: finalData, encoding: .utf8) else {
                        throw URLError(.badServerResponse, url: self.url(of: path))
                    }
                    
                    let contents: [String] = dataResponse.components(separatedBy: "\n")
                        .compactMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    success_lock.try()
                    success = true
                    success_lock.unlock()
                    completionHandler(contents, nil)
                    
                    success_lock.try()
                    if !success && !(response.hasPrefix("25") || response.hasPrefix("15")) {
                        success_lock.unlock()
                        throw FileProviderFTPError(message: response, path: path)
                    } else {
                        success_lock.unlock()
                    }
                } catch {
                    self.dispatch_queue.async {
                        completionHandler([], error)
                    }
                }
            }
        }
    }
    
    func recursiveList(path: String, useMLST: Bool, foundItemsHandler: ((_ contents: [FileObject]) -> Void)? = nil,
                       completionHandler: @escaping (_ contents: [FileObject], _ error: Error?) -> Void) -> Progress? {
        let progress = Progress(totalUnitCount: -1)
        let queue = DispatchQueue(label: "\(self.type).recursiveList")
        let group = DispatchGroup()
        queue.async {
            var result = [FileObject]()
            var errorInfo:Error?
            group.enter()
            self.contentsOfDirectory(path: path, completionHandler: { (files, error) in
                if let error = error {
                    errorInfo = error
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
                    _=self.recursiveList(path: dir.path, useMLST: useMLST, foundItemsHandler: foundItemsHandler) {
                        (contents, error) in
                        if let error = error {
                            errorInfo = error
                            group.leave()
                            return
                        }
                        
                        foundItemsHandler?(files)
                        result.append(contentsOf: contents)
                        
                        group.leave()
                    }
                }
                progress.resignCurrent()
                group.leave()
            })
            group.wait()
            
            if let error = errorInfo {
                completionHandler([], error)
            } else {
                self.dispatch_queue.async {
                    completionHandler(result, nil)
                }
            }
        }
        return progress
    }
    
    func ftpRetrieve(_ task: FileProviderStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1, to stream: OutputStream,
                     onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                     onProgress: @escaping (_ data: Data, _ totalReceived: Int64, _ expectedBytes: Int64) -> Void,
                     completionHandler: SimpleCompletionHandler) {
        
        self.attributesOfItem(path: filePath) { (file, error) in
            let totalSize = file?.size ?? -1
            // Retreive data from server
            self.ftpDataConnect(task) { (dataTask, error) in
                if let error = error {
                    completionHandler?(error)
                    return
                }
                
                guard let dataTask = dataTask else {
                    completionHandler?(URLError(.badServerResponse, url: self.url(of: filePath)))
                    return
                }
                
                // Send retreive command
                self.execute(command: "TYPE I" + "\r\n" + "REST \(position)" + "\r\n" + "RETR \(filePath)", on: task) { (response, error) in
                    // starting passive task
                    onTask?(dataTask)
                    
                    defer {
                        dataTask.closeRead()
                        dataTask.closeWrite()
                    }
                    
                    if stream.streamStatus == .notOpen || stream.streamStatus == .closed {
                        stream.open()
                    }
                    
                    let timeout = self.session.configuration.timeoutIntervalForRequest
                    var totalReceived: Int64 = 0
                    var eof = false
                    let error_lock = NSLock()
                    var error: Error?
                    while !eof {
                        let group = DispatchGroup()
                        group.enter()
                        dataTask.readData(ofMinLength: 1, maxLength: Int.max, timeout: timeout) { (data, segeof, segerror) in
                            defer {
                                group.leave()
                            }
                            if let segerror = segerror {
                                error_lock.lock()
                                error = segerror
                                error_lock.unlock()
                                return
                            }
                            if let data = data {
                                var data = data
                                if length > 0, Int64(data.count) + totalReceived > Int64(length) {
                                    data.count = Int(Int64(length) - totalReceived)
                                }
                                totalReceived += Int64(data.count)
                                let dataCount = data.count
                                let result = data.withUnsafeBytes({ p in
                                    stream.write(p, maxLength: dataCount)
                                })
                                if result < 0 {
                                    error_lock.lock()
                                    error = stream.streamError ?? URLError(.cannotWriteToFile, url: self.url(of: filePath))
                                    error_lock.unlock()
                                    eof = true
                                    return
                                }
                                onProgress(data, totalReceived, totalSize)
                            }
                            eof = segeof || (length > 0 && totalReceived >= Int64(length))
                        }
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        error_lock.try()
                        if let error = error {
                            error_lock.unlock()
                            completionHandler?(error)
                            return
                        }
                        error_lock.unlock()
                        
                        if waitResult == .timedOut {
                            completionHandler?(URLError(.timedOut, url: self.url(of: filePath)))
                            return
                        }
                    }
                    
                    completionHandler?(nil)
                    
                    do {
                        if let error = error {
                            throw error
                        }
                        
                        guard let response = response else {
                            throw URLError(.cannotParseResponse, url: self.url(of: filePath))
                        }
                        
                        if !(response.hasPrefix("1") || response.hasPrefix("2")) {
                            throw FileProviderFTPError(message: response)
                        }
                    } catch {
                        self.dispatch_queue.async {
                            completionHandler?(error)
                        }
                    }
                }
            }
        }
    }
    
    func ftpDownloadData(_ task: FileProviderStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1,
                     onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                     onProgress: ((_ data: Data, _ bytesReceived: Int64, _ totalReceived: Int64, _ expectedBytes: Int64) -> Void)?,
                     completionHandler: @escaping (_ data: Data?, _ error: Error?) -> Void) {
        
        // Check cache
        if useCache, let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL, let cachedResponse = self.cache?.cachedResponse(for: URLRequest(url: url)), cachedResponse.data.count > 0 {
            dispatch_queue.async {
                completionHandler(cachedResponse.data, nil)
            }
            return
        }
        
        let stream = OutputStream.toMemory()
        self.ftpRetrieve(task, filePath: filePath, from: position, length: length, to: stream, onTask: onTask, onProgress: { (data, total, expected) in
            onProgress?(data, Int64(data.count), total, expected)
        }) { (error) in
            if let error = error {
                completionHandler(nil, error)
            }
            
            guard let finalData = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
                completionHandler(nil, CocoaError(.fileReadUnknown, path: filePath))
                return
            }
            
            if let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL {
                let urlresponse = URLResponse(url: url, mimeType: nil, expectedContentLength: finalData.count, textEncodingName: nil)
                let cachedResponse = CachedURLResponse(response: urlresponse, data: finalData)
                let request = URLRequest(url: url)
                self.cache?.storeCachedResponse(cachedResponse, for: request)
            }
            completionHandler(finalData, nil)
        }
    }
    
    func ftpDownload(_ task: FileProviderStreamTask, filePath: String, from position: Int64 = 0, length: Int = -1, to stream: OutputStream,
                     onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                     onProgress: ((_ bytesReceived: Int64, _ totalReceived: Int64, _ expectedBytes: Int64) -> Void)?,
                     completionHandler: SimpleCompletionHandler) {
        // Check cache
        if useCache, let url = URL(string: filePath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? filePath, relativeTo: self.baseURL!)?.absoluteURL, let cachedResponse = self.cache?.cachedResponse(for: URLRequest(url: url)), cachedResponse.data.count > 0 {
            dispatch_queue.async {
                let data = cachedResponse.data
                let dataCount = data.count
                stream.open()
                let result = data.withUnsafeBytes({ p in
                    stream.write(p, maxLength: dataCount)
                })
                if result > 0 {
                    completionHandler?(nil)
                } else {
                    completionHandler?(stream.streamError ?? URLError(.cannotWriteToFile, url: self.url(of: filePath)))
                }
                stream.close()
            }
            return
        }
        
        self.ftpRetrieve(task, filePath: filePath, from: position, length: length, to: stream, onTask: onTask, onProgress: { (data, total, expected) in
            onProgress?(Int64(data.count), total, expected)
        }, completionHandler: completionHandler)
    }
    
    func ftpStore(_ task: FileProviderStreamTask, filePath: String, from stream: InputStream, size: Int64,
                  onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                  onProgress: ((_ bytesSent: Int64, _ totalSent: Int64, _ expectedBytes: Int64) -> Void)?,
                  completionHandler: @escaping (_ error: Error?) -> Void) {
        if self.uploadByREST {
            ftpStoreParted(task, filePath: filePath, from: stream, size: size, onTask: onTask, onProgress: onProgress, completionHandler: completionHandler)
        } else {
            ftpStoreSerial(task, filePath: filePath, from: stream, size: size, onTask: onTask, onProgress: onProgress, completionHandler: completionHandler)
        }
    }
    
    func optimizedChunkSize(_ size: Int64) -> Int {
        switch size {
        case 0..<262_144:
            return 32_768 // 0KB To 256KB, chunk size is 32KB
        case 262_144..<1_048_576:
            return 65_536 // 256KB To 1MB, chunk size is 64KB
        case 1_048_576..<10_485_760:
            return 131_072 // 1MB To 10MB, chunk size is 128KB
        case 10_485_760..<33_554_432:
            return 262_144 // 10MB To 32MB, chunk size is 256KB
        default:
            return 524_288 // Larger than 32MB, chunk size is 512KB
        }
    }
    
    func ftpStoreSerial(_ task: FileProviderStreamTask, filePath: String, from stream: InputStream, size: Int64,
                        onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                        onProgress: ((_ bytesSent: Int64, _ totalSent: Int64, _ expectedBytes: Int64) -> Void)?, completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "TYPE I", on: task) { (response, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let response = response else {
                    throw URLError(.cannotParseResponse, url: self.url(of: filePath))
                }
                
                if !response.hasPrefix("2") {
                    throw FileProviderFTPError(message: response)
                }
            } catch {
                completionHandler(error)
                return
            }
            
            self.ftpDataConnect(task) { (dataTask, error) in
                if let error = error {
                    completionHandler(error)
                    return
                }
                
                guard let dataTask = dataTask else {
                    completionHandler(URLError(.badServerResponse, url: self.url(of: filePath)))
                    return
                }
                let success_lock = NSLock()
                var success = false
                
                let completed_lock = NSLock()
                var completed = false
                func completionOnce(completion: () -> ()) {
                    completed_lock.lock()
                    guard !completed else {
                        completed_lock.unlock()
                        return
                    }
                    completion()
                    completed = true
                    completed_lock.unlock()
                }
                
                self.execute(command: "STOR \(filePath)", on: task, afterSend: { error in
                    onTask?(dataTask)
                    
                    let timeout = self.session.configuration.timeoutIntervalForResource
                    var error: Error?
                    
                    let chunkSize = self.optimizedChunkSize(size)
                    let lock = NSLock()
                    var sent: Int64 = 0
                    
                    stream.open()
                    
                    repeat {
                        guard !completed else {
                            return
                        }
                        
                        lock.lock()
                        var subdata = Data.init(count: chunkSize)
                        let count = subdata.withUnsafeMutableBytes { buffer in
                            stream.read(buffer, maxLength: chunkSize)
                        }
                        if count < 0 {
                            lock.unlock()
                            completionOnce {
                                completionHandler(stream.streamError ?? URLError(.requestBodyStreamExhausted, url: self.url(of: filePath)))
                            }
                            return
                        }
                        subdata.count = count
                        lock.unlock()
                        if count == 0 { break }
                        
                        let group = DispatchGroup()
                        group.enter()
                        dataTask.write(subdata, timeout: timeout, completionHandler: { (serror) in
                            lock.lock()
                            if let serror = serror {
                                error = serror
                            } else {
                                sent += Int64(subdata.count)
                                let totalsent = sent
                                let sentbytes = Int64(subdata.count)
                                onProgress?(sentbytes, totalsent, size)
                                print("ftp", filePath, dataTask.countOfBytesSent, dataTask.countOfBytesExpectedToSend, totalsent)
                            }
                            lock.unlock()
                            group.leave()
                        })
                        let waitResult = group.wait(timeout: .now() + timeout)
                        
                        lock.lock()
                        
                        if let error = error {
                            lock.unlock()
                            completionOnce {
                                completionHandler(error)
                            }
                            return
                        }
                        
                        if waitResult == .timedOut {
                            lock.unlock()
                            completionOnce {
                                completionHandler(URLError(.timedOut, url: self.url(of: filePath)))
                            }
                            return
                        }
                        lock.unlock()
                    } while stream.streamStatus != .atEnd
                    
                    success_lock.lock()
                    success = true
                    success_lock.unlock()
                    
                    if self.securedDataConnection {
                        dataTask.stopSecureConnection()
                    }
                    // TOFIX: Close read/write stream for receive a FTP response from the server
                    dataTask.closeRead()
                    dataTask.closeWrite()
                }) { (response, error) in
                    do {
                        if let error = error {
                            throw error
                        }
                        
                        guard let response = response else {
                            throw URLError(.cannotParseResponse, url: self.url(of: filePath))
                        }
                        
                        let lines = response.components(separatedBy: "\n").compactMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if lines.count > 0 {
                            for line in lines {
                                if !(line.hasPrefix("1") || line.hasPrefix("2")) {
                                    // FTP Error Response
                                    throw FileProviderFTPError(message: response)
                                }
                            }
                        }
                        
                        success_lock.lock()
                        if success, let last = lines.last, last.hasPrefix("2") {
                            success_lock.unlock()
                            // File successfully transferred.
                            completionOnce {
                                completionHandler(nil)
                            }
                            return
                        } else {
                            success_lock.unlock()
                            throw URLError(.cannotCreateFile, url: self.url(of: filePath))
                        }
                    } catch {
                        success_lock.lock()
                        if !success {
                            dataTask.cancel()
                        }
                        success_lock.unlock()
                        
                        completionOnce {
                            completionHandler(error)
                        }
                    }
                }
            }
        }
        
        
    }
    
    func ftpStoreParted(_ task: FileProviderStreamTask, filePath: String, from stream: InputStream, size: Int64, from position: Int64 = 0,
                        onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                        onProgress: ((_ bytesSent: Int64, _ totalSent: Int64, _ expectedBytes: Int64) -> Void)?,
                        completionHandler: @escaping (_ error: Error?) -> Void) {
        operation_queue.addOperation {
            let timeout = self.session.configuration.timeoutIntervalForResource
            var error: Error?
            let chunkSize = self.optimizedChunkSize(size)
            
            stream.open()
            defer {
                stream.close()
            }
            var sent: Int64 = position
            repeat {
                var subdata = Data.init(count: chunkSize)
                let count = subdata.withUnsafeMutableBytes { buffer in
                    stream.read(buffer, maxLength: chunkSize)
                }
                if count < 0 {
                    completionHandler(stream.streamError ?? URLError(.requestBodyStreamExhausted, url: self.url(of: filePath)))
                    return
                }
                subdata.count = count
                if count == 0 { break }
                
                let group = DispatchGroup()
                group.enter()
                self.ftpStore(task, data: subdata, to: filePath, from: sent, onTask: onTask, completionHandler: { (serror) in
                    error = serror
                    if serror == nil {
                        sent += Int64(count)
                        group.leave()
                        onProgress?(Int64(count), sent, size)
                    }
                })
                let waitResult = group.wait(timeout: .now() + timeout)
                
                if let error = error {
                    print(error.localizedDescription)
                    completionHandler(error)
                    return
                }
                
                if waitResult == .timedOut {
                    completionHandler(URLError(.timedOut, url: self.url(of: filePath)))
                    return
                }
            } while stream.streamStatus != .atEnd
            completionHandler(nil)
        }
    }
    
    func ftpStore(_ task: FileProviderStreamTask, data: Data, to filePath: String, from position: Int64,
                  onTask: ((_ task: FileProviderStreamTask) -> Void)?,
                  completionHandler: @escaping (_ error: Error?) -> Void) {
        self.execute(command: "TYPE I", on: task) { (response, error) in
            do {
                if let error = error {
                    throw error
                }
                
                guard let response = response else {
                    throw URLError(.cannotParseResponse, url: self.url(of: filePath))
                }
                
                if !response.hasPrefix("2") {
                    throw FileProviderFTPError(message: response)
                }
            } catch {
                completionHandler(error)
                return
            }
            
            self.execute(command: "REST \(position)", on: task, completionHandler: { (response, error) in
                do {
                    if let error = error {
                        throw error
                    }
                    
                    guard let response = response else {
                        throw URLError(.cannotParseResponse, url: self.url(of: filePath))
                    }
                    
                    if !response.hasPrefix("35") {
                        throw FileProviderFTPError(message: response)
                    }
                } catch {
                    completionHandler(error)
                    return
                }
                
                self.ftpDataConnect(task) { (dataTask, error) in
                    if let error = error {
                        completionHandler(error)
                        return
                    }
                    
                    guard let dataTask = dataTask else {
                        completionHandler(URLError(.badServerResponse, url: self.url(of: filePath)))
                        return
                    }
                    
                    // Send retreive command
                    let success_lock = NSLock()
                    var success = false
                    self.execute(command: "STOR \(filePath)", on: task, minLength: 44 + filePath.count + 4, afterSend: { error in
                        // starting passive task
                        let timeout = self.session.configuration.timeoutIntervalForRequest
                        onTask?(dataTask)
                        
                        if data.count == 0 { return }
                        
                        dataTask.write(data, timeout: timeout, completionHandler: { (error) in
                            if let error = error {
                                completionHandler(error)
                                return
                            }
                            success_lock.lock()
                            success = true
                            success_lock.unlock()
                            
                            completionHandler(nil)
                        })
                    }) { (response, error) in
                        success_lock.lock()
                        guard success else {
                            success_lock.unlock()
                            return
                        }
                        success_lock.unlock()
                        
                        do {
                            if let error = error {
                                throw error
                            }
                            
                            guard let response = response else {
                                throw URLError(.cannotParseResponse, url: self.url(of: filePath))
                            }
                            
                            if !(response.hasPrefix("1") || response.hasPrefix("2")) {
                                throw FileProviderFTPError(message: response)
                            }
                        } catch {
                            self.dispatch_queue.async {
                                completionHandler(error)
                            }
                        }
                    }
                }
            })
        }
        
        
    }
    
    func ftpQuit(_ task: FileProviderStreamTask) {
        self.execute(command: "QUIT", on: task) { (_, _) in
            //task.closeRead()
            //task.closeWrite()
        }
    }
    
    func ftpPath(_ apath: String) -> String {
        // path of base url should be concreted into file path! And remove final slash
        let apath = apath.replacingOccurrences(of: "/", with: "", options: [.anchored])
        var path = baseURL!.appendingPathComponent(apath).path.replacingOccurrences(of: "/", with: "", options: [.anchored, .backwards])
        
        // Fixing slashes
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        
        return path
    }
    
    func parseUnixList(_ text: String, in path: String) -> FileObject? {
        let gregorian = Calendar(identifier: .gregorian)
        let nearDateFormatter = DateFormatter()
        nearDateFormatter.calendar = gregorian
        nearDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        nearDateFormatter.dateFormat = "MMM dd hh:mm yyyy"
        let farDateFormatter = DateFormatter()
        farDateFormatter.calendar = gregorian
        farDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        farDateFormatter.dateFormat = "MMM dd yyyy"
        let thisYear = gregorian.component(.year, from: Date())
        
        let components = text.components(separatedBy: " ").compactMap { $0.isEmpty ? nil : $0 }
        guard components.count >= 9 else { return nil }
        let posixPermission = components[0]
        let linksCount = Int(components[1]) ?? 0
        //let owner = components[2]
        //let groupOwner = components[3]
        let size = Int64(components[4]) ?? -1
        let date = components[5..<8].joined(separator: " ")
        let name = components[8..<components.count].joined(separator: " ")
        
        guard name != "." && name != ".." else { return nil }
        let path = path.appendingPathComponent(name).replacingOccurrences(of: "/", with: "", options: .anchored)
        
        let file = FileObject(url: url(of: path), name: name, path: "/" + path)
        #if swift(>=4.0)
        let typeChar = posixPermission.first ?? Character(" ")
        #else
        let typeChar = posixPermission.characters.first ?? Character(" ")
        #endif
        switch String(typeChar) {
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
    
    func parseDOSList(_ text: String, in path: String) -> FileObject? {
        let gregorian = Calendar(identifier: .gregorian)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = gregorian
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "M-d-y hh:mma"
        
        let components = text.components(separatedBy: " ").compactMap { $0.isEmpty ? nil : $0 }
        guard components.count >= 4 else { return nil }
        let size = Int64(components[2]) ?? -1
        let date = components[0..<2].joined(separator: " ")
        let name = components[3..<components.count].joined(separator: " ")
        
        guard name != "." && name != ".." else { return nil }
        let path = path.appendingPathComponent(name).replacingOccurrences(of: "/", with: "", options: .anchored)
        
        let file = FileObject(url: url(of: path), name: name, path: "/" + path)
        file.type = components[2] == "<DIR>" ? .directory : .regular
        file.size = size
        
        if let parsedDate = dateFormatter.date(from: date) {
            file.modifiedDate = parsedDate
        }
        
        return file
    }
    
    func parseMLST(_ text: String, in path: String) -> FileObject? {
        var components = text.components(separatedBy: ";").compactMap { $0.isEmpty ? nil : $0 }
        guard components.count > 1 else { return nil }
        
        let nameOrPath = components.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
        var correctedPath: String
        let name: String
        if nameOrPath.hasPrefix("/") {
            correctedPath = nameOrPath.replacingOccurrences(of: baseURL!.path, with: "", options: .anchored)
            name = nameOrPath.lastPathComponent
        } else {
            name = nameOrPath
            correctedPath = path.appendingPathComponent(nameOrPath)
        }
        correctedPath = correctedPath.replacingOccurrences(of: "/", with: "", options: .anchored)
        
        var attributes = [String: String]()
        for component in components {
            let keyValue = component.components(separatedBy: "=").compactMap { $0.isEmpty ? nil : $0 }
            guard keyValue.count >= 2, !keyValue[0].isEmpty else { continue }
            attributes[keyValue[0].lowercased()] = keyValue.dropFirst().joined(separator: "=")
        }
        
        let file = FileObject(url: url(of: correctedPath), name: name, path: "/" + correctedPath)
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
public struct FileProviderFTPError: LocalizedError {
    /// HTTP status code returned for error by server.
    public let code: Int
    /// Path of file/folder casued that error
    public let path: String
    /// Contents returned by server as error description
    public let serverDescription: String?
    
    init(code: Int, path: String, serverDescription: String?) {
        self.code = code
        self.path = path
        self.serverDescription = serverDescription
    }
    
    init(message  response: String) {
        self.init(message: response, path: "")
    }
    
    init(message response: String, path: String) {
        let message = response.components(separatedBy: .newlines).last ?? "No Response"
        #if swift(>=4.0)
        let startIndex = (message.index(of: "-") ?? message.index(of: " ")) ?? message.startIndex
        self.code = Int(message[..<startIndex].trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        #else
        let startIndex = (message.characters.index(of: "-") ?? message.characters.index(of: " ")) ?? message.startIndex
        self.code = Int(message.substring(to: startIndex).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        #endif
        self.path = path
        if code > 0 {
            #if swift(>=4.0)
            self.serverDescription = message[startIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            #else
            self.serverDescription = message.substring(from: startIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            #endif
        } else {
            self.serverDescription = message
        }
    }
    
    public var errorDescription: String? {
        return serverDescription
    }
}
