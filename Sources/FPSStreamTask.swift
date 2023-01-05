//
//  FPSStreamTask.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

private var _lasttaskIdAssociated = 1_000_000_000
let _lasttaskIdAssociated_lock: NSLock = NSLock()
var lasttaskIdAssociated: Int {
    get {
        _lasttaskIdAssociated_lock.lock()
        defer {
            _lasttaskIdAssociated_lock.unlock()
        }
        return _lasttaskIdAssociated
    }
    set {
        _lasttaskIdAssociated_lock.lock()
        defer {
            _lasttaskIdAssociated_lock.unlock()
        }
        _lasttaskIdAssociated = newValue
    }
}

// codebeat:disable[TOTAL_LOC,TOO_MANY_IVARS]
/// This class is a replica of NSURLSessionStreamTask with same api for iOS 7/8
/// while it can actually fallback to NSURLSessionStreamTask in iOS 9.
public class FileProviderStreamTask: URLSessionTask, StreamDelegate {
    fileprivate var inputStream: InputStream?
    fileprivate var outputStream: OutputStream?
    
    fileprivate let dataToBeSentLock = NSLock()
    fileprivate var dataToBeSent: Data = Data()
    fileprivate let dataReceivedLock = NSLock()
    fileprivate var dataReceived: Data = Data()
    
    fileprivate var _error: Error? = nil
    fileprivate var isSecure = false
    public var securityLevel: StreamSocketSecurityLevel = .negotiatedSSL
    
    fileprivate var dispatch_queue: DispatchQueue!
    internal var _underlyingSession: URLSession
    fileprivate var host: (hostname: String, port: Int)?
    fileprivate var service: NetService?
    fileprivate var streamDelegate: FPSStreamDelegate? {
        return (_underlyingSession.delegate as? FPSStreamDelegate)
    }
    
    internal static let defaultUseURLSession = false
    
    fileprivate var _taskIdentifier: Int
    fileprivate var _taskDescription: String?
    
    var observers: [(keyPath: String, observer: NSObject, context: UnsafeMutableRawPointer?)] = []
    
    /// Force using `URLSessionStreamTask` for iOS 9 and later
    public let useURLSession: Bool
    @available(iOS 9.0, macOS 10.11, *)
    fileprivate static var streamTasks = [Int: URLSessionStreamTask]()
    
    @available(iOS 9.0, macOS 10.11, *)
    internal var _underlyingTask: URLSessionStreamTask? {
        return FileProviderStreamTask.streamTasks[_taskIdentifier]
    }
    
    /// The end of the stream has been reached.
    private var endEncountered: Bool = false
    
    /// Trust all certificates if `disableEvaluation`, Otherwise validate certificate chain.
    public var serverTrustPolicy: ServerTrustPolicy = .performDefaultEvaluation(validateHost: true)
    
    /// A pointer to a buffer containing the peer ID data to set.
    var peerID: UnsafeRawPointer? = nil
    /// The length of the peer ID data buffer.
    var peerIDLen: Int = 0
    
    /**
     * An identifier uniquely identifies the task within a given session.
     *
     * This value is unique only within the context of a single session;
     * tasks in other sessions may have the same `taskIdentifier` value.
     */
    open override var taskIdentifier: Int {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.taskIdentifier
            }
        }
        
        return _taskIdentifier
    }
    
    /// An app-provided description of the current task.
    ///
    /// This value may be nil. It is intended to contain human-readable strings that you can
    /// then display to the user as part of your app’s user interface.
    open override var taskDescription: String? {
        get {
            if #available(iOS 9.0, macOS 10.11, *) {
                if self.useURLSession {
                    return _underlyingTask!.taskDescription
                }
            }
            
            return _taskDescription
        }
        @objc(setTaskDescription:)
        set {
            if #available(iOS 9.0, macOS 10.11, *) {
                if self.useURLSession {
                    _underlyingTask!.taskDescription = newValue
                    return
                }
            }
            
            _taskDescription = newValue
        }
    }
    
    fileprivate var _state: URLSessionTask.State = .suspended
    /**
     * The current state of the task—active, suspended, in the process
     * of being canceled, or completed.
     */
    override open var state: URLSessionTask.State {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.state
            }
        }
        
        return _state
    }
    
    /**
     * The original request object passed when the task was created.
     * This value is typically the same as the currently active request (`currentRequest`)
     * except when the server has responded to the initial request with a redirect to a different URL.
     */
    override open var originalRequest: URLRequest? {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.originalRequest
            }
        }
        
        return nil
    }
    
    /**
     * The URL request object currently being handled by the task.
     * This value is typically the same as the initial request (`originalRequest`)
     * except when the server has responded to the initial request with a redirect to a different URL.
     */
    override open var currentRequest: URLRequest? {
        if #available(iOS 9.0, macOS 10.11, *) {
            return _underlyingTask!.currentRequest
        } else {
            return nil
        }
    }
    
    fileprivate var _countOfBytesSent: Int64 = 0 {
        willSet {
            for observer in observers where observer.keyPath == "countOfBytesSent" {
                observer.observer.observeValue(forKeyPath: observer.keyPath, of: self, change: [.oldKey: _countOfBytesSent, .oldKey: newValue], context: observer.context)
            }
        }
        didSet {
            for observer in observers where observer.keyPath == "countOfBytesSent" {
                observer.observer.observeValue(forKeyPath: observer.keyPath, of: self, change: [.oldKey: oldValue, .oldKey: _countOfBytesSent], context: observer.context)
            }
        }
    }
    
    fileprivate var _countOfBytesRecieved: Int64 = 0 {
        willSet {
            for observer in observers where observer.keyPath == "countOfBytesRecieved" {
                observer.observer.observeValue(forKeyPath: observer.keyPath, of: self, change: [.oldKey: _countOfBytesRecieved, .oldKey: newValue], context: observer.context)
            }
        }
        didSet {
            for observer in observers where observer.keyPath == "countOfBytesRecieved" {
                observer.observer.observeValue(forKeyPath: observer.keyPath, of: self, change: [.oldKey: oldValue, .oldKey: _countOfBytesRecieved], context: observer.context)
            }
        }
    }
    
    /**
     * The number of bytes that the task has sent to the server in the request body.
     *
     * This byte count includes only the length of the request body itself, not the request headers.
     *
     * To be notified when this value changes, implement the
     * `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` delegate method.
     */
    override open var countOfBytesSent: Int64 {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesSent
            }
        }
        
        self.dataToBeSentLock.lock()
        defer {
            self.dataToBeSentLock.unlock()
        }
        return _countOfBytesSent
    }
    
    /**
     * The number of bytes that the task has received from the server in the response body.
     *
     * To be notified when this value changes, implement the `urlSession(_:dataTask:didReceive:)` delegate method (for data and upload tasks)
     * or the `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)` method (for download tasks).
     */
    override open var countOfBytesReceived: Int64 {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesReceived
            }
        }
        
        dataReceivedLock.lock()
        defer {
            dataReceivedLock.unlock()
        }
        return _countOfBytesRecieved
    }
    
    /**
     * The number of bytes that the task expects to send in the request body.
     *
     * The `URL` loading system can determine the length of the upload data in three ways:
     * - From the length of the `NSData` object provided as the upload body.
     * - From the length of the file on disk provided as the upload body of an upload task (not a download task).
     * - From the `Content-Length` in the request object, if you explicitly set it.
     *
     * Otherwise, the value is `NSURLSessionTransferSizeUnknown` (`-1`) if you provided a stream or body data object, or zero (`0`) if you did not.
     */
    override open var countOfBytesExpectedToSend: Int64 {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesExpectedToSend
            }
        }
        
        self.dataToBeSentLock.lock()
        defer {
            self.dataToBeSentLock.unlock()
        }
        return Int64(dataToBeSent.count) + _countOfBytesSent
    }
    
    /**
     * The number of bytes that the task expects to receive in the response body.
     *
     * This value is determined based on the `Content-Length` header received from the server.
     * If that header is absent, the value is `NSURLSessionTransferSizeUnknown`.
     */
    override open var countOfBytesExpectedToReceive: Int64 {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                return _underlyingTask!.countOfBytesExpectedToReceive
            }
        }
        
        dataReceivedLock.lock()
        defer {
            dataReceivedLock.unlock()
        }
        return Int64(dataReceived.count)
    }
    
    override public init() {
        fatalError("Use NSURLSession.fpstreamTask() method")
    }
    
    internal init(session: URLSession, host: String, port: Int, useURLSession: Bool = defaultUseURLSession) {
        self._underlyingSession = session
        self.useURLSession = useURLSession
        if #available(iOS 9.0, macOS 10.11, *) {
            if useURLSession {
                let task = session.streamTask(withHostName: host, port: port)
                self._taskIdentifier = task.taskIdentifier
                FileProviderStreamTask.streamTasks[_taskIdentifier] = task
                return
            }
        }
        
        lasttaskIdAssociated += 1
        self._taskIdentifier = lasttaskIdAssociated
        self.host = (host, port)
        self.dispatch_queue = DispatchQueue(label: "FileProviderStreamTask")
        self.dispatch_queue.suspend()
    }
    
    internal init(session: URLSession, netService: NetService, useURLSession: Bool = defaultUseURLSession) {
        self._underlyingSession = session
        self.useURLSession = useURLSession
        if #available(iOS 9.0, macOS 10.11, *) {
            if useURLSession {
                let task = session.streamTask(with: netService)
                self._taskIdentifier = task.taskIdentifier
                FileProviderStreamTask.streamTasks[_taskIdentifier] = task
                return
            }
        }
        
        lasttaskIdAssociated += 1
        self._taskIdentifier = lasttaskIdAssociated
        self.service = netService
        self.dispatch_queue = DispatchQueue(label: "FileProviderStreamTask")
        self.dispatch_queue.suspend()
    }
    
    deinit {
        if !self.useURLSession {
            finish()
        }
    }
    
    /**
     * An error object that indicates why the task failed.
     *
     * This value is `NULL` if the task is still active or if the transfer completed successfully.
     */
    override open var error: Error? {
        if #available(iOS 9.0, macOS 10.11, *) {
            if useURLSession {
                return _underlyingTask!.error
            }
        }
        
        return _error
    }
    
    /**
     * Cancels the task.
     *
     * This method returns immediately, marking the task as being canceled. Once a task is marked as being canceled,
     * `urlSession(_:task:didCompleteWithError:)` will be sent to the task delegate, passing an error
     * in the domain NSURLErrorDomain with the code `NSURLErrorCancelled`. A task may, under some circumstances,
     * send messages to its delegate before the cancelation is acknowledged.
     *
     * This method may be called on a task that is suspended.
     */
    override open func cancel() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.cancel()
                return
            }
        }
        
        self._state = .canceling
        
        dispatch_queue.async {
            self.finish()
            
            self._state = .completed
            self._countOfBytesSent = 0
            self._countOfBytesRecieved = 0
        }
    }
    
    /**
     * Temporarily suspends a task.
     *
     * A task, while suspended, produces no network traffic and is not subject to timeouts.
     * A download task can continue transferring data at a later time.
     * All other tasks must start over when resumed.
     */
    override open func suspend() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.suspend()
                return
            }
        }
        
        if self._state == .running {
            self._state = .suspended
            self.dispatch_queue.suspend()
        }
    }
    
    // Resumes the task, if it is suspended.
    override open func resume() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.resume()
                return
            }
        }
        
        if inputStream == nil || outputStream == nil {
            if let host = host {
                Stream.getStreamsToHost(withName: host.hostname, port: host.port, inputStream: &self.inputStream, outputStream: &self.outputStream)
            } else if let service = service {
                var readStream : Unmanaged<CFReadStream>?
                var writeStream : Unmanaged<CFWriteStream>?
                let cfnetService = CFNetServiceCreate(kCFAllocatorDefault, service.domain as CFString, service.type as CFString, service.name as CFString, Int32(service.port))
                CFStreamCreatePairWithSocketToNetService(kCFAllocatorDefault, cfnetService.takeRetainedValue(), &readStream, &writeStream)
                inputStream = readStream?.takeRetainedValue()
                outputStream = writeStream?.takeRetainedValue()
            }
            
            
            guard let inputStream = inputStream, let outputStream = outputStream else {
                return
            }
            streamDelegate?.urlSession?(self._underlyingSession, streamTask: self, didBecome: inputStream, outputStream: outputStream)
        }
        
        guard let inputStream = inputStream, let outputStream = outputStream else {
            return
        }
        
        if isSecure {
            inputStream.setProperty(securityLevel.rawValue, forKey: .socketSecurityLevelKey)
            outputStream.setProperty(securityLevel.rawValue, forKey: .socketSecurityLevelKey)

            if serverTrustPolicy.evaluate() {
                // ※ Called, After setProperty securityLevel
                addTrustAllCertificatesSettings()
            }
            
            inputStream.setSSLPeerID(peerID: peerID, peerIDLen: peerIDLen)
        } else {
            inputStream.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
            outputStream.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
        }
        
        inputStream.delegate = self
        outputStream.delegate = self
        
        #if swift(>=4.2)
        inputStream.schedule(in: RunLoop.main, forMode: .common)
        #else
        inputStream.schedule(in: RunLoop.main, forMode: .commonModes)
        #endif
        //outputStream.schedule(in: RunLoop.main, forMode: .init("kCFRunLoopDefaultMode"))
        
        inputStream.open()
        outputStream.open()
        
        if self._state == .suspended {
            dispatch_queue.resume()
            _state = .running
        }
    }
    
    /**
     * Asynchronously reads a number of bytes from the stream, and calls a handler upon completion.
     *
     * - Parameter minBytes: The minimum number of bytes to read.
     * - ParametermaxBytes: The maximum number of bytes to read.
     * - Parameter timeout:  A timeout for reading bytes. If the read is not completed within the specified interval,
     *        the read is canceled and the completionHandler is called with an error. Pass `0` to prevent a read from timing out.
     * - Parameter completionHandler: The completion handler to call when all bytes are read, or an error occurs.
     *        This handler is executed on the delegate queue. This completion handler takes the following parameters:
     * - Parameter data: The data read from the stream.
     * - Parameter atEOF: Whether or not the stream reached end-of-file (`EOF`), such that no more data can be read.
     * - Parameter error: An error object that indicates why the read failed, or `nil` if the read was successful.
     */
    open func readData(ofMinLength minBytes: Int, maxLength maxBytes: Int, timeout: TimeInterval, completionHandler: @escaping (_ data: Data?, _ atEOF: Bool, _ error :Error?) -> Void) {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.readData(ofMinLength: minBytes, maxLength: maxBytes, timeout: timeout, completionHandler: completionHandler)
                return
            }
        }
        
        guard let inputStream = inputStream else {
            return
        }
        
        let expireDate = Date(timeIntervalSinceNow: timeout)
        dispatch_queue.async {
            var timedOut: Bool = false
            self.dataReceivedLock.lock()
            while (self.dataReceived.count == 0 || self.dataReceived.count < minBytes) && !timedOut && !self.endEncountered {
                self.dataReceivedLock.unlock()
                Thread.sleep(forTimeInterval: 0.1)
                if let error = inputStream.streamError {
                    completionHandler(nil, inputStream.streamStatus == .atEnd, error)
                    return
                }
                timedOut = expireDate < Date()
                self.dataReceivedLock.lock()
            }
            self.endEncountered = false
            var dR: Data?
            if self.dataReceived.count > maxBytes {
                let range: Range = 0..<maxBytes
                dR = self.dataReceived.subdata(in: range)
                self.dataReceived.removeFirst(maxBytes)
            } else {
                if self.dataReceived.count > 0 {
                    dR = self.dataReceived
                    self.dataReceived.removeAll(keepingCapacity: false)
                }
            }
            let isEOF = inputStream.streamStatus == .atEnd && self.dataReceived.count == 0
            self.dataReceivedLock.unlock()
            completionHandler(dR, isEOF, dR == nil ? (timedOut ? URLError(.timedOut) : inputStream.streamError) : nil)
        }
    }
    
    /**
     * Asynchronously writes the specified data to the stream, and calls a handler upon completion.
     *
     * There is no guarantee that the remote side of the stream has received all of the written bytes
     * at the time that `completionHandler` is called, only that all of the data has been written to the kernel.
     *
     * - Parameter data: The data to be written.
     * - Parameter timeout: A timeout for writing bytes. If the write is not completed within the specified interval,
     *      the write is canceled and the `completionHandler` is called with an error.
     *      Pass `0` to prevent a write from timing out.
     * - Parameter completionHandler: The completion handler to call when all bytes are written, or an error occurs.
     *      This handler is executed on the delegate queue.
     *      This completion handler takes the following parameter:
     * - Parameter error: An error object that indicates why the write failed, or `nil` if the write was successful.
     */
    open func write(_ data: Data, timeout: TimeInterval, completionHandler: @escaping (_ error: Error?) -> Void) {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.write(data, timeout: timeout, completionHandler: completionHandler)
                return
            }
        }
        
        guard outputStream != nil else {
            if self.state == .canceling || self.state == .completed {
                completionHandler(URLError(.cancelled))
            }
            return
        }
        
        self.dataToBeSentLock.lock()
        self.dataToBeSent.append(data)
        self.dataToBeSentLock.unlock()
        
        dispatch_queue.async {
            let result = self.write(timeout: timeout, close: false)
            if result < 0 {
                let error = self.outputStream?.streamError ??
                    URLError((self.state == .canceling || self.state == .completed) ? .cancelled : .cannotWriteToFile)
                completionHandler(error)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    /**
     * Completes any already enqueued reads and writes, and then invokes the
     * `urlSession(_:streamTask:didBecome:outputStream:)` delegate message.
     */
    open func captureStreams() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.captureStreams()
                return
            }
        }
        
        guard let outputStream = outputStream, let inputStream = inputStream else {
            return
        }
        dispatch_queue.async {
            _=self.write(close: false)
            while outputStream.streamStatus == .writing {
                Thread.sleep(forTimeInterval: 0.1)
            }
            self.streamDelegate?.urlSession?(self._underlyingSession, streamTask: self, didBecome: inputStream, outputStream: outputStream)
        }
    }
    
    /**
     * Completes any enqueued reads and writes, and then closes the write side of the underlying socket.
     *
     * You may continue to read data using the `readData(ofMinLength:maxLength:timeout:completionHandler:)`
     * method after calling this method. Any calls to `write(_:timeout:completionHandler:)` after calling
     * this method will result in an error.
     *
     * Because the server may continue to write bytes to the client, it is recommended that
     * you continue reading until the stream reaches end-of-file (EOF).
     */
    open func closeWrite() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.closeWrite()
                return
            }
        }
        
        dispatch_queue.async {
            _ = self.write(close: true)
        }
    }
    
    fileprivate var shouldCloseWrite = false
    
    /**
     * Completes any enqueued reads and writes, and then closes the read side of the underlying socket.
     *
     * You may continue to write data using the `write(_:timeout:completionHandler:)` method after
     * calling this method. Any calls to `readData(ofMinLength:maxLength:timeout:completionHandler:)`
     * after calling this method will result in an error.
     */
    open func closeRead() {
        closeRead(immediate: false)
    }
    
    /**
     * Completes any enqueued reads and writes, and then closes the read side of the underlying socket.
     *
     * You may continue to write data using the `write(_:timeout:completionHandler:)` method after
     * calling this method. Any calls to `readData(ofMinLength:maxLength:timeout:completionHandler:)`
     * after calling this method will result in an error.
     *
     * - Parameter immediate: close immediatly if true.
     */
    open func closeRead(immediate: Bool) {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.closeRead()
                return
            }
        }
        
        guard let inputStream = inputStream else {
            return
        }
        dispatch_queue.async {
            if !immediate {
                while inputStream.streamStatus != .atEnd {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            inputStream.close()
            self.streamDelegate?.urlSession?(self._underlyingSession, readClosedFor: self)
        }
    }
    
    /**
     * Completes any enqueued reads and writes, and establishes a secure connection.
     *
     * Authentication callbacks are sent to the session's delegate using the
     * `urlSession(_:task:didReceive:completionHandler:)` method.
     */
    open func startSecureConnection() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.startSecureConnection()
                return
            }
        }
        
        isSecure = true
        if let inputStream = self.inputStream, let outputStream = self.outputStream,
            inputStream.property(forKey: .socketSecurityLevelKey) as? String == StreamSocketSecurityLevel.none.rawValue {
            if serverTrustPolicy.evaluate() {
                // ※ Called, Before setProperty securityLevel
                self.addTrustAllCertificatesSettings()
            }
            
            inputStream.setSSLPeerID(peerID: peerID, peerIDLen: peerIDLen)
            
            dispatch_queue.async {
                inputStream.setProperty(self.securityLevel.rawValue, forKey: .socketSecurityLevelKey)
                outputStream.setProperty(self.securityLevel.rawValue, forKey: .socketSecurityLevelKey)
            }
            
            var sslSessionState: SSLSessionState = .idle
            if let sslContext = inputStream.property(forKey: kCFStreamPropertySSLContext as Stream.PropertyKey) {
                while SSLGetSessionState(sslContext as! SSLContext, UnsafeMutablePointer(&sslSessionState)) == errSSLWouldBlock ||
                    sslSessionState == .idle || sslSessionState == .handshake {
                        guard inputStream.streamError == nil, outputStream.streamError == nil else {
                            break
                        }
                        Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
    }
    
    /**
     * Completes any enqueued reads and writes, and closes the secure connection.
     */
    open func stopSecureConnection() {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                _underlyingTask!.stopSecureConnection()
                return
            }
        }
        
        isSecure = false
        dispatch_queue.async {
            if let inputStream = self.inputStream, let outputStream = self.outputStream,
                inputStream.property(forKey: .socketSecurityLevelKey) as? String != StreamSocketSecurityLevel.none.rawValue {
                
                inputStream.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
                outputStream.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
                
                if let sslContext = inputStream.property(forKey: kCFStreamPropertySSLContext as Stream.PropertyKey) {
                    while SSLClose(sslContext as! SSLContext) == errSSLWouldBlock {
                        guard inputStream.streamError == nil || inputStream.streamError?._code == Int(errSSLClosedGraceful),
                            outputStream.streamError == nil || outputStream.streamError?._code == Int(errSSLClosedGraceful) else {
                                break
                        }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
            }
        }
    }
    
    /**
     * Add TrustAllCertificates SSLSettings to Input/OutputStream.
     *
     * - note: Connects to a remote socket server using a self-signed certificate
     */
    func addTrustAllCertificatesSettings() {
        // Define custom SSL/TLS settings
        #if swift(>=5.0)
        let sslSettings: [NSString: Any] = [
            NSString(format: kCFStreamSSLValidatesCertificateChain): kCFBooleanFalse!,
            NSString(format: kCFStreamSSLPeerName): kCFNull!
        ]
        #else
        let sslSettings: [NSString: Any] = [
            NSString(format: kCFStreamSSLValidatesCertificateChain): kCFBooleanFalse,
            NSString(format: kCFStreamSSLPeerName): kCFNull
        ]
        #endif
        // Set custom SSL/TLS settings
        inputStream?.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
        outputStream?.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
    }
    
    /**
     * Reuse SSL/TLS session used for the SSL/TLS session cache.
     *
     * - Parameter task: The task authenticated connection FTP over SSL/TLS.
     */
    func reuseSSLSession(task: FileProviderStreamTask) {
        let sslPeerID = task.inputStream?.getSSLPeerID()
        peerID = sslPeerID?.peerID
        peerIDLen = sslPeerID?.peerIDLen ?? 0
    }
}

extension Stream {
    /**
     * Retrieves the current peer ID data.
     *
     * - Returns:
     *   - peerID: On return, points to a buffer containing the peer ID data.
     *   - peerIDLen: On return, the length of the peer ID data buffer.
     */
    public func getSSLPeerID() -> (peerID: UnsafeRawPointer?, peerIDLen: Int) {
        var peerID: UnsafeRawPointer? = nil
        var peerIDLen: Int = 0
        
        if let sslContext = self.property(forKey: kCFStreamPropertySSLContext as Stream.PropertyKey) {
            let _ = SSLGetPeerID(sslContext as! SSLContext, UnsafeMutablePointer(&peerID), UnsafeMutablePointer(&peerIDLen))
        }
        
        return (peerID, peerIDLen)
    }
    
    /**
     * Specifies data that is sufficient to uniquely identify the peer of the current session.
     * This peerID is used for the TLS session cache.
     *
     * - Parameter peerID: A pointer to a buffer containing the peer ID data to set.
     * - Parameter peerIDLen: The length of the peer ID data buffer.
     */
    fileprivate func setSSLPeerID(peerID: UnsafeRawPointer?, peerIDLen: Int) {
        guard peerID != nil, peerIDLen > 0 else {
            return
        }
        
        if let sslContext = self.property(forKey: kCFStreamPropertySSLContext as Stream.PropertyKey) {
            let _ = SSLSetPeerID(sslContext as! SSLContext, peerID, peerIDLen)
        }
    }
}

extension FileProviderStreamTask {
    open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode.contains(.errorOccurred) {
            self._error = aStream.streamError
            streamDelegate?.urlSession?(_underlyingSession, task: self, didCompleteWithError: error)
        }
        
        if aStream == inputStream && eventCode.contains(.endEncountered) {
            self.endEncountered = true
        }
        
        if aStream == inputStream && eventCode.contains(.hasBytesAvailable) {
            while (inputStream!.hasBytesAvailable) {
                var buffer = [UInt8](repeating: 0, count: 2048)
                let len = inputStream!.read(&buffer, maxLength: buffer.count)
                if len > 0 {
                    dataReceivedLock.lock()
                    dataReceived.append(&buffer, count: len)
                    dataReceivedLock.unlock()
                    self._countOfBytesRecieved += Int64(len)
                }
            }
        }
    }
    
    fileprivate func write(timeout: TimeInterval = 0, close: Bool) -> Int {
        guard let outputStream = outputStream else {
            return -1
        }
        
        var byteSent: Int = 0
        let expireDate = Date(timeIntervalSinceNow: timeout)
        self.dataToBeSentLock.lock()
        defer {
            self.dataToBeSentLock.unlock()
        }
        while self.dataToBeSent.count > 0 && (timeout == 0 || expireDate > Date()) {
            if let _ = outputStream.streamError {
                return byteSent == 0 ? -1 : byteSent
            }
            
            let bytesWritten: Int = (try? outputStream.write(data: self.dataToBeSent)) ?? -1
            
            if bytesWritten > 0 {
                self.dataToBeSent.removeFirst(bytesWritten)
                byteSent += bytesWritten
                self._countOfBytesSent += Int64(bytesWritten)
            } else if bytesWritten < 0 {
                self._error = outputStream.streamError
                return bytesWritten
            }
            if self.dataToBeSent.count == 0 {
                break
            }
        }
        
        if close {
            DispatchQueue.main.sync {
                outputStream.close()
                shouldCloseWrite = true
            }
            self.streamDelegate?.urlSession?(self._underlyingSession, writeClosedFor: self)
        }
        return byteSent
    }
    
    fileprivate func finish() {
        peerID = nil
        
        inputStream?.delegate = nil
        outputStream?.delegate = nil
        
        inputStream?.close()
        #if swift(>=4.2)
        inputStream?.remove(from: RunLoop.main, forMode: .common)
        #else
        inputStream?.remove(from: RunLoop.main, forMode: .commonModes)
        #endif
        inputStream = nil
        
        outputStream?.close()
        #if swift(>=4.2)
        outputStream?.remove(from: RunLoop.main, forMode: .common)
        #else
        outputStream?.remove(from: RunLoop.main, forMode: .commonModes)
        #endif
        outputStream = nil
    }
    
}

extension FileProviderStreamTask {
    public override func addObserver(_ observer: NSObject, forKeyPath keyPath: String, options: NSKeyValueObservingOptions = [], context: UnsafeMutableRawPointer?) {
        if #available(iOS 9.0, macOS 10.11, *) {
            if self.useURLSession {
                self._underlyingTask?.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
                return
            }
        }
        
        switch keyPath {
        case #keyPath(countOfBytesSent):
            fallthrough
        case #keyPath(countOfBytesReceived):
            fallthrough
        case #keyPath(countOfBytesExpectedToSend):
            fallthrough
        case #keyPath(countOfBytesExpectedToReceive):
            observers.append((keyPath: keyPath, observer: observer, context: context))
        default:
            break
        }
        super.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
    }
    
    public override func removeObserver(_ observer: NSObject, forKeyPath keyPath: String) {
        var newObservers: [(keyPath: String, observer: NSObject, context: UnsafeMutableRawPointer?)] = []
        for observer in observers where observer.keyPath != keyPath {
            newObservers.append(observer)
        }
        self.observers = newObservers
        super.removeObserver(observer, forKeyPath: keyPath)
    }
    
    public override func removeObserver(_ observer: NSObject, forKeyPath keyPath: String, context: UnsafeMutableRawPointer?) {
        var newObservers: [(keyPath: String, observer: NSObject, context: UnsafeMutableRawPointer?)] = []
        for observer in observers where observer.keyPath != keyPath || observer.context != context {
            newObservers.append(observer)
        }
        self.observers = newObservers
        super.removeObserver(observer, forKeyPath: keyPath, context: context)
    }
}

public extension URLSession {
    /// Creates a bidirectional stream task to a given host and port.
    func fpstreamTask(withHostName hostname: String, port: Int) -> FileProviderStreamTask {
        return FileProviderStreamTask(session: self, host: hostname, port: port)
    }
    
    /**
     * Creates a bidirectional stream task with an NSNetService to identify the endpoint.
     * The NSNetService will be resolved before any IO completes.
     */
    func fpstreamTask(withNetService service: NetService) -> FileProviderStreamTask {
        return FileProviderStreamTask(session: self, netService: service)
    }
}

@objc
internal protocol FPSStreamDelegate : URLSessionTaskDelegate {
    
    
    /**
     * Indiciates that the read side of a connection has been closed.  Any
     * outstanding reads complete, but future reads will immediately fail.
     * This may be sent even when no reads are in progress. However, when
     * this delegate message is received, there may still be bytes
     * available.  You only know that no more bytes are available when you
     * are able to read until EOF. */
    @objc optional func urlSession(_ session: URLSession, readClosedFor streamTask: FileProviderStreamTask)
    
    
    /**
     * Indiciates that the write side of a connection has been closed.
     * Any outstanding writes complete, but future writes will immediately
     * fail.
     */
    @objc optional func urlSession(_ session: URLSession, writeClosedFor streamTask: FileProviderStreamTask)
    
    
    /**
     * A notification that the system has determined that a better route
     * to the host has been detected (eg, a wi-fi interface becoming
     * available.)  This is a hint to the delegate that it may be
     * desirable to create a new task for subsequent work.  Note that
     * there is no guarantee that the future task will be able to connect
     * to the host, so callers should should be prepared for failure of
     * reads and writes over any new interface. */
    @objc optional func urlSession(_ session: URLSession, betterRouteDiscoveredFor streamTask: FileProviderStreamTask)
    
    
    /**
     * The given task has been completed, and unopened NSInputStream and
     * NSOutputStream objects are created from the underlying network
     * connection.  This will only be invoked after all enqueued IO has
     * completed (including any necessary handshakes.)  The streamTask
     * will not receive any further delegate messages.
     */
    @objc optional func urlSession(_ session: URLSession, streamTask: FileProviderStreamTask, didBecome inputStream: InputStream, outputStream: OutputStream)
}
// codebeat:enable[TOTAL_LOC,TOO_MANY_IVARS]

private let ports: [String: Int] = ["http": 80, "https": 443, "smb": 445,"ftp": 21,
                                    "telnet": 23, "pop": 110, "smtp": 25, "imap": 143]
private let securePorts: [String: Int] =  ["ssh": 22, "https": 443, "smb": 445, "smtp": 465,
                                           "ftps": 990,"telnet": 992, "imap": 993, "pop": 995]
