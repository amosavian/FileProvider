//
//  FPSStreamTask.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian on 5/19/95.
//
//

import Foundation

private var lasttaskIdAssociated = 1_000_000_000

@objc
public class FPSStreamTask: NSURLSessionTask, NSStreamDelegate {
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    
    private var dispatch_queue: dispatch_queue_t!
    internal var _underlyingSession: NSURLSession
    private var streamDelegate: FPSStreamDelegate? {
        return (_underlyingSession.delegate as? FPSStreamDelegate)
    }
    private var _underlyingTaskObject: NSURLSessionTask?
    private var _taskIdentifier: Int
    
    @available(iOS 9.0, OSX 10.11, *)
    internal var _underlyingTask: NSURLSessionStreamTask? {
        get {
            return _underlyingTaskObject as? NSURLSessionStreamTask
        }
        set {
            _underlyingTaskObject = newValue
        }
    }
    
    public override var taskIdentifier: Int {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.taskIdentifier
        } else {
            return _taskIdentifier
        }
    }
    
    private var _state: NSURLSessionTaskState = .Suspended
    override public var state: NSURLSessionTaskState {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.state
        } else {
            return _state
        }
    }
    
    override public var originalRequest: NSURLRequest? {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.originalRequest
        } else {
            return nil
        }
    }
    
    override public var currentRequest: NSURLRequest? {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.currentRequest
        } else {
            return nil
        }
    }
    
    private var _countOfBytesSent: Int64 = 0
    private var _countOfBytesRecieved: Int64 = 0
    
    override public var countOfBytesSent: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesSent
        } else {
            return _countOfBytesSent
        }
    }
    
    override public var countOfBytesReceived: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesReceived
        } else {
            return _countOfBytesRecieved
        }
    }
    
    override public var countOfBytesExpectedToSend: Int64 {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.countOfBytesExpectedToSend
        } else {
            return Int64(dataToBeSent.length)
        }
    }
    
    override public var countOfBytesExpectedToReceive: Int64 {
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
    var service: NSNetService?
    
    internal init(session: NSURLSession, host: String, port: Int) {
        self._underlyingSession = session
        if #available(iOS 9.0, OSX 10.11, *) {
            self._underlyingTaskObject = session.streamTaskWithHostName(host, port: port)
            self._taskIdentifier = self._underlyingTaskObject!.taskIdentifier
            super.init()
        } else {
            lasttaskIdAssociated += 1
            self._taskIdentifier = lasttaskIdAssociated
            self.host = (host, port)
            self.dispatch_queue = dispatch_queue_create("FSPStreamTask", DISPATCH_QUEUE_CONCURRENT)
            super.init()
        }
    }
    
    internal init(session: NSURLSession, netService: NSNetService) {
        self._underlyingSession = session
        if #available(iOS 9.0, OSX 10.11, *) {
            self._underlyingTaskObject = session.streamTaskWithNetService(netService)
            self._taskIdentifier = self._underlyingTaskObject!.taskIdentifier
        } else {
            lasttaskIdAssociated += 1
            self._taskIdentifier = lasttaskIdAssociated
            self.service = netService
            self.dispatch_queue = dispatch_queue_create("FSPStreamTask", DISPATCH_QUEUE_CONCURRENT)
        }
    }
    
    override public func cancel() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.cancel()
        } else {
            self._state = .Canceling
            inputStream?.setValue(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as String)
            outputStream?.setValue(kCFBooleanTrue, forKey: kCFStreamPropertyShouldCloseNativeSocket as String)
            
            self.inputStream?.close()
            self.outputStream?.close()
            
            self.inputStream?.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
            self.outputStream?.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
            
            self.inputStream?.delegate = nil
            self.outputStream?.delegate = nil
            
            self.inputStream = nil
            self.outputStream = nil
            
            self._state = .Completed
            self._countOfBytesSent = 0
            self._countOfBytesRecieved = 0
        }
    }
    
    var _error: NSError? = nil
    override public var error: NSError? {
        if #available(iOS 9.0, OSX 10.11, *) {
            return _underlyingTask!.error
        } else {
            return _error
        }
    }
    
    override public func suspend() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.suspend()
        } else {
            inputStream?.close()
            outputStream?.close()
            streamDelegate?.URLSession?(_underlyingSession, readClosedForStreamTask: self)
            streamDelegate?.URLSession?(_underlyingSession, writeClosedForStreamTask: self)
            self._state = .Suspended
        }
    }
    
    override public func resume() {
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
                    let cfnetService = CFNetServiceCreate(kCFAllocatorDefault, service.domain, service.type, service.name, Int32(service.port))
                    CFStreamCreatePairWithSocketToNetService(kCFAllocatorDefault, cfnetService.takeRetainedValue(), &readStream, &writeStream)
                }
                
                inputStream = readStream?.takeRetainedValue()
                outputStream = writeStream?.takeRetainedValue()
                guard let inputStream = inputStream, outputStream = outputStream else {
                    return
                }
                streamDelegate?.URLSession?(self._underlyingSession, streamTask: self, didBecomeInputStream: inputStream, outputStream: outputStream)
            }
            
            guard let inputStream = inputStream, outputStream = outputStream else {
                return
            }
            
            inputStream.delegate = self
            outputStream.delegate = self
            
            dispatch_sync(dispatch_queue, { 
                inputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
                outputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
            })
            
            inputStream.open()
            outputStream.open()
            
            _state = .Running
        }
    }
    
    private let dataToBeSent: NSMutableData = NSMutableData()
    private let dataReceived: NSMutableData = NSMutableData()
    
    /* Read minBytes, or at most maxBytes bytes and invoke the completion
     * handler on the sessions delegate queue with the data or an error.
     * If an error occurs, any outstanding reads will also fail, and new
     * read requests will error out immediately.
     */
    public func readDataOfMinLength(minBytes: Int, maxLength maxBytes: Int, timeout: NSTimeInterval, completionHandler: (NSData?, Bool, NSError?) -> Void) {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.readDataOfMinLength(minBytes, maxLength: maxBytes, timeout: timeout, completionHandler: completionHandler)
        } else {
            guard let inputStream = inputStream else {
                return
            }
            var timedOut: Bool = false
            dispatch_async(dispatch_queue) {
                if timeout > 0 {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * 1_000_000_000)), self.dispatch_queue, {
                        timedOut = true
                        completionHandler(nil, inputStream.streamStatus == .AtEnd, inputStream.streamError)
                    })
                }
                while self.dataReceived.length < minBytes && !timedOut {
                    NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
                    NSThread.sleepForTimeInterval(0.1)
                }
                let dR = NSMutableData()
                if self.dataReceived.length > maxBytes {
                    let range = NSRange(location: 0, length: maxBytes - 1)
                    dR.appendData(self.dataReceived.subdataWithRange(range))
                    self.dataReceived.replaceBytesInRange(range, withBytes: nil, length: 0)
                } else {
                    dR.appendData(self.dataReceived)
                    self.dataReceived.length = 0
                }
                completionHandler(self.dataReceived, inputStream.streamStatus == .AtEnd, inputStream.streamError)
            }
        }
    }
    
    /* Write the data completely to the underlying socket.  If all the
     * bytes have not been written by the timeout, a timeout error will
     * occur.  Note that invocation of the completion handler does not
     * guarantee that the remote side has received all the bytes, only
     * that they have been written to the kernel. */
    public func writeData(data: NSData, timeout: NSTimeInterval, completionHandler: (NSError?) -> Void) {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.writeData(data, timeout: timeout, completionHandler: completionHandler)
        } else {
            guard let outputStream = outputStream else {
                return
            }
            var timedOut: Bool = false
            dispatch_async(dispatch_queue) {
                if timeout > 0 {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * 1_000_000_000)), self.dispatch_queue, {
                        timedOut = true
                        completionHandler(self._error)
                    })
                }
                
                self.dataToBeSent.appendData(data)
                while !outputStream.hasSpaceAvailable && !timedOut {
                    NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
                    NSThread.sleepForTimeInterval(0.1)
                }
                if self.dataToBeSent.length > 0 {
                    let bytesWritten = outputStream.write(UnsafePointer(self.dataToBeSent.bytes), maxLength: self.dataToBeSent.length) ?? -1
                    if bytesWritten > 0 {
                        let range = NSRange(location: 0, length: bytesWritten)
                        self.dataToBeSent.replaceBytesInRange(range, withBytes: nil, length: 0)
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
    public func captureStreams() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.captureStreams()
        } else {
            guard let outputStream = outputStream, let inputStream = inputStream else {
                return
            }
            write(false)
            dispatch_async(dispatch_queue) {
                while inputStream.streamStatus != .AtEnd {
                    NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
                    NSThread.sleepForTimeInterval(0.1)
                }
                self.streamDelegate?.URLSession?(self._underlyingSession, streamTask: self, didBecomeInputStream: inputStream, outputStream: outputStream)
            }
        }
    }
    
    /* Enqueue a request to close the write end of the underlying socket.
     * All outstanding IO will complete before the write side of the
     * socket is closed.  The server, however, may continue to write bytes
     * back to the client, so best practice is to continue reading from
     * the server until you receive EOF.
     */
    public func closeWrite() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.closeWrite()
        } else {
            write(true)
        }
    }
    
    private func write(close: Bool) {
        guard let outputStream = outputStream else {
            return
        }
        dispatch_async(dispatch_queue) {
            while self.dataToBeSent.length > 0 {
                let bytesWritten = outputStream.write(UnsafePointer(self.dataToBeSent.bytes), maxLength: self.dataToBeSent.length) ?? -1
                if bytesWritten > 0 {
                    let range = NSRange(location: 0, length: bytesWritten)
                    self.dataToBeSent.replaceBytesInRange(range, withBytes: nil, length: 0)
                    self._countOfBytesSent += bytesWritten
                } else {
                    self._error = outputStream.streamError
                }
                NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
                NSThread.sleepForTimeInterval(0.1)
            }
            if close {
                outputStream.close()
                self.streamDelegate?.URLSession?(self._underlyingSession, writeClosedForStreamTask: self)
            }
        }
    }
    
    /* Enqueue a request to close the read side of the underlying socket.
     * All outstanding IO will complete before the read side is closed.
     * You may continue writing to the server.
     */
    public func closeRead() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.closeRead()
        } else {
            guard let inputStream = inputStream else {
                return
            }
            dispatch_async(dispatch_queue) {
                while inputStream.streamStatus != .AtEnd {
                    NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
                    NSThread.sleepForTimeInterval(0.1)
                }
                inputStream.close()
                self.streamDelegate?.URLSession?(self._underlyingSession, readClosedForStreamTask: self)
            }
        }
    }
    
    /*
     * Begin encrypted handshake.  The hanshake begins after all pending
     * IO has completed.  TLS authentication callbacks are sent to the
     * session's -URLSession:task:didReceiveChallenge:completionHandler:
     */
    public func startSecureConnection() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.startSecureConnection()
        } else {
            inputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            outputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
        }
    }
    
    /*
     * Cleanly close a secure connection after all pending secure IO has
     * completed.
     */
    public func stopSecureConnection() {
        if #available(iOS 9.0, OSX 10.11, *) {
            _underlyingTask!.stopSecureConnection()
        } else {
            inputStream!.setProperty(NSStreamSocketSecurityLevelNone, forKey: NSStreamSocketSecurityLevelKey)
            outputStream!.setProperty(NSStreamSocketSecurityLevelNone, forKey: NSStreamSocketSecurityLevelKey)
        }
    }
    
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        switch (eventCode) {
        case NSStreamEvent.ErrorOccurred:
            self._error = aStream.streamError
            streamDelegate?.URLSession?(_underlyingSession, task: self, didCompleteWithError: error)
        case NSStreamEvent.EndEncountered:
            break
        case NSStreamEvent.None:
            break
        case NSStreamEvent.OpenCompleted:
            break
        case NSStreamEvent.HasBytesAvailable:
            var buffer = [UInt8](count: 2048, repeatedValue: 0)
            if (aStream == inputStream) {
                while (inputStream!.hasBytesAvailable ?? false) {
                    let len = inputStream!.read(&buffer, maxLength: buffer.count)
                    if len > 0 {
                        dataReceived.appendBytes(&buffer, length: len)
                        self._countOfBytesRecieved += len
                    }
                }
            }
        case NSStreamEvent.HasSpaceAvailable:
            break
        default:
            break
        }
    }
}

extension NSURLSession {
    /* Creates a bidirectional stream task to a given host and port.
     */
    public func fpstreamTaskWithHostName(hostname: String, port: Int) -> FPSStreamTask {
        return FPSStreamTask(session: self, host: hostname, port: port)
    }
    
    /* Creates a bidirectional stream task with an NSNetService to identify the endpoint.
     * The NSNetService will be resolved before any IO completes.
     */
    public func fpstreamTaskWithNetService(service: NSNetService) -> FPSStreamTask {
        return fpstreamTaskWithNetService(service)
    }
}

@objc
public protocol FPSStreamDelegate : NSURLSessionTaskDelegate {
    
    /* Indiciates that the read side of a connection has been closed.  Any
     * outstanding reads complete, but future reads will immediately fail.
     * This may be sent even when no reads are in progress. However, when
     * this delegate message is received, there may still be bytes
     * available.  You only know that no more bytes are available when you
     * are able to read until EOF. */
    optional func URLSession(session: NSURLSession, readClosedForStreamTask streamTask: FPSStreamTask)
    
    /* Indiciates that the write side of a connection has been closed.
     * Any outstanding writes complete, but future writes will immediately
     * fail.
     */
    optional func URLSession(session: NSURLSession, writeClosedForStreamTask streamTask: FPSStreamTask)
    
    /* A notification that the system has determined that a better route
     * to the host has been detected (eg, a wi-fi interface becoming
     * available.)  This is a hint to the delegate that it may be
     * desirable to create a new task for subsequent work.  Note that
     * there is no guarantee that the future task will be able to connect
     * to the host, so callers should should be prepared for failure of
     * reads and writes over any new interface. */
    optional func URLSession(session: NSURLSession, betterRouteDiscoveredForStreamTask streamTask: FPSStreamTask)
    
    /* The given task has been completed, and unopened NSInputStream and
     * NSOutputStream objects are created from the underlying network
     * connection.  This will only be invoked after all enqueued IO has
     * completed (including any necessary handshakes.)  The streamTask
     * will not receive any further delegate messages.
     */
    optional func URLSession(session: NSURLSession, streamTask: FPSStreamTask, didBecomeInputStream inputStream: NSInputStream, outputStream: NSOutputStream)
}

private let ports = ["http": 80,
                            "https": 443,
                            "smb": 445,
                            "ftp": 21,
                            "sftp": 22,
                            "sftp": 2121,
                            "telnet": 23,
                            "pop": 110,
                            "smtp": 25,
                            "imap": 143]
private let securePorts =  ["https": 443,
                                   "smb": 445,
                                   "sftp": 22,
                                   "sftp": 2121,
                                   "telnet": 992,
                                   "pop": 995,
                                   "smtp": 465,
                                   "imap": 993]