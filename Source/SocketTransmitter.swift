//
//  SocketTransmitter.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/9/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

class TCPSocketTransmitter: NSObject, NSStreamDelegate {
    static let ports = ["http": 80,
                        "https": 443,
                        "smb": 445,
                        "ftp": 21,
                        "sftp": 22,
                        "sftp": 2121,
                        "telnet": 23,
                        "pop": 110,
                        "smtp": 25,
                        "imap": 143]
    static let securePorts =  ["https": 443,
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
    let dataRecieved: NSMutableData = NSMutableData()
    
    let baseURL: NSURL
    let secureConnection: Bool
    private let port: UInt32
    private var connected = false
    
    init?(baseURL: NSURL, secure: Bool = false) {
        self.baseURL = baseURL
        self.secureConnection = secure
        let scheme = baseURL.scheme.lowercaseString
        let defaultPort = secure ? UInt32(TCPSocketTransmitter.securePorts[scheme] ?? 0) : UInt32(TCPSocketTransmitter.ports[scheme] ?? 0)
        self.port = baseURL.port?.unsignedIntValue ?? defaultPort
        if self.port == 0 {
            return nil
        }
    }
    
    deinit {
        disconnect()
    }
    
    func connect() -> Bool {
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
    
    func disconnect() {
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
    
    func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        switch (eventCode) {
        case NSStreamEvent.ErrorOccurred:
            break
        case NSStreamEvent.EndEncountered:
            connected = false
        case NSStreamEvent.None:
            break
        case NSStreamEvent.OpenCompleted:
            let activeStatus: [NSStreamStatus] = [.Open, .Reading, .Writing, .AtEnd]
            connected = activeStatus.contains(inputStream?.streamStatus ?? .NotOpen) && activeStatus.contains(outputStream?.streamStatus ?? .NotOpen)
        case NSStreamEvent.HasBytesAvailable:
            var buffer = [UInt8](count: 2048, repeatedValue: 0)
            if ( aStream == inputStream) {
                while (inputStream!.hasBytesAvailable ?? false) {
                    let len = inputStream!.read(&buffer, maxLength: buffer.count)
                    if len > 0 {
                        dataRecieved.appendBytes(&buffer, length: len)
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
    
    func send(data data: NSData?) throws {
        if self.outputStream?.hasSpaceAvailable ?? false {
            if let data = data {
                dataToBeSent.appendData(data)
            }
            
            if dataToBeSent.length > 0 {
                let bytesWritten = self.outputStream?.write(UnsafePointer(dataToBeSent.bytes), maxLength: dataToBeSent.length) ?? -1
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
    
    func waitForSendDataPurge() {
        if NSThread.isMainThread() {
            assertionFailure("waitForSendDataPurge() method can't be called from main thread")
        }
        while true {
            if dataToBeSent.length == 0 {
                break
            }
            
            NSRunLoop.currentRunLoop().runUntilDate(NSDate(timeIntervalSinceNow: 0.1));
            NSThread.sleepForTimeInterval(0.1)
        }
    }
    
    func waitForResponse() -> Bool {
        if NSThread.isMainThread() {
            assertionFailure("waitForResponse() method can't be called from main thread")
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