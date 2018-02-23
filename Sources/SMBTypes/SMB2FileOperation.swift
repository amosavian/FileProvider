//
//  SMB2FileOperation.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

extension SMB2 {
    // MARK: SMB2 Read
    
    struct ReadRequest: SMBRequestBody {
        static var command: SMB2.Command = .READ
        
        let size: UInt16
        fileprivate let padding: UInt8
        let flags: ReadRequest.Flags
        let length: UInt32
        let offset: UInt64
        let fileId: FileId
        let minimumLength: UInt32
        let channel: Channel
        let remainingBytes: UInt32
        fileprivate let channelInfoOffset: UInt16
        fileprivate let channelInfoLength: UInt16
        fileprivate let channelBuffer: UInt8
        
        init (fileId: FileId, offset: UInt64, length: UInt32, flags: ReadRequest.Flags = [], minimumLength: UInt32 = 0, remainingBytes: UInt32 = 0, channel: Channel = .NONE) {
            self.size = 49
            self.padding = 0
            self.flags = flags
            self.length = length
            self.offset = offset
            self.fileId = fileId
            self.minimumLength = minimumLength
            self.channel = channel
            self.remainingBytes = remainingBytes
            self.channelInfoOffset = 0
            self.channelInfoLength = 0
            self.channelBuffer = 0
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt8
            
            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            static let UNBUFFERED = Flags(rawValue: 0x01)
        }
    }
    
    struct ReadRespone: SMBResponseBody {
        struct Header {
            let size: UInt16
            let offset: UInt8
            fileprivate let reserved: UInt8
            let length: UInt32
            let remaining: UInt32
            fileprivate let reserved2: UInt32
            
        }
        let header: ReadRespone.Header
        let buffer: Data
        
        init?(data: Data) {
            guard data.count > 16 else {
                return nil
            }
            self.header = data.scanValue()!
            let headersize = MemoryLayout<Header>.size
            self.buffer = data.subdata(in: headersize..<data.count)
        }
    }
    
    struct Channel: Option {
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        let rawValue: UInt32
        
        public static let NONE                   = Channel(rawValue: 0x00000000)
        public static let RDMA_V1                = Channel(rawValue: 0x00000001)
        public static let RDMA_V1_INVALIDATE     = Channel(rawValue: 0x00000002)
    }
    
    // MARK: SMB2 Write
    
    struct WriteRequest: SMBRequestBody {
        static var command: SMB2.Command = .WRITE
        
        let header: WriteRequest.Header
        let channelInfo: ChannelInfo?
        let fileData: Data
        
        struct Header {
            let size: UInt16
            let dataOffset: UInt16
            let length: UInt32
            let offset: UInt64
            let fileId: FileId
            let channel: Channel
            let remainingBytes: UInt32
            let channelInfoOffset: UInt16
            let channelInfoLength: UInt16
            let flags: WriteRequest.Flags
        }
        
        // codebeat:disable[ARITY]
        init(fileId: FileId, offset: UInt64, remainingBytes: UInt32 = 0, data: Data, channel: Channel = .NONE, channelInfo: ChannelInfo? = nil, flags: WriteRequest.Flags = []) {
            var channelInfoOffset: UInt16 = 0
            var channelInfoLength: UInt16 = 0
            if channel != .NONE, let _ = channelInfo {
                channelInfoOffset = UInt16(MemoryLayout<SMB2.Header>.size + MemoryLayout<WriteRequest.Header>.size)
                channelInfoLength = UInt16(MemoryLayout<SMB2.ChannelInfo>.size)
            }
            let dataOffset = UInt16(MemoryLayout<SMB2.Header>.size + MemoryLayout<WriteRequest.Header>.size) + channelInfoLength
            self.header = WriteRequest.Header(size: UInt16(49), dataOffset: dataOffset, length: UInt32(data.count), offset: offset, fileId: fileId, channel: channel, remainingBytes: remainingBytes, channelInfoOffset: channelInfoOffset, channelInfoLength: channelInfoLength, flags: flags)
            self.channelInfo = channelInfo
            self.fileData = data
        }
        // codebeat:enable[ARITY]
        
        func data() -> Data {
            var result = Data(value: self.header)
            if let channelInfo = channelInfo {
                result.append(channelInfo.data())
            }
            result.append(fileData)
            return result
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let THROUGH      = Flags(rawValue: 0x00000001)
            static let UNBUFFERED   = Flags(rawValue: 0x00000002)
        }
    }
    
    struct WriteResponse: SMBResponseBody {
        let size: UInt16
        fileprivate let reserved: UInt16
        let writtenBytes: UInt32
        fileprivate let remaining: UInt32
        fileprivate let channelInfoOffset: UInt16
        fileprivate let channelInfoLength: UInt16
    }
    
    struct ChannelInfo: SMBRequestBody {
        static var command: SMB2.Command = .WRITE
        
        let offset: UInt64
        let token: UInt32
        let length: UInt32
    }
    
    // MARK: SMB2 Lock
    
    struct LockElement: SMBRequestBody {
        static var command: SMB2.Command = .LOCK
        
        let offset: UInt64
        let length: UInt64
        let flags: LockElement.Flags
        fileprivate let reserved: UInt32
        
        struct Flags: OptionSet {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let SHARED_LOCK      = Flags(rawValue: 0x00000001)
            static let EXCLUSIVE_LOCK   = Flags(rawValue: 0x00000002)
            static let UNLOCK           = Flags(rawValue: 0x00000004)
            static let FAIL_IMMEDIATELY = Flags(rawValue: 0x00000010)
        }
    }
    
    struct LockRequest: SMBRequestBody {
        static var command: SMB2.Command = .LOCK
        
        let header: LockRequest.Header
        let locks: [LockElement]
        
        init(fileId: FileId,locks: [LockElement], lockSequenceNumber : Int8 = 0, lockSequenceIndex: UInt32 = 0) {
            self.header = LockRequest.Header(size: 48, lockCount: UInt16(locks.count), lockSequence: UInt32(lockSequenceNumber << 28) + lockSequenceIndex, fileId: fileId)
            self.locks = locks
        }
        
        func data() -> Data {
            var result = Data(value: header)
            for lock in locks {
                result.append(Data(value: lock))
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            fileprivate let lockCount: UInt16
            let lockSequence: UInt32
            let fileId : FileId
        }
    }
    
    struct LockResponse: SMBResponseBody {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
    }
    
    // MARK: SMB2 Cancel
    
    struct CancelRequest: SMBRequestBody {
        static var command: SMB2.Command = .CANCEL
        
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
    }
}
