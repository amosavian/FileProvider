//
//  FPSStreamTask.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

private var lasttaskIdAssociated = 1_000_000_000


/// This class is a replica of NSURLSessionStreamTask with same api for iOS 7/8
/// while it will fallback to NSURLSessionStreamTask in iOS 9.
internal class FPSStreamTask: URLSessionTask, StreamDelegate {
    fileprivate var inputStream: InputStream?
    fileprivate var outputStream: OutputStream?
    
    fileprivate var operation_queue: OperationQueue!
    internal var _underlyingSession: URLSession
    fileprivate var streamDelegate: FPSStreamDelegate? {
        return (_underlyingSession.delegate as? FPSStreamDelegate)
    }
    fileprivate var _taskIdentifier: Int
    
    public var useURLSession = true
    @available(iOS 9.0, OSX 10.11, *)
    static var streamTasks = [Int: URLSessionStreamTask]()
    
    @available(iOS 9.0, OSX 10.11, *)
    internal var _underlyingTask: URLSessionStreamTask? {
        return FPSStreamTask.streamTasks[_taskIdentifier]
    }
    
    open override var taskIdentifier: Int {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.taskIdentifier
            }
        }
        
        return _taskIdentifier
    }
    
    fileprivate var _state: URLSessionTask.State = .suspended
    override open var state: URLSessionTask.State {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.state
            }
        }
        
        return _state
    }
    
    override open var originalRequest: URLRequest? {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.originalRequest
            }
        }
        
        return nil
    }
    
    override open var currentRequest: URLRequest? {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.currentRequest
        } else {
            return nil
        }
    }
    
    fileprivate var _countOfBytesSent: Int64 = 0
    fileprivate var _countOfBytesRecieved: Int64 = 0
    
    override open var countOfBytesSent: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesSent
            }
        }
        
        return _countOfBytesSent
    }
    
    override open var countOfBytesReceived: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesReceived
            }
        }
        
        return _countOfBytesRecieved
    }
    
    override open var countOfBytesExpectedToSend: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesExpectedToSend
        } else {
            return Int64(dataToBeSent.count)
        }
    }
    
    override open var countOfBytesExpectedToReceive: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesExpectedToReceive
            }
        }
        
        return Int64(dataReceived.count)
    }
    
    override public init() {
        fatalError("Use NSURLSession.fpstreamTask() method")
    }
    
    var host: (hostname: String, port: Int)?
    var service: NetService?
    
    internal init(session: URLSession, host: String, port: Int) {
        self._underlyingSession = session
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                let task = session.streamTask(withHostName: host, port: port)
                self._taskIdentifier = task.taskIdentifier
                FPSStreamTask.streamTasks[_taskIdentifier] = task
                return
            }
        }
        
        lasttaskIdAssociated += 1
        self._taskIdentifier = lasttaskIdAssociated
        self.host = (host, port)
        self.operation_queue = OperationQueue()
        self.operation_queue.name = "FPSStreamTask"
        self.operation_queue.maxConcurrentOperationCount = 1
    }
    
    internal init(session: URLSession, netService: NetService) {
        self._underlyingSession = session
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                let task = session.streamTask(with: netService)
                self._taskIdentifier = task.taskIdentifier
                FPSStreamTask.streamTasks[_taskIdentifier] = task
                return
            }
        }
        
        lasttaskIdAssociated += 1
        self._taskIdentifier = lasttaskIdAssociated
        self.service = netService
        self.operation_queue = OperationQueue()
        self.operation_queue.name = "FPSStreamTask"
        self.operation_queue.maxConcurrentOperationCount = 1
    }
    
    override open func cancel() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.cancel()
                return
            }
        }
        
        self._state = .canceling
        inputStream?.setValue(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as String)
        outputStream?.setValue(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as String)
        
        self.inputStream?.close()
        self.outputStream?.close()
        
        self.inputStream?.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        self.outputStream?.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        
        self.inputStream?.delegate = nil
        self.outputStream?.delegate = nil
        
        self.inputStream = nil
        self.outputStream = nil
        
        self._state = .completed
        self._countOfBytesSent = 0
        self._countOfBytesRecieved = 0
    }
    
    var _error: Error? = nil
    override open var error: Error? {
        if #available(iOS 9.0, OSX 10.11, *) {
            if useURLSession {
                return _underlyingTask!.error
            }
        }
        
        return _error
    }
    
    override open func suspend() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.suspend()
                return
            }
        }
        
        self._state = .suspended
        self.operation_queue.isSuspended = true
    }
    
    override open func resume() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.resume()
                return
            }
        }
        
        var readStream : Unmanaged<CFReadStream>?
        var writeStream : Unmanaged<CFWriteStream>?
        
        if inputStream == nil || outputStream == nil {
            if let host = host {
                let hostRef: CFString = NSString(string: host.hostname)
                CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, hostRef, UInt32(host.port), &readStream, &writeStream)
            } else if let service = service {
                let cfnetService = CFNetServiceCreate(kCFAllocatorDefault, service.domain as CFString, service.type as CFString, service.name as CFString, Int32(service.port))
                CFStreamCreatePairWithSocketToNetService(kCFAllocatorDefault, cfnetService.takeRetainedValue(), &readStream, &writeStream)
            }
            
            inputStream = readStream?.takeRetainedValue()
            outputStream = writeStream?.takeRetainedValue()
            guard let inputStream = inputStream, let outputStream = outputStream else {
                return
            }
            streamDelegate?.urlSession?(self._underlyingSession, streamTask: self, didBecome: inputStream, outputStream: outputStream)
        }
        
        guard let inputStream = inputStream, let outputStream = outputStream else {
            return
        }
        
        inputStream.delegate = self
        outputStream.delegate = self
        
        operation_queue.addOperation {
            inputStream.schedule(in: RunLoop.main, forMode: .defaultRunLoopMode)
            outputStream.schedule(in: RunLoop.main, forMode: .defaultRunLoopMode)
        }
        
        inputStream.open()
        outputStream.open()
        
        operation_queue.isSuspended = false
        _state = .running
    }
    
    fileprivate var dataToBeSent: Data = Data()
    fileprivate var dataReceived: Data = Data()
    
    /* Read minBytes, or at most maxBytes bytes and invoke the completion
     * handler on the sessions delegate queue with the data or an error.
     * If an error occurs, any outstanding reads will also fail, and new
     * read requests will error out immediately.
     */
    open func readData(ofMinLength minBytes: Int, maxLength maxBytes: Int, timeout: TimeInterval, completionHandler: @escaping (Data?, Bool, Error?) -> Void) {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.readData(ofMinLength: minBytes, maxLength: maxBytes, timeout: timeout, completionHandler: completionHandler)
                return
            }
        }
        
        guard let inputStream = inputStream else {
            return
        }
        
        let expireDate = Date(timeIntervalSinceNow: timeout)
        operation_queue.addOperation {
            var timedOut: Bool = false
            while (self.dataReceived.count == 0 || self.dataReceived.count < minBytes) && !timedOut {
                Thread.sleep(forTimeInterval: 0.1)
                timedOut = expireDate < Date()
            }
            var dR: Data?
            if self.dataReceived.count > maxBytes {
                let range: Range = 0..<maxBytes
                dR = self.dataReceived.subdata(in: range)
                self.dataReceived.replaceSubrange(range, with: Data())
            } else {
                if self.dataReceived.count > 0 {
                    dR = self.dataReceived
                    self.dataReceived.count = 0
                }
            }
            let isEOF = inputStream.streamStatus == .atEnd && self.dataReceived.count == 0
            completionHandler(dR, isEOF, dR == nil ? inputStream.streamError : nil)
        }
    }
    
    /* Write the data completely to the underlying socket.  If all the
     * bytes have not been written by the timeout, a timeout error will
     * occur.  Note that invocation of the completion handler does not
     * guarantee that the remote side has received all the bytes, only
     * that they have been written to the kernel. */
    open func write(_ data: Data, timeout: TimeInterval, completionHandler: @escaping (Error?) -> Void) {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.write(data, timeout: timeout, completionHandler: completionHandler)
                return
            }
        }
        
        guard outputStream != nil else {
            return
        }
        
        
        operation_queue.addOperation {
            self.dataToBeSent.append(data)
            let result = self.write(timeout: timeout, close: false)
            if result < 0 {
                let error = self.outputStream?.streamError ?? NSError(domain: URLError.errorDomain, code: URLError.cannotWriteToFile.rawValue, userInfo: nil)
                completionHandler(error)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    /* -captureStreams completes any already enqueued reads
     * and writes, and then invokes the
     * URLSession:streamTask:didBecomeInputStream:outputStream: delegate
     * message. When that message is received, the task object is
     * considered completed and will not receive any more delegate
     * messages. */
    open func captureStreams() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.captureStreams()
                return
            }
        }
        
        guard let outputStream = outputStream, let inputStream = inputStream else {
            return
        }
        self.operation_queue.addOperation {
            self.write(close: false)
            while inputStream.streamStatus != .atEnd {
                Thread.sleep(forTimeInterval: 0.1)
            }
            self.streamDelegate?.urlSession?(self._underlyingSession, streamTask: self, didBecome: inputStream, outputStream: outputStream)
        }
    }
    
    /* Enqueue a request to close the write end of the underlying socket.
     * All outstanding IO will complete before the write side of the
     * socket is closed.  The server, however, may continue to write bytes
     * back to the client, so best practice is to continue reading from
     * the server until you receive EOF.
     */
    open func closeWrite() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.closeWrite()
                return
            }
        }
        
        operation_queue.addOperation {
            _ = self.write(close: true)
        }
    }
    
    @discardableResult
    fileprivate func write(timeout: TimeInterval = 0, close: Bool) -> Int {
        guard let outputStream = outputStream else {
            return -1
        }
        
        var byteSent: Int = 0
        let expireDate = Date(timeIntervalSinceNow: timeout)
        while self.dataToBeSent.count > 0 && (timeout == 0 || expireDate > Date()) {
            let bytesWritten = self.dataToBeSent.withUnsafeBytes {
                outputStream.write($0, maxLength: self.dataToBeSent.count)
            }
            
            if bytesWritten > 0 {
                let range = 0..<bytesWritten
                self.dataToBeSent.replaceSubrange(range, with: Data())
                byteSent += bytesWritten
            } else if bytesWritten < 0 {
                self._error = outputStream.streamError
                return bytesWritten
            }
            if self.dataToBeSent.count == 0 {
                break
            }
        }
        self._countOfBytesSent += Int64(byteSent)
        if close {
            outputStream.close()
            self.streamDelegate?.urlSession?(self._underlyingSession, writeClosedFor: self)
        }
        return byteSent
    }
    
    /* Enqueue a request to close the read side of the underlying socket.
     * All outstanding IO will complete before the read side is closed.
     * You may continue writing to the server.
     */
    open func closeRead() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.closeRead()
                return
            }
        }
        
        guard let inputStream = inputStream else {
            return
        }
        operation_queue.addOperation {
            while inputStream.streamStatus != .atEnd {
                Thread.sleep(forTimeInterval: 0.1)
            }
            inputStream.close()
            self.streamDelegate?.urlSession?(self._underlyingSession, readClosedFor: self)
        }
    }
    
    /*
     * Begin encrypted handshake.  The hanshake begins after all pending
     * IO has completed.  TLS authentication callbacks are sent to the
     * session's -URLSession:task:didReceiveChallenge:completionHandler:
     */
    open func startSecureConnection() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.startSecureConnection()
                return
            }
        }
        
        operation_queue.addOperation {
            self.inputStream!.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue, forKey: .socketSecurityLevelKey)
            self.outputStream!.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue, forKey: .socketSecurityLevelKey)
        }
    }
    
    /*
     * Cleanly close a secure connection after all pending secure IO has
     * completed.
     */
    open func stopSecureConnection() {
        if #available(iOS 9.0, OSX 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.stopSecureConnection()
                return
            }
        }
        operation_queue.addOperation {
            self.inputStream!.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
            self.outputStream!.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
        }
    }
    
    open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch (eventCode) {
        case Stream.Event.errorOccurred:
            self._error = aStream.streamError
            streamDelegate?.urlSession?(_underlyingSession, task: self, didCompleteWithError: error)
        case Stream.Event.endEncountered:
            break
        case Stream.Event():
            break
        case Stream.Event.openCompleted:
            break
        case Stream.Event.hasBytesAvailable:
            var buffer = [UInt8](repeating: 0, count: 2048)
            if (aStream == inputStream) {
                while (inputStream!.hasBytesAvailable) {
                    let len = inputStream!.read(&buffer, maxLength: buffer.count)
                    if len > 0 {
                        dataReceived.append(&buffer, count: len)
                        self._countOfBytesRecieved += Int64(len)
                    }
                }
            }
        case Stream.Event.hasSpaceAvailable:
            break
        default:
            break
        }
    }
}

internal extension URLSession {
    /* Creates a bidirectional stream task to a given host and port.
     */
    func fpstreamTask(withHostName hostname: String, port: Int) -> FPSStreamTask {
        return FPSStreamTask(session: self, host: hostname, port: port)
    }
    
    /* Creates a bidirectional stream task with an NSNetService to identify the endpoint.
     * The NSNetService will be resolved before any IO completes.
     */
    func fpstreamTask(withNetService service: NetService) -> FPSStreamTask {
        return fpstreamTask(withNetService: service)
    }
}

@objc
internal protocol FPSStreamDelegate : URLSessionTaskDelegate {
    
    
    /* Indiciates that the read side of a connection has been closed.  Any
     * outstanding reads complete, but future reads will immediately fail.
     * This may be sent even when no reads are in progress. However, when
     * this delegate message is received, there may still be bytes
     * available.  You only know that no more bytes are available when you
     * are able to read until EOF. */
    @objc optional func urlSession(_ session: URLSession, readClosedFor streamTask: FPSStreamTask)
    
    
    /* Indiciates that the write side of a connection has been closed.
     * Any outstanding writes complete, but future writes will immediately
     * fail.
     */
    @objc optional func urlSession(_ session: URLSession, writeClosedFor streamTask: FPSStreamTask)
    
    
    /* A notification that the system has determined that a better route
     * to the host has been detected (eg, a wi-fi interface becoming
     * available.)  This is a hint to the delegate that it may be
     * desirable to create a new task for subsequent work.  Note that
     * there is no guarantee that the future task will be able to connect
     * to the host, so callers should should be prepared for failure of
     * reads and writes over any new interface. */
    @objc optional func urlSession(_ session: URLSession, betterRouteDiscoveredFor streamTask: FPSStreamTask)
    
    
    /* The given task has been completed, and unopened NSInputStream and
     * NSOutputStream objects are created from the underlying network
     * connection.  This will only be invoked after all enqueued IO has
     * completed (including any necessary handshakes.)  The streamTask
     * will not receive any further delegate messages.
     */
    @objc optional func urlSession(_ session: URLSession, streamTask: FPSStreamTask, didBecome inputStream: InputStream, outputStream: OutputStream)
}

private let ports: [String: Int] = ["http": 80, "https": 443, "smb": 445,"ftp": 21,"ftps": 22, "sftp": 2121,
                                    "telnet": 23, "pop": 110, "smtp": 25, "imap": 143]
private let securePorts: [String: Int] =  ["https": 443, "smb": 445, "ftps": 22, "sftp": 2121,
                                           "telnet": 992, "pop": 995, "smtp": 465, "imap": 993]
