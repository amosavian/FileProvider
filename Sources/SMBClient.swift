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

protocol SMBProtocolClientDelegate: class {
    func receivedSMB2Response(_ header: SMB2.Header, response: SMBResponse)
}

class SMB2ProtocolClient: FPSStreamTask {
    var currentMessageID: UInt64 = 0
    var sessionId: UInt64 = 0
    
    weak var delegate: SMBProtocolClientDelegate?
    
    func sendNegotiate(completionHandler: SimpleCompletionHandler) -> UInt64 {
        let mId = messageId()
        let smbHeader = SMB2.Header(command: .NEGOTIATE, creditRequestResponse: UInt16(126), messageId: mId, treeId: UInt32(0), sessionId: UInt64(0))
        let msg = SMB2.NegotiateRequest()
        let data = createSMB2Message(header: smbHeader, message: msg)
        self.writeData(data, timeout: 0, completionHandler: { (e) in
            completionHandler?(e)
        })
        return mId
    }
    
    func sendSessionSetup(completionHandler: SimpleCompletionHandler) -> UInt64 {
        let mId = messageId()
        let credit = UInt16(sessionId > 0 ? 124 : 125)
        let smbHeader = SMB2.Header(command: SMB2.Command.SESSION_SETUP, creditRequestResponse: credit, messageId: mId, treeId: UInt32(0), sessionId: sessionId)
        let msg = SMB2.SessionSetupRequest(singing: [])
        let data = createSMB2Message(header: smbHeader, message: msg)
        self.writeData(data, timeout: 0, completionHandler: { (e) in
            if self.sessionId == 0 {
                self.readData(OfMinLength: 64, maxLength: 65536, timeout: 30, completionHandler: { (data, eof, e2) in
                    // TODO: set session id
                    completionHandler?(e2 ?? e)
                })
            }
        })
        return mId
    }
    
    func sendTreeConnect(completionHandler: SimpleCompletionHandler) -> UInt64 {
        let req = self.currentRequest ?? self.originalRequest
        guard let url = req?.url, let host = url.host else {
            return 0
        }
        let mId = messageId()
        let smbHeader = SMB2.Header(command: .TREE_CONNECT, creditRequestResponse: 123, messageId: mId, treeId: 0, sessionId: sessionId)
        var share = ""
        let cmp = url.pathComponents
        if cmp.count > 0 {
            share = cmp[0]
        }
        let tcHeader = SMB2.TreeConnectRequest.Header(flags: [])
        let msg = SMB2.TreeConnectRequest(header: tcHeader, host: host, share: share)
        let data = createSMB2Message(header: smbHeader, message: msg!)
        self.writeData(data, timeout: 0, completionHandler: { (e) in
            completionHandler?(e)
            
        })
        return mId
    }
    
    func sendTreeDisconnect(id treeId: UInt32, completionHandler: SimpleCompletionHandler) -> UInt64 {
        let mId = messageId()
        let smbHeader = SMB2.Header(command: .TREE_DISCONNECT, creditRequestResponse: 111, messageId: mId, treeId: treeId, sessionId: sessionId)
        let msg = SMB2.TreeDisconnect()
        let data = createSMB2Message(header: smbHeader, message: msg)
        self.writeData(data, timeout: 0, completionHandler: { (e) in
            completionHandler?(e)
        })
        return mId
    }
    
    func sendLogoff(id treeId: UInt32, completionHandler: SimpleCompletionHandler) -> UInt64 {
        let mId = messageId()
        let smbHeader = SMB2.Header(command: .LOGOFF, creditRequestResponse: 0, messageId: mId, treeId: 0, sessionId: sessionId)
        let msg = SMB2.LogOff()
        let data = createSMB2Message(header: smbHeader, message: msg)
        self.writeData(data, timeout: 0, completionHandler: { (e) in
            completionHandler?(e)
        })
        return mId
    }
    
    func messageId() -> UInt64 {
        defer {
            currentMessageID += 1
        }
        return currentMessageID
    }
}

// MARK: create and analyse messages
extension SMB2ProtocolClient {
    func determineSMBVersion(_ data: Data) -> Float {
        let smbverChar: Int8 = Int8(bitPattern: data.first ?? 0)
        let version = 0 - smbverChar
        return Float(version)
    }
    
    func digestSMBMessage(_ data: Data) throws -> (header: SMB1.Header, blocks: [(params: [UInt16], message: Data?)]) {
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
            let messageBytesCount = Int(UInt16(buffer[0]) + UInt16(buffer[1]) << 8)
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
    }
    
    func digestSMB2Message(_ data: Data) throws -> (header: SMB2.Header, message: SMBResponse?)? {
        guard data.count > 65 else {
            throw URLError(.badServerResponse)
        }
        guard determineSMBVersion(data) == 2 else {
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
        case .INVALID:
            throw SMBFileProviderError.invalidCommand
        }
    }
    
    func createSMBMessage(header: SMB1.Header, blocks: [(params: Data?, message: Data?)]) -> Data {
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
    }
    
    func createSMB2Message(header: SMB2.Header, message: SMBRequest) -> Data {
        var result = Data(value: header)
        result.append(message.data())
        return result
    }
}
