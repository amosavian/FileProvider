//
//  SMBTransmitter.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

// This client implementation is for little-endian platform, namely x86, x64 & arm
// For big-endian platforms like PowerPC, there must be a huge overhaul

enum SMBClientError: Error {
    case streamNotOpened
    case timedOut
}

@objcMembers
class SMBClient: NSObject, StreamDelegate {
    fileprivate var inputStream: InputStream?
    fileprivate var outputStream: OutputStream?
    fileprivate var operation_queue: OperationQueue!
    
    fileprivate var host: (hostname: String, port: Int)?
    fileprivate var service: NetService?
    
    public var timeout: TimeInterval = 30
    
    internal private(set) var messageId: UInt64 = 0
    private func createMessageId() -> UInt64 {
        defer {
            messageId += 1
        }
        return messageId
    }
    
    internal private(set) var credit: UInt16 = 0
    private func consumeCredit() -> UInt16 {
        if credit > 0 {
            credit -= 1
            return credit
        } else {
            return 0
        }
    }
    
    private(set) var sessionId: UInt64 = 0
    
    private(set) var establishedTrees = Array<SMB2.TreeConnectResponse>()
    private(set) var requestStack = [Int: SMBRequest]()
    private(set) var responseStack = [Int: SMBResponse]()
    
    init(host: String, port: Int) {
        self.host = (host, port)
        self.operation_queue = OperationQueue()
        self.operation_queue.name = "FileProviderStreamTask"
        self.operation_queue.maxConcurrentOperationCount = 1
        super.init()
    }
    
    deinit {
        close()
    }
    
    fileprivate func open(secure: Bool = false) {
        var readStream : Unmanaged<CFReadStream>?
        var writeStream : Unmanaged<CFWriteStream>?
        
        if inputStream == nil || outputStream == nil {
            if let host = host {
                CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host.hostname as CFString, UInt32(host.port), &readStream, &writeStream)
            } else if let service = service {
                let cfnetService = CFNetServiceCreate(kCFAllocatorDefault, service.domain as CFString, service.type as CFString, service.name as CFString, Int32(service.port))
                CFStreamCreatePairWithSocketToNetService(kCFAllocatorDefault, cfnetService.takeRetainedValue(), &readStream, &writeStream)
            }
            
            inputStream = readStream?.takeRetainedValue()
            outputStream = writeStream?.takeRetainedValue()
        }
        
        guard let inputStream = inputStream, let outputStream = outputStream else {
            return
        }
        
        if secure {
            inputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue, forKey: .socketSecurityLevelKey)
            outputStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue, forKey: .socketSecurityLevelKey)
        }
        
        inputStream.delegate = self
        outputStream.delegate = self
        inputStream.schedule(in: RunLoop.main, forMode: .defaultRunLoopMode)
        outputStream.schedule(in: RunLoop.main, forMode: .defaultRunLoopMode)
        inputStream.open()
        outputStream.open()
        
        operation_queue.isSuspended = false
    }
    
    fileprivate func close() {
        self.inputStream?.close()
        self.outputStream?.close()
        self.inputStream?.remove(from: RunLoop.main, forMode: .defaultRunLoopMode)
        self.outputStream?.remove(from: RunLoop.main, forMode: .defaultRunLoopMode)
        self.inputStream?.delegate = nil
        self.outputStream?.delegate = nil
        
        self.inputStream = nil
        self.outputStream = nil
    }
    
    @discardableResult
    fileprivate func write(data: Data) throws -> Int {
        guard let outputStream = self.outputStream else {
            throw SMBClientError.streamNotOpened
        }
        let expireDate = Date(timeIntervalSinceNow: timeout)
        var data = data
        var byteSent: Int = 0
        while data.count > 0 {
            let bytesWritten = data.withUnsafeBytes {
                outputStream.write($0, maxLength: data.count)
            }
            
            if bytesWritten > 0 {
                let range = 0..<bytesWritten
                data.replaceSubrange(range, with: Data())
                byteSent += bytesWritten
            } else if bytesWritten < 0 {
                if let error = outputStream.streamError {
                    throw error
                }
                return bytesWritten
            }
            if data.count == 0 {
                break
            }
            if expireDate < Date() {
                throw SMBClientError.timedOut
            }
            
        }
        return byteSent
    }
    
    var currentHandlingData: Data = Data()
    var expectedBytes = 0
    
    open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode.contains(.errorOccurred) {
            /*self._error = aStream.streamError
            streamDelegate?.urlSession?(_underlyingSession, task: self, didCompleteWithError: error)*/
        }
        
        if aStream == inputStream && eventCode.contains(.hasBytesAvailable) {
            while (inputStream!.hasBytesAvailable) {
                var buffer = [UInt8](repeating: 0, count: 65536)
                let len = inputStream!.read(&buffer, maxLength: buffer.count)
                if len > 0 {
                    
                    /*dataReceived.append(&buffer, count: len)
                    self._countOfBytesRecieved += Int64(len)*/
                }
            }
        }
    }
}

// MARK: create and analyse messages
extension SMBClient {
    internal func sendMessage(_ message: SMBRequestBody, toTree treeId: UInt32, completionHandler: SimpleCompletionHandler) -> UInt64 {
        let mId = createMessageId()
        let credit = consumeCredit()
        let smbHeader = SMB2.Header(command: message.command, creditRequestResponse: credit, messageId: mId, treeId: treeId, sessionId: sessionId)
        let data = createRequest(header: smbHeader, message: message)
        operation_queue.addOperation {
            do {
                try self.write(data: data)
                completionHandler?(nil)
            } catch {
                completionHandler?(error)
            }
        }
        return mId
    }
}


fileprivate extension SMBClient {
    func determineSMBVersion(_ data: Data) -> Float {
        let smbverChar: Int8 = Int8(bitPattern: data.first ?? 0)
        let version = 0 - smbverChar
        return Float(version)
    }
    
    func createRequest(header: SMB2.Header, message: SMBRequestBody) -> Data {
        var result = Data(value: header)
        result.append(message.data())
        return result
    }
    
    func responseOf(_ data: Data) throws -> SMBResponse? {
        guard data.count > 65 else {
            throw URLError(.badServerResponse)
        }
        guard determineSMBVersion(data) >= 2 else {
            throw SMBFileProviderError.incompatibleHeader
        }
        let headersize = MemoryLayout<SMB2.Header>.size
        let headerData = data.subdata(in: 0..<headersize)
        let messageSize = data.count - headersize
        let messageData = data.subdata(in: headersize..<(headersize + messageSize))
        let header: SMB2.Header = headerData.scanValue()!
        switch header.command {
        case .NEGOTIATE:
            return (header, SMB2.NegotiateResponse(data: messageData))
        case .SESSION_SETUP:
            return (header, SMB2.SessionSetupResponse(data: messageData))
        case .LOGOFF:
            return (header, SMB2.LogOff(data: messageData))
        case .TREE_CONNECT:
            return (header, SMB2.TreeConnectResponse(data: messageData))
        case .TREE_DISCONNECT:
            return (header, SMB2.TreeDisconnect(data: messageData))
        case .CREATE:
            return (header, SMB2.CreateResponse(data: messageData))
        case .CLOSE:
            return (header, SMB2.CloseResponse(data: messageData))
        case .FLUSH:
            return (header, SMB2.FlushResponse(data: messageData))
        case .READ:
            return (header, SMB2.ReadRespone(data: messageData))
        case .WRITE:
            return (header, SMB2.WriteResponse(data: messageData))
        case .LOCK:
            return (header, SMB2.LockResponse(data: messageData))
        case .IOCTL:
            return (header, SMB2.IOCtlResponse(data: messageData))
        case .CANCEL:
            return (header, nil)
        case .ECHO:
            return (header, SMB2.Echo(data: messageData))
        case .QUERY_DIRECTORY:
            return (header, SMB2.QueryDirectoryResponse(data: messageData))
        case .CHANGE_NOTIFY:
            return (header, SMB2.ChangeNotifyResponse(data: messageData))
        case .QUERY_INFO:
            return (header, SMB2.QueryInfoResponse(data: messageData))
        case .SET_INFO:
            return (header, SMB2.SetInfoResponse(data: messageData))
        case .OPLOCK_BREAK:
            return (header, nil) // FIXME:
        default:
            throw SMBFileProviderError.invalidCommand
        }
    }
    
    /*func createSMBMessage(header: SMB1.Header, blocks: [(params: Data?, message: Data?)]) -> Data {
        var result = Data(value: header)
        for block in blocks {
            var paramWordsCount = UInt8(block.params?.count ?? 0)
            result.append(&paramWordsCount, count: MemoryLayout.size(ofValue: paramWordsCount))
            if let params = block.params {
                result.append(params)
            }
            var messageLen = UInt16(block.message?.count ?? 0)
            let b = UnsafeBufferPointer(start: &messageLen, count: MemoryLayout.size(ofValue: messageLen))
            result.append(b)
            if let message = block.message {
                result.append(message)
            }
        }
        return result
    }*/
    
    /*func digestSMBMessage(_ data: Data) throws -> (header: SMB1.Header, blocks: [(params: [UInt16], message: Data?)]) {
     guard data.count > 30 else {
     throw URLError(.badServerResponse)
     }
     var buffer = [UInt8](repeating: 0, count: data.count)
     guard determineSMBVersion(data) == 1 else {
     throw SMBFileProviderError.incompatibleHeader
     }
     let headersize = MemoryLayout<SMB1.Header>.size
     let header: SMB1.Header = data.scanValue()!
     var blocks = [(params: [UInt16], message: Data?)]()
     var offset = headersize
     while offset < data.count {
     let paramWords: [UInt16]
     let paramWordsCount = Int(buffer[offset])
     guard data.count > (paramWordsCount * 2 + offset) else {
     throw SMBFileProviderError.incorrectParamsLength
     }
     offset += MemoryLayout<UInt8>.size
     var rawParamWords = [UInt8](buffer[offset..<(offset + paramWordsCount * 2)])
     let paramData = Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(&rawParamWords), count: rawParamWords.count, deallocator: .free)
     paramWords = paramData.scanValue()!
     offset += paramWordsCount * 2
     let messageBytesCountHi = Int(buffer[1]) << 8
     let messageBytesCount = Int(buffer[0]) + messageBytesCountHi
     offset += MemoryLayout<UInt16>.size
     guard data.count >= (offset + messageBytesCount) else {
     throw SMBFileProviderError.incorrectMessageLength
     }
     let rawMessage = [UInt8](buffer[offset..<(offset + messageBytesCount)])
     offset += messageBytesCount
     let message = Data(bytes: rawMessage)
     blocks.append((params: paramWords, message: message))
     }
     return (header, blocks)
     }*/
}
