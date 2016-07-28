//
//  SocketTransmitter.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public class TCPSocketClient: NSObject, NSStreamDelegate {
    public static let ports = ["http": 80,
                        "https": 443,
                        "smb": 445,
                        "ftp": 21,
                        "sftp": 22,
                        "sftp": 2121,
                        "telnet": 23,
                        "pop": 110,
                        "smtp": 25,
                        "imap": 143]
    public static let securePorts =  ["https": 443,
                               "smb": 445,
                               "sftp": 22,
                               "sftp": 2121,
                               "telnet": 992,
                               "pop": 995,
                               "smtp": 465,
                               "imap": 993]
    
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    private var dataToBeSent: NSMutableData = NSMutableData()
    /// holds data received from server
    public let dataReceived: NSMutableData = NSMutableData()
    /// a url with valid scheme, dns or ip host and ports path and query sections will be neglected
    public let baseURL: NSURL
    /// a url with valid scheme, dns or ip host and ports path and query sections will be neglected
    public let secureConnection: Bool
    /// server's ports which is value between 1 to 65535
    private let port: UInt32
    private var open = false
    
    /**
     * - parameter baseURL: a url with valid scheme, dns or ip host and ports
     * path and query sections will be neglected
     *
     * **Note** Call `connect()` to establish connection
     * - parameter secure: establishing connection using an SSL/TLS connection
     */
    
    public init?(baseURL: NSURL, secure: Bool = false) {
        self.baseURL = baseURL
        self.secureConnection = secure
        let scheme = baseURL.uw_scheme.lowercaseString
        let defaultPort = secure ? UInt32(TCPSocketClient.securePorts[scheme] ?? 0) : UInt32(TCPSocketClient.ports[scheme] ?? 0)
        self.port = baseURL.port?.unsignedIntValue ?? defaultPort
        if self.port == 0 {
            return nil
        }
    }
    
    deinit {
        disconnect()
    }

    /**
     * Establshes a connection to desired server
     * - returns: A bool value which indicated there where no system error during
     * creating connection
     */
    
    public func connect() -> Bool {
        guard let hostStr = baseURL.host else {
            return false
        }
        var readStream : Unmanaged<CFReadStream>?
        var writeStream : Unmanaged<CFWriteStream>?
        let host : CFString = NSString(string: hostStr)
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host, self.port, &readStream, &writeStream)
        inputStream = readStream?.takeRetainedValue()
        outputStream = writeStream?.takeRetainedValue()
        
        guard let inputStream = inputStream, outputStream = outputStream else {
            return false
        }
        
        inputStream.delegate = self
        outputStream.delegate = self
        
        inputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        
        if secureConnection {
            inputStream.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            outputStream.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
        }
        
        inputStream.open()
        outputStream.open()
        return true
    }
    
    /**
     * Terminates connection to the server
     */
    
    public func disconnect() {
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
    }
    
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        switch (eventCode) {
        case NSStreamEvent.ErrorOccurred:
            open = false
        case NSStreamEvent.EndEncountered:
            break
        case NSStreamEvent.None:
            break
        case NSStreamEvent.OpenCompleted:
            let activeStatus: [NSStreamStatus] = [.Open, .Reading, .Writing, .AtEnd]
            open = activeStatus.contains(inputStream?.streamStatus ?? .NotOpen) && activeStatus.contains(outputStream?.streamStatus ?? .NotOpen)
        case NSStreamEvent.HasBytesAvailable:
            var buffer = [UInt8](count: 2048, repeatedValue: 0)
            if ( aStream == inputStream) {
                while (inputStream!.hasBytesAvailable ?? false) {
                    let len = inputStream!.read(&buffer, maxLength: buffer.count)
                    if len > 0 {
                        dataReceived.appendBytes(&buffer, length: len)
                    }
                }
            }
        case NSStreamEvent.HasSpaceAvailable:
            if aStream == outputStream {
                do {
                    try send(data: nil)
                } catch _ {
                    NSLog("Sending error")
                }
                
            }
        default:
            break
        }
    }
    
    /**
     * Sends data to server
     * - parameter data: data which is intended to be sent to server
     * - throws: NSURLError.NetworkConnectionLost in case of server disconnects disgracefully
     */
    
    public func send(data data: NSData?) throws {
        guard let outputStream = outputStream else {
            return
        }
        if outputStream.hasSpaceAvailable ?? false {
            if let data = data {
                dataToBeSent.appendData(data)
            }
            
            if dataToBeSent.length > 0 {
                let bytesWritten = outputStream.write(UnsafePointer(dataToBeSent.bytes), maxLength: dataToBeSent.length) ?? -1
                if bytesWritten > 0 {
                    let range = NSRange(location: 0, length: bytesWritten)
                    dataToBeSent.replaceBytesInRange(range, withBytes: nil, length: 0)
                } else {
                    throw NSError(domain: NSURLErrorDomain, code:  NSURLError.NetworkConnectionLost.rawValue, userInfo: nil)
                }
            }
            //println("Sent the following")
        } else { //steam busy
            if let data = data {
                dataToBeSent.appendData(data)
            }
        }
    }
    
    /**
     * Clears entire send and receive buffer
     */
    
    public func flush() {
        dataToBeSent.length = 0
        dataReceived.length = 0
    }
    
    /**
     * Put's thread in sleep until all data is sent
     * **Note:** Don't call this method from main thread
     */
    
    internal func waitUntillDataSent() {
        if NSThread.isMainThread() {
            assert(false, "waitUntillDataSent() method can't be called from main thread")
        }
        while true {
            if dataToBeSent.length == 0 {
                break
            }
            
            NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
            NSThread.sleepForTimeInterval(0.1)
        }
    }
    
    /**
     * Put's thread in sleep until all response from server is loaded into tcp stack
     * server response can be retrieved by `dataReceived` property
     * **Note:** Don't call this method from main thread
     * - returns: A Bool value indicates all response loaded from server successfullt
    */
    
    internal func waitUntilResponse() -> Bool {
        if NSThread.isMainThread() {
            assert(false, "waitUntilResponse() method can't be called from main thread")
        }
        var finished = false
        while !finished {
            switch inputStream?.streamStatus ?? .Error {
            case .AtEnd:
                finished = true
                return true
            case .Closed, .Error:
                return false
            default:
                finished = false
            }
            
            NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
            NSThread.sleepForTimeInterval(0.1)
        }
        return false
    }
}