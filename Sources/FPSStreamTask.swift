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
    
    fileprivate var dispatch_queue: DispatchQueue!
    internal var _underlyingSession: URLSession
    fileprivate var streamDelegate: FPSStreamDelegate? {
        return (_underlyingSession.delegate as? FPSStreamDelegate)
    }
    fileprivate var _taskIdentifier: Int
    
    @available(iOS 9.0, OSX 10.11, *)
    static var streamTasks = [Int: URLSessionStreamTask]()
    
    @available(iOS 9.0, OSX 10.11, *)
    internal var _underlyingTask: URLSessionStreamTask? {
        return FPSStreamTask.streamTasks[_taskIdentifier]
    }
    
    open override var taskIdentifier: Int {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.taskIdentifier
        } else {
            return _taskIdentifier
        }
    }
    
    fileprivate var _state: URLSessionTask.State = .suspended
    override open var state: URLSessionTask.State {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.state
        } else {
            return _state
        }
    }
    
    override open var originalRequest: URLRequest? {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.originalRequest
        } else {
            return nil
        }
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
            return _underlyingTask!.countOfBytesSent
        } else {
            return _countOfBytesSent
        }
    }
    
    override open var countOfBytesReceived: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesReceived
        } else {
            return _countOfBytesRecieved
        }
    }
    
    override open var countOfBytesExpectedToSend: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesExpectedToSend
        } else {
            return Int64(dataToBeSent.length)
        }
    }
    
    override open var countOfBytesExpectedToReceive: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesExpectedToReceive
        } else {
            return Int64(dataReceived.length)
        }
    }
    
    override public init() {
        fatalError("Use NSURLSession.fpstreamTask() method")
    }
    
    var host: (hostname: String, port: Int)?
    var service: NetService?
    
    internal init(session: URLSession, host: String, port: Int) {
        self._underlyingSession = session
        if #available(iOS 9.0, OSX 10.11, *) {
            let task = session.streamTask(withHostName: host, port: port)
            self._taskIdentifier = task.taskIdentifier
            FPSStreamTask.streamTasks[_taskIdentifier] = task
        } else {
            lasttaskIdAssociated += 1
            self._taskIdentifier = lasttaskIdAssociated
            self.host = (host, port)
            self.dispatch_queue = DispatchQueue(label: "FSPStreamTask", attributes: DispatchQueue.Attributes.concurrent)
        }
    }
    
    internal init(session: URLSession, netService: NetService) {
        self._underlyingSession = session
        if #available(iOS 9.0, OSX 10.11, *) {
            let task = session.streamTask(with: netService)
            self._taskIdentifier = task.taskIdentifier
            FPSStreamTask.streamTasks[_taskIdentifier] = task
        } else {
            lasttaskIdAssociated += 1
            self._taskIdentifier = lasttaskIdAssociated
            self.service = netService
            self.dispatch_queue = DispatchQueue(label: "FSPStreamTask", attributes: DispatchQueue.Attributes.concurrent)
        }
    }
    
    override open func cancel() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.cancel()
        } else {
            self._state = .canceling
            inputStream?.setValue(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as String)
            outputStream?.setValue(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as String)
            
            self.inputStream?.close()
            self.outputStream?.close()
            
            self.inputStream?.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
            self.outputStream?.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
            
            self.inputStream?.delegate = nil
            self.outputStream?.delegate = nil
            
            self.inputStream = nil
            self.outputStream = nil
            
            self._state = .completed
            self._countOfBytesSent = 0
            self._countOfBytesRecieved = 0
        }
    }
    
    var _error: Error? = nil
    override open var error: Error? {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.error
        } else {
            return _error
        }
    }
    
    override open func suspend() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.suspend()
        } else {
            self._state = .suspended
        }
    }
    
    override open func resume() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.resume()
        } else {
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
            
            dispatch_queue.sync(execute: { 
                inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
            })
            
            inputStream.open()
            outputStream.open()
            
            _state = .running
        }
    }
    
    fileprivate let dataToBeSent: NSMutableData = NSMutableData()
    fileprivate let dataReceived: NSMutableData = NSMutableData()
    
    /* Read minBytes, or at most maxBytes bytes and invoke the completion
     * handler on the sessions delegate queue with the data or an error.
     * If an error occurs, any outstanding reads will also fail, and new
     * read requests will error out immediately.
     */
    open func readData(OfMinLength minBytes: Int, maxLength maxBytes: Int, timeout: TimeInterval, completionHandler: @escaping (Data?, Bool, NSError?) -> Void) {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.readData(ofMinLength: minBytes, maxLength: maxBytes, timeout: timeout, completionHandler: completionHandler as! (Data?, Bool, Error?) -> Void)
        } else {
            guard let inputStream = inputStream else {
                return
            }
            var timedOut: Bool = false
            dispatch_queue.async {
                if timeout > 0 {
                    self.dispatch_queue.asyncAfter(deadline: .now() + 1) {
                        timedOut = true
                        completionHandler(nil, inputStream.streamStatus == .atEnd, inputStream.streamError as NSError?)
                    }
                }
                while (self.dataReceived.length == 0 || self.dataReceived.length < minBytes) && !timedOut {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1));
                    Thread.sleep(forTimeInterval: 0.1)
                }
                let dR = NSMutableData()
                if self.dataReceived.length > maxBytes {
                    let range = NSRange(location: 0, length: maxBytes - 1)
                    dR.append(self.dataReceived.subdata(with: range))
                    self.dataReceived.replaceBytes(in: range, withBytes: nil, length: 0)
                } else {
                    dR.append(self.dataReceived as Data)
                    self.dataReceived.length = 0
                }
                completionHandler(dR as Data, inputStream.streamStatus == .atEnd, inputStream.streamError as NSError?)
            }
        }
    }
    
    /* Write the data completely to the underlying socket.  If all the
     * bytes have not been written by the timeout, a timeout error will
     * occur.  Note that invocation of the completion handler does not
     * guarantee that the remote side has received all the bytes, only
     * that they have been written to the kernel. */
    open func writeData(_ data: Data, timeout: TimeInterval, completionHandler: @escaping (Error?) -> Void) {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.write(data, timeout: timeout, completionHandler: completionHandler)
        } else {
            guard let outputStream = outputStream else {
                return
            }
            var timedOut: Bool = false
            dispatch_queue.async {
                if timeout > 0 {
                    self.dispatch_queue.asyncAfter(deadline: .now() + 1) {
                        timedOut = true
                        completionHandler(self._error)
                    }
                }
                
                self.dataToBeSent.append(data)
                while !outputStream.hasSpaceAvailable && !timedOut {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1));
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if self.dataToBeSent.length > 0 {
                    let bytesWritten = outputStream.write(self.dataToBeSent.bytes.bindMemory(to: UInt8.self, capacity: self.dataToBeSent.length), maxLength: self.dataToBeSent.length) 
                    if bytesWritten > 0 {
                        let range = NSRange(location: 0, length: bytesWritten)
                        self.dataToBeSent.replaceBytes(in: range, withBytes: nil, length: 0)
                        self._countOfBytesSent += bytesWritten
                        completionHandler(nil)
                    } else {
                        self._error = outputStream.streamError
                        completionHandler(outputStream.streamError)
                    }
                }
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
            _underlyingTask!.captureStreams()
        } else {
            guard let outputStream = outputStream, let inputStream = inputStream else {
                return
            }
            dispatch_queue.async {
                self.write(false)
                while inputStream.streamStatus != .atEnd {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1));
                    Thread.sleep(forTimeInterval: 0.1)
                }
                self.streamDelegate?.urlSession?(self._underlyingSession, streamTask: self, didBecome: inputStream, outputStream: outputStream)
            }
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
            _underlyingTask!.closeWrite()
        } else {
            dispatch_queue.async(execute: { 
                self.write(true)
            })
        }
    }
    
    fileprivate func write(_ close: Bool) {
        guard let outputStream = outputStream else {
            return
        }
        while self.dataToBeSent.length > 0 {
            let bytesWritten = outputStream.write(self.dataToBeSent.bytes.bindMemory(to: UInt8.self, capacity: self.dataToBeSent.length), maxLength: self.dataToBeSent.length) 
            if bytesWritten > 0 {
                let range = NSRange(location: 0, length: bytesWritten)
                self.dataToBeSent.replaceBytes(in: range, withBytes: nil, length: 0)
                self._countOfBytesSent += bytesWritten
            } else {
                self._error = outputStream.streamError as NSError?
            }
            if self.dataToBeSent.length == 0 {
                break
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1));
            Thread.sleep(forTimeInterval: 0.1)
        }
        if close {
            outputStream.close()
            self.streamDelegate?.urlSession?(self._underlyingSession, writeClosedFor: self)
        }
    }
    
    /* Enqueue a request to close the read side of the underlying socket.
     * All outstanding IO will complete before the read side is closed.
     * You may continue writing to the server.
     */
    open func closeRead() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.closeRead()
        } else {
            guard let inputStream = inputStream else {
                return
            }
            dispatch_queue.async {
                while inputStream.streamStatus != .atEnd {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1));
                    Thread.sleep(forTimeInterval: 0.1)
                }
                inputStream.close()
                self.streamDelegate?.urlSession?(self._underlyingSession, readClosedFor: self)
            }
        }
    }
    
    /*
     * Begin encrypted handshake.  The hanshake begins after all pending
     * IO has completed.  TLS authentication callbacks are sent to the
     * session's -URLSession:task:didReceiveChallenge:completionHandler:
     */
    open func startSecureConnection() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.startSecureConnection()
        } else {
            inputStream!.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue, forKey: .socketSecurityLevelKey)
            outputStream!.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue, forKey: .socketSecurityLevelKey)
        }
    }
    
    /*
     * Cleanly close a secure connection after all pending secure IO has
     * completed.
     */
    open func stopSecureConnection() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.stopSecureConnection()
        } else {
            inputStream!.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
            outputStream!.setProperty(StreamSocketSecurityLevel.none.rawValue, forKey: .socketSecurityLevelKey)
        }
    }
    
    open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch (eventCode) {
        case Stream.Event.errorOccurred:
            self._error = aStream.streamError as NSError?
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
                        dataReceived.append(&buffer, length: len)
                        self._countOfBytesRecieved += len
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
    func fpstreamTaskWithHostName(_ hostname: String, port: Int) -> FPSStreamTask {
        return FPSStreamTask(session: self, host: hostname, port: port)
    }
    
    /* Creates a bidirectional stream task with an NSNetService to identify the endpoint.
     * The NSNetService will be resolved before any IO completes.
     */
    func fpstreamTaskWithNetService(_ service: NetService) -> FPSStreamTask {
        return fpstreamTaskWithNetService(service)
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
