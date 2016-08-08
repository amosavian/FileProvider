//
//  SMBTransmitter.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

internal func encode<T>(inout value: T) -> NSData {
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}

internal func encode<T>(value: T) -> NSData {
    var value = value
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}

internal func decode<T>(data: NSData) -> T {
    let pointer = UnsafeMutablePointer<T>.alloc(sizeof(T.Type))
    data.getBytes(pointer, length: sizeof(T.Type))
    
    return pointer.move()
}

// This client implementation is for little-endian platform, namely x86, x64 & arm
// For big-endian platforms like PowerPC, there must be a huge overhaul

protocol SMBProtocolClientDelegate: class {
    func receivedSMB2Response(header: SMB2.Header, response: SMBResponse)
}

class SMBProtocolClient: TCPSocketClient {
    var currentMessageID: UInt64 = 0
    
    weak var delegate: SMBProtocolClientDelegate?
    
    func negotiateToSMB2() throws {
        let smbHeader = SMB2.Header(command: .NEGOTIATE, creditRequestResponse: 126, messageId: messageId(), treeId: 0, sessionId: 0)
        currentMessageID += 1
        let negMessage = SMB2.NegotiateRequest(request: SMB2.NegotiateRequest.Header(capabilities: []))
        createSMB2Message(smbHeader, message: negMessage)
        do {
            try self.send(data: nil)
        } catch let e {
            throw e
        }
    }
    
    func sessionSetupForSMB2() -> SMB2.SessionSetupResponse? {
        return nil
    }
    
    func messageId() -> UInt64 {
        defer {
            currentMessageID += 1
        }
        return currentMessageID
    }
    
    // MARK: create and analyse messages
    
    func determineSMBVersion(data: NSData) -> Float {
        var smbverChar: Int8 = 0
        data.getBytes(&smbverChar, length: 1)
        let version = 0 - smbverChar
        return Float(version)
    }
    
    func digestSMBMessage(data: NSData) throws -> (header: SMB1.Header, blocks: [(params: [UInt16], message: NSData?)]) {
        guard data.length > 30 else {
            throw NSURLError.BadServerResponse
        }
        var buffer = [UInt8](count: data.length, repeatedValue: 0)
        guard determineSMBVersion(data) == 1 else {
            throw SMBFileProviderError.IncompatibleHeader
        }
        let headersize = sizeof(SMB1.Header.self)
        let header: SMB1.Header = decode(data)
        var blocks = [(params: [UInt16], message: NSData?)]()
        var offset = headersize
        while offset < data.length {
            let paramWords: [UInt16]
            let paramWordsCount = Int(buffer[offset])
            guard data.length > (paramWordsCount * 2 + offset) else {
                throw SMBFileProviderError.IncorrectParamsLength
            }
            offset += sizeof(UInt8)
            var rawParamWords = [UInt8](buffer[offset..<(offset + paramWordsCount * 2)])
            let paramData = NSData(bytesNoCopy: &rawParamWords, length: rawParamWords.count)
            paramWords = decode(paramData)
            offset += paramWordsCount * 2
            let messageBytesCountLittleEndian = [UInt8](buffer[offset...(offset + 1)])
            let messageBytesCount = Int(UnsafePointer<UInt16>(messageBytesCountLittleEndian).memory)
            offset += sizeof(UInt16)
            guard data.length >= (offset + messageBytesCount) else {
                throw SMBFileProviderError.IncorrectMessageLength
            }
            var rawMessage = [UInt8](buffer[offset..<(offset + messageBytesCount)])
            offset += messageBytesCount
            let message = NSData(bytes: &rawMessage, length: rawMessage.count)
            blocks.append((params: paramWords, message: message))
        }
        return (header, blocks)
    }
    
    func digestSMB2Message(data: NSData) throws -> (header: SMB2.Header, message: SMBResponse?)? {
        guard data.length > 65 else {
            throw NSURLError.BadServerResponse
        }
        guard determineSMBVersion(data) == 2 else {
            throw SMBFileProviderError.IncompatibleHeader
        }
        let headersize = sizeof(SMB2.Header.self)
        let headerData = data.subdataWithRange(NSRange(location: 0, length: headersize))
        let messageSize = data.length - headersize
        let messageData = data.subdataWithRange(NSRange(location: headersize, length: messageSize))
        let header: SMB2.Header = decode(headerData)
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
            return (header, nil) // FIXME:
        case .WRITE:
            return (header, nil) // FIXME:
        case .LOCK:
            return (header, nil) // FIXME:
        case .IOCTL:
            return (header, nil)
        case .CANCEL:
            return (header, nil)
        case .ECHO:
            return (header, SMB2.Echo(data: messageData))
        case .QUERY_DIRECTORY:
            return (header, SMB2.QueryDirectoryResponse(data: messageData))
        case .CHANGE_NOTIFY:
            return (header, nil) // FIXME:
        case .QUERY_INFO:
            return (header, nil) // FIXME:
        case .SET_INFO:
            return (header, nil) // FIXME:
        case .OPLOCK_BREAK:
            return (header, nil) // FIXME:
        case .INVALID:
            throw SMBFileProviderError.InvalidCommand
        }
    }
    
    func createSMBMessage(header: SMB1.Header, blocks: [(params: NSData?, message: NSData?)]) -> NSData {
        var headerv = header
        let result = NSMutableData(data: encode(&headerv))
        for block in blocks {
            var paramWordsCount = UInt8(block.params?.length ?? 0)
            result.appendBytes(&paramWordsCount, length: sizeofValue(paramWordsCount))
            if let params = block.params {
                result.appendData(params)
            }
            var messageLen = UInt16(block.message?.length ?? 0)
            result.appendBytes(&messageLen, length: sizeofValue(messageLen))
            if let message = block.message {
                result.appendData(message)
            }
        }
        return result
    }
    
    func createSMB2Message(header: SMB2.Header, message: SMBRequest) -> NSData {
        var headerv = header
        let result = NSMutableData(data: encode(&headerv))
        result.appendData(message.data())
        return result
    }
}

protocol FileProviderSMBHeader {
    var protocolID: UInt32 { get }
    static var protocolConst: UInt32 { get }
}