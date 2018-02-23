//
//  SMB2IOCtl.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

extension SMB2 {
    // MARK: SMB2 IOCTL
    
    /**
     * IOCtl usage is usually limited in SMB to pipe requests and duplicating file inside server
     */
    
    struct IOCtlRequest: SMBRequestBody {
        static var command: SMB2.Command = .IOCTL
        
        let header: Header
        let requestData:  IOCtlRequestProtocol?
        
        init(fileId: FileId ,ctlCode: IOCtlCode, requestData: IOCtlRequestProtocol?, flags: IOCtlRequest.Flags = []) {
            let offset = requestData != nil ? UInt32(MemoryLayout<SMB2.Header>.size + MemoryLayout<IOCtlRequest.Header>.size) : 0
            self.header = Header(size: 57, reserved: 0, ctlCode: ctlCode, fileId: fileId, inputOffset: offset, inputCount: UInt32((requestData?.data().count ?? 0)), maxInputResponse: 0, outputOffset: offset, outputCount: 0, maxOutputResponse: UInt32(Int32.max), flags: flags, reserved2: 0)
            self.requestData = requestData
        }
        
        func data() -> Data {
            var result = Data(value: self.header)
            if let reqData = requestData?.data() {
                result.append(reqData)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            fileprivate let reserved: UInt16
            let ctlCode: IOCtlCode
            let fileId: FileId
            let inputOffset: UInt32
            let inputCount: UInt32
            let maxInputResponse: UInt32
            let outputOffset: UInt32
            let outputCount: UInt32
            let maxOutputResponse: UInt32
            let flags: IOCtlRequest.Flags
            fileprivate let reserved2: UInt32
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let IOCTL = Flags(rawValue: 0x00000000)
            static let FSCTL = Flags(rawValue: 0x00000001)
        }
    }
    
    struct IOCtlResponse: SMBResponseBody {
        let header: Header
        let responseData:  IOCtlResponseProtocol?
        
        init?(data: Data) {
            self.header = data.scanValue()!
            let endRange = Int(self.header.outputOffset - 64) + Int(self.header.outputCount)
            let response = data.subdata(in: Int(self.header.outputOffset - 64)..<endRange)
            switch self.header.ctlCode {
            case .SRV_COPYCHUNK, .SRV_COPYCHUNK_WRITE:
                self.responseData = IOCtlResponseData.SrvCopyChunk(data: response)
            case .SRV_ENUMERATE_SNAPSHOTS:
                self.responseData = IOCtlResponseData.SrvSnapshots(data: response)
            case .SRV_REQUEST_RESUME_KEY:
                self.responseData = IOCtlResponseData.ResumeKey(data: response)
            case .SRV_READ_HASH:
                self.responseData = IOCtlResponseData.ReadHash(data: response)
            case .QUERY_NETWORK_INTERFACE_INFO:
                self.responseData = IOCtlResponseData.NetworkInterfaceInfo(data: response)
            case .VALIDATE_NEGOTIATE_INFO:
                self.responseData = IOCtlResponseData.ValidateNegotiateInfo(data: response)
            default:
                self.responseData = nil
            }
        }
        
        struct Header {
            let size: UInt16
            fileprivate let reserved: UInt16
            let ctlCode: IOCtlCode
            let fileId: FileId
            let inputOffset: UInt32
            let inputCount: UInt32
            let outputOffset: UInt32
            let outputCount: UInt32
            fileprivate let flags: UInt32
            fileprivate let reserved2: UInt32
        }
    }
    
    struct IOCtlCode: Option {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        public static let DFS_GET_REFERRALS              = IOCtlCode(rawValue: 0x00060194)
        public static let DFS_GET_REFERRALS_EX           = IOCtlCode(rawValue: 0x000601B0)
        public static let SET_REPARSE_POINT              = IOCtlCode(rawValue: 0x000900A4)
        public static let FILE_LEVEL_TRIM                = IOCtlCode(rawValue: 0x00098208)
        public static let PIPE_PEEK                      = IOCtlCode(rawValue: 0x0011400C)
        public static let PIPE_WAIT                      = IOCtlCode(rawValue: 0x00110018)
        /// PIPE_TRANSCEIVE is valid only on a named pipe with mode set to FILE_PIPE_MESSAGE_MODE.
        public static let PIPE_TRANSCEIVE                = IOCtlCode(rawValue: 0x0011C017)
        /// Get ResumeKey used by the client to uniquely identify the source file in an FSCTL_SRV_COPYCHUNK or FSCTL_SRV_COPYCHUNK_WRITE request.
        public static let SRV_REQUEST_RESUME_KEY         = IOCtlCode(rawValue: 0x00140078)
        /// Get all the revision time-stamps that are associated with the Tree Connect share in which the open resides
        public static let SRV_ENUMERATE_SNAPSHOTS        = IOCtlCode(rawValue: 0x00144064)
        /// Reads a chunk of file for performing server side copy operations.
        public static let SRV_COPYCHUNK                  = IOCtlCode(rawValue: 0x001440F2)
        /// Retrieve data from the Content Information File associated with a specified file, not valid for the SMB 2.0.2 dialect.
        public static let SRV_READ_HASH                  = IOCtlCode(rawValue: 0x001441BB)
        /// Writes the chunk of file for performing server side copy operations.
        public static let SRV_COPYCHUNK_WRITE            = IOCtlCode(rawValue: 0x001480F2)
        /// Request resiliency for a specified open file, not valid for the SMB 2.0.2 dialect.
        public static let LMR_REQUEST_RESILIENCY         = IOCtlCode(rawValue: 0x001401D4)
        /// Get server network interface info e.g. link speed and socket address information
        public static let QUERY_NETWORK_INTERFACE_INFO   = IOCtlCode(rawValue: 0x001401FC)
        /// Request validation of a previous SMB 2 NEGOTIATE, valid for SMB 3.0 and SMB 3.0.2 dialects.
        public static let VALIDATE_NEGOTIATE_INFO        = IOCtlCode(rawValue: 0x00140204)
    }
    
    struct IOCtlRequestData {
        struct CopyChunk: IOCtlRequestProtocol {
            static var command: SMB2.Command = .IOCTL
            
            let sourceKey: (UInt64, UInt64, UInt64)
            let chunkCount: UInt32
            let chunks: [Chunk]
            
            func data() -> Data {
                var result = Data(value: sourceKey)
                result.append(Data(value: chunkCount))
                let reserved: UInt32 = 0
                result.append(Data(value: reserved))
                return Data()
            }
            
            struct Chunk {
                let sourceOffset: UInt64
                let targetOffset: UInt64
                let length: UInt32
                fileprivate let reserved: UInt32
            }
        }
        
        struct ReadHash: IOCtlRequestProtocol {
            static var command: SMB2.Command = .IOCTL
            
            let _hashType: IOCtlHashType
            let _hashVersion: IOCtlHashVersion
            let _hashRetrievalType: IOCtlHashRetrievalType
            let length: UInt32
            let offset: UInt64
            
            init(offset: UInt64, length: UInt32, hashType: IOCtlHashType = .PEER_DIST, hashVersion: IOCtlHashVersion = .VER_1, hashRetrievalType: IOCtlHashRetrievalType = .FILE_BASED) {
                self._hashType = hashType
                self._hashVersion = hashVersion
                self._hashRetrievalType = hashRetrievalType
                self.length = length
                self.offset = offset
            }
        }
        
        struct ResilencyRequest: IOCtlRequestProtocol {
            static var command: SMB2.Command = .IOCTL
            
            let timeout: UInt32
            fileprivate let reserved: UInt32
            
            /// The requested time the server holds the file open after a disconnect before releasing it. This time is in milliseconds.
            init(timeout: UInt32) {
                self.timeout = timeout
                self.reserved = 0
            }
        }
        
        struct ValidateNegotiateInfo: IOCtlRequestProtocol {
            static var command: SMB2.Command = .IOCTL
            
            let header: ValidateNegotiateInfo.Header
            let dialects: [UInt16]
            
            init(dialects: [UInt16], guid: uuid_t, capabilities: IOCtlCapabilities, securityMode: UInt16) {
                self.header = Header(capabilities: capabilities, guid: guid, securityMode: securityMode, dialectCount: UInt16(dialects.count))
                self.dialects = dialects
            }
            
            func data() -> Data {
                var result = Data(value: self.header)
                dialects.forEach { result.append(Data(value: $0)) }
                return result
            }
            
            struct Header {
                let capabilities: IOCtlCapabilities
                /// Client's GUID
                let guid: uuid_t
                let securityMode: UInt16
                let dialectCount: UInt16
            }
        }
    }
    
    struct IOCtlResponseData {
        // SRV_COPYCHUNK, SRV_COPYCHUNK_WRITE
        struct SrvCopyChunk: IOCtlResponseProtocol {
            let chunksCount: UInt32
            let chunksBytesWritten: UInt32
            let totalBytesWriiten: UInt32
        }
        
        // SRV_ENUMERATE_SNAPSHOTS
        struct SrvSnapshots: IOCtlResponseProtocol {
            let count: UInt32
            let returnedCount: UInt32
            let snapshots: [SMBTime]
            
            init?(data: Data) {
                guard data.count > 8 else { return nil }
                self.count = data.scanValue()!
                self.returnedCount = data.scanValue(start: 4)!
                //let size: UInt32 = decode(data.subdataWithRange(NSRange(location: 8, length: 4)))
                var snapshots = [SMBTime]()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "'@GMT-'yyyy'.'MM'.'dd'-'HH'.'mm'.'ss"
                for i in 0..<Int(returnedCount) {
                    let offset = 24 + i * 48
                    if data.count < offset + 48 {
                        return nil
                    }
                    let datestring = data.scanString(start: offset, length: 48, using: .utf16)
                    if let datestring = datestring, let date = dateFormatter.date(from: datestring) {
                        snapshots.append(SMBTime(date: date))
                    }
                }
                self.snapshots = snapshots
            }
        }
        
        struct ResumeKey: IOCtlResponseProtocol {
            let key: (UInt64, UInt64, UInt64)
            fileprivate let contextLength: UInt32
            fileprivate let context: UInt32
        }
        
        struct ReadHash: IOCtlResponseProtocol {
            // TODO: Implement IOCTL READ_HASH
        }
        
        struct NetworkInterfaceInfo: IOCtlResponseProtocol {
            let items: [NetworkInterfaceInfo.Item]
            
            init?(data: Data) {
                var items = [Item]()
                var offset = 0
                while let item: Item = data.scanValue(start: offset) {
                    items.append(item)
                    offset += MemoryLayout<Item>.size
                }
                self.items = items
            }
            
            struct Item {
                /// The offset, in bytes, from the beginning of this structure to the beginning of a subsequent 8-byte aligned network interface.
                let next: UInt32
                /// specifies the network interface index.
                let ifIndex: UInt32
                let capability: IOCtlCapabilities
                fileprivate let reserved: UInt32
                /// Speed of the network interface in bits per second
                let linkSpeed: UInt64
                fileprivate let sockaddrStorage:
                (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
                var family: sa_family_t {
                    return sockaddrStorage.1
                }
                
                static let ipv4: sa_family_t = 0x02
                static let ipv6: sa_family_t = 0x17
                
                var sockaddr: sockaddr_in {
                    return Data.mapMemory(from: self.sockaddrStorage)!
                }
                
                var sockaddr6: sockaddr_in6 {
                     return Data.mapMemory(from: self.sockaddrStorage)!
                }
            }
        }
        
        struct ValidateNegotiateInfo: IOCtlResponseProtocol {
            let capabilities: IOCtlCapabilities
            let guid: uuid_t
            let securityMode: UInt16
            fileprivate let _dialect: UInt16
            var dialect: (major: Int, minor: Int) {
                return (major: Int(_dialect & 0xFF), minor: Int(_dialect >> 8))
            }
        }
    }
    
    struct IOCtlCapabilities: OptionSet {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static let RSS_CAPABLE  = IOCtlCapabilities(rawValue: 0x00000001)
        static let RDMA_CAPABLE = IOCtlCapabilities(rawValue: 0x00000002)
    }
    
    struct IOCtlHashType: Option {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        public static let PEER_DIST = IOCtlHashType(rawValue: 0x00000001)
    }
    
    struct IOCtlHashVersion: Option {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        public static let VER_1 = IOCtlHashVersion(rawValue: 0x00000001)
        public static let VER_2 = IOCtlHashVersion(rawValue: 0x00000002)
    }
    
    struct IOCtlHashRetrievalType: Option {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        public static let HASH_BASED = IOCtlHashRetrievalType(rawValue: 0x00000001)
        public static let FILE_BASED = IOCtlHashRetrievalType(rawValue: 0x00000002)
    }
}
