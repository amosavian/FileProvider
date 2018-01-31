//
//  SMB2NegotiationTypes.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

extension SMB2 {
    // MARK: SMB2 Negotiating
    
    struct NegotiateRequest: SMBRequestBody {
        static var command: SMB2.Command = .NEGOTIATE
        
        let header: NegotiateRequest.Header
        let dialects: [UInt16]
        let contexts: [(type: NegotiateContextType, data: Data)]
        
        init(header: NegotiateRequest.Header, dialects: [UInt16] = [0x0202], contexts: [(type: NegotiateContextType, data: Data)] = []) {
            self.header = header
            self.dialects = dialects
            self.contexts = contexts
        }
        
        init(dialects: [UInt16] = [0x0202], contexts: [(type: NegotiateContextType, data: Data)] = [],capabilities: GlobalCapabilities = [], clientStartTime: SMBTime? = nil, guid: uuid_t? = nil, signing: NegotiateSinging = [.ENABLED]) {
            self.header = Header(capabilities: capabilities, clientStartTime: clientStartTime, guid: guid, signing: signing)
            self.dialects = dialects
            self.contexts = contexts
        }
        
        func data() -> Data {
            var header = self.header
            header.dialectCount = UInt16(dialects.count)
            var dialectData = Data()
            for dialect in dialects {
                var dialect = dialect
                dialectData.append(UnsafeBufferPointer(start: &dialect, count: 2))
            }
            let pad = ((1024 - dialectData.count) % 8)
            dialectData.count += pad
            header.contextOffset = UInt32(MemoryLayout<NegotiateRequest.Header>.size) + UInt32(dialectData.count)
            header.contextCount = UInt16(contexts.count)
            
            var contextData = Data()
            for context in contexts {
                contextData.append(Data(value: context.type.rawValue))
                contextData.count += 4
                contextData.append(Data(value: UInt16(context.data.count)))
            }
            var result = Data(value: header)
            result.append(dialectData as Data)
            result.append(contextData as Data)
            return result
        }
        
        struct Header {
            var size: UInt16
            var dialectCount: UInt16
            let signing: NegotiateSinging
            fileprivate let reserved: UInt16
            let capabilities: GlobalCapabilities
            let guid: uuid_t
            var contextOffset: UInt32
            var contextCount: UInt16
            fileprivate let reserved2: UInt16
            var clientStartTime: SMBTime {
                let lo = Int64(contextOffset)
                let hi1 = Int64(contextCount) << 32
                let hi2 = Int64(contextCount) << 48
                let time: Int64 = lo + hi1 + hi2
                return SMBTime(time: time)
            }
            
            init(capabilities: GlobalCapabilities, clientStartTime: SMBTime? = nil, guid: uuid_t? = nil, signing: NegotiateSinging = [.ENABLED]) {
                self.size = 36
                self.dialectCount = 0
                self.signing = signing
                self.reserved = 0
                self.capabilities = capabilities
                self.guid = guid ?? (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
                if let clientStartTime = clientStartTime {
                    let time = clientStartTime.time
                    self.contextOffset = UInt32(time & 0xffffffff)
                    self.contextCount = UInt16(time & 0x0000ffff00000000 >> 32)
                    self.reserved2 = UInt16(time >> 48)
                } else {
                    self.contextOffset = 0
                    self.contextCount = 0
                    self.reserved2 = 0
                }
            }
        }
    }
    
    struct NegotiateResponse: SMBResponseBody {
        let header: NegotiateResponse.Header
        let buffer: Data?
        let contexts: [(type: NegotiateContextType, data: Data)]
        
        init? (data: Data) {
            guard data.count >= 64 else {
                return nil
            }
            self.header = data.scanValue()!
            if Int(header.size) != 65 {
                return nil
            }
            let bufOffset = Int(self.header.bufferOffset) - MemoryLayout<SMB2.Header>.size
            let bufLen = Int(self.header.bufferLength)
            if bufOffset > 0 && bufLen > 0 && data.count >= bufOffset + bufLen {
                self.buffer = data.subdata(in: bufOffset..<(bufOffset + bufLen))
            } else {
                self.buffer = nil
            }
            let contextCount = Int(self.header.contextCount)
            let contextOffset = Int(self.header.contextOffset) - MemoryLayout<SMB2.Header>.size
            if  contextCount > 0 &&  contextOffset > 0 {
                // TODO: NegotiateResponse context support for SMB3
                self.contexts = []
            } else {
                self.contexts = []
            }
        }
        
        struct Header {
            let size: UInt16
            let singing: NegotiateSinging
            let dialect: UInt16
            let contextCount: UInt16
            let serverGuid: uuid_t
            let capabilities: GlobalCapabilities
            let maxTransactSize: UInt32
            let maxReadSize: UInt32
            let maxWriteSize: UInt32
            let systemTime: SMBTime
            let serverStartTime: SMBTime
            let bufferOffset: UInt16
            let bufferLength: UInt16
            let contextOffset: UInt32
        }
    }
    
    struct NegotiateSinging: OptionSet {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        static let ENABLED   = NegotiateSinging(rawValue: 0x0001)
        static let REQUIRED  = NegotiateSinging(rawValue: 0x0002)
    }
    
    struct NegotiateContextType: OptionSet {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        static let PREAUTH_INTEGRITY_CAPABILITIES   = NegotiateContextType(rawValue: 0x0001)
        static let ENCRYPTION_CAPABILITIES          = NegotiateContextType(rawValue: 0x0002)
    }
    
    struct GlobalCapabilities: OptionSet {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        static let DFS                  = GlobalCapabilities(rawValue: 0x00000001)
        static let LEASING              = GlobalCapabilities(rawValue: 0x00000002)
        static let LARGE_MTU            = GlobalCapabilities(rawValue: 0x00000004)
        static let MULTI_CHANNEL        = GlobalCapabilities(rawValue: 0x00000008)
        static let PERSISTENT_HANDLES   = GlobalCapabilities(rawValue: 0x00000010)
        static let DIRECTORY_LEASING    = GlobalCapabilities(rawValue: 0x00000020)
        static let ENCRYPTION           = GlobalCapabilities(rawValue: 0x00000040)
    }
    
    // MARK: SMB2 Session Setup
    
    struct SessionSetupRequest: SMBRequestBody {
        static var command: SMB2.Command = .SESSION_SETUP
        
        let header: SessionSetupRequest.Header
        let buffer: Data?
        
        init(header: SessionSetupRequest.Header, buffer: Data) {
            self.header = header
            self.buffer = buffer
        }
        
        init(sessionId: UInt64 = 0, flags: SessionSetupRequest.Flags = [], singing: SessionSetupSinging = [.ENABLED], capabilities: GlobalCapabilities = [], securityData: Data? = nil) {
            self.header = Header(sessionId: sessionId, flags: flags, singing: singing, capabilities: capabilities)
            self.buffer = securityData
        }
        
        func data() -> Data {
            var header = self.header
            header.bufferOffset = UInt16(MemoryLayout<SMB2.Header>.size + MemoryLayout<SessionSetupRequest.Header>.size)
            header.bufferLength = UInt16(buffer?.count ?? 0)
            var result = Data(value: header)
            if let buffer = self.buffer {
                result.append(buffer)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            let flags: SessionSetupRequest.Flags
            let signing: SessionSetupSinging
            let capabilities: GlobalCapabilities
            fileprivate let channel: UInt32
            var bufferOffset: UInt16
            var bufferLength: UInt16
            let sessionId: UInt64
            
            init(sessionId: UInt64, flags: SessionSetupRequest.Flags = [], singing: SessionSetupSinging, capabilities: GlobalCapabilities) {
                self.size = 25
                self.flags = flags
                self.signing = singing
                self.capabilities = capabilities
                self.channel = 0
                self.bufferOffset = 0
                self.bufferLength = 0
                self.sessionId = sessionId
            }
        }
        
        /// Works the client implements the SMB 3.x dialect family
        struct Flags: OptionSet {
            let rawValue: UInt8
            
            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            static let BINDING = NegotiateSinging(rawValue: 0x01)
        }
    }
    
    struct SessionSetupResponse: SMBResponseBody {
        let header: SessionSetupResponse.Header
        let buffer: Data?
        
        init? (data: Data) {
            guard data.count >= 64 else {
                return nil
            }
            self.header = data.scanValue()!
            if Int(header.size) != 9 {
                return nil
            }
            let bufOffset = Int(self.header.bufferOffset) - MemoryLayout<SMB2.Header>.size
            let bufLen = Int(self.header.bufferLength)
            if bufOffset > 0 && bufLen > 0 && data.count >= bufOffset + bufLen {
                self.buffer = data.subdata(in: bufOffset..<(bufOffset + bufLen))
            } else {
                self.buffer = nil
            }
        }
        
        struct Header {
            let size: UInt16
            let flags: SessionSetupResponse.Flags
            let bufferOffset: UInt16
            let bufferLength: UInt16
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt16
            
            init(rawValue: UInt16) {
                self.rawValue = rawValue
            }
            
            static let IS_GUEST     = Flags(rawValue: 0x0001)
            static let IS_NULL      = Flags(rawValue: 0x0002)
            static let ENCRYPT_DATA = Flags(rawValue: 0x0004)
        }
    }
    
    struct SessionSetupSinging: OptionSet {
        let rawValue: UInt8
        
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        static let ENABLED   = SessionSetupSinging(rawValue: 0x01)
        static let REQUIRED  = SessionSetupSinging(rawValue: 0x02)
    }
    
    // MARK: SMB2 Log off
    
    struct LogOff: SMBRequestBody, SMBResponseBody {
        static var command: SMB2.Command = .LOGOFF
        
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
    }
    
    // MARK: SMB2 Echo
    
    struct Echo: SMBRequestBody, SMBResponseBody {
        static var command: SMB2.Command = .ECHO
        
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
    }
}
