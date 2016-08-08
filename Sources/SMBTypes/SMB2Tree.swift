//
//  SMB2Tree.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

extension SMB2 {
    // MARK: SMB2 Tree Connect
    
    struct TreeConnectRequest: SMBRequest {
        let header: TreeConnectRequest.Header
        let buffer: NSData?
        var path: String {
            return ""
        }
        var share: String {
            return ""
        }
        
        init? (header: TreeConnectRequest.Header, host: String, share: String) {
            guard !host.containsString("/") && !host.containsString("/") && !share.containsString("/") && !share.containsString("/") else {
                return nil
            }
            self.header = header
            let path = "\\\\\(host)\\\(share)"
            self.buffer = path.dataUsingEncoding(NSUTF16StringEncoding)
        }
        
        func data() -> NSData {
            var header = self.header
            header.pathOffset = UInt16(sizeof(SMB2.Header.self) + sizeof(TreeConnectRequest.Header.self))
            header.pathLength = UInt16(buffer?.length ?? 0)
            let result = NSMutableData(data: encode(&header))
            if let buffer = self.buffer {
                result.appendData(buffer)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            let flags: TreeConnectRequest.Flags
            var pathOffset: UInt16
            var pathLength: UInt16
            
            init(flags: TreeConnectRequest.Flags) {
                self.size = 9
                self.flags = flags
                self.pathOffset = 0
                self.pathLength = 0
            }
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt16
            
            init(rawValue: UInt16) {
                self.rawValue = rawValue
            }
            
            static let SHAREFLAG_CLUSTER_RECONNECT = Flags(rawValue: 0x0001)
        }
    }
    
    struct TreeConnectResponse: SMBResponse {
        let size: UInt16  // = 16
        private let _type: UInt8
        var type: ShareType {
            return ShareType(rawValue: _type) ?? .UNKNOWN
        }
        private let reserved: UInt8
        let flags: TreeConnectResponse.ShareFlags
        let capabilities: TreeConnectResponse.Capabilities
        let maximalAccess: FileAccessMask
        
        init? (data: NSData) {
            if data.length != 16 {
                return nil
            }
            self = decode(data)
        }
        
        enum ShareType: UInt8 {
            case UNKNOWN  = 0x00
            case DISK     = 0x01
            case PIPE     = 0x02
            case PRINT    = 0x03
        }
        
        struct ShareFlags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let DFS                          = ShareFlags(rawValue: 0x00000001)
            static let DFS_ROOT                     = ShareFlags(rawValue: 0x00000002)
            static let MANUAL_CACHING               = ShareFlags(rawValue: 0x00000000)
            static let AUTO_CACHING                 = ShareFlags(rawValue: 0x00000010)
            static let VDO_CACHING                  = ShareFlags(rawValue: 0x00000020)
            static let NO_CACHING                   = ShareFlags(rawValue: 0x00000030)
            static let RESTRICT_EXCLUSIVE_OPENS     = ShareFlags(rawValue: 0x00000100)
            static let FORCE_SHARED_DELETE          = ShareFlags(rawValue: 0x00000200)
            static let ALLOW_NAMESPACE_CACHING      = ShareFlags(rawValue: 0x00000400)
            static let ACCESS_BASED_DIRECTORY_ENUM  = ShareFlags(rawValue: 0x00000800)
            static let FORCE_LEVELII_OPLOCK         = ShareFlags(rawValue: 0x00001000)
            static let ENABLE_HASH_V1               = ShareFlags(rawValue: 0x00002000)
            static let ENABLE_HASH_V2               = ShareFlags(rawValue: 0x00004000)
            static let ENCRYPT_DATA                 = ShareFlags(rawValue: 0x00008000)
        }
        
        struct Capabilities: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let DFS                      = Capabilities(rawValue: 0x00000008)
            static let CONTINUOUS_AVAILABILITY  = Capabilities(rawValue: 0x00000010)
            static let SCALEOUT                 = Capabilities(rawValue: 0x00000020)
            static let CLUSTER                  = Capabilities(rawValue: 0x00000040)
            static let ASYMMETRIC               = Capabilities(rawValue: 0x00000080)
        }
    }
    
    // MARK: SMB2 Tree Disconnect
    
    struct TreeDisconnect: SMBRequest, SMBResponse {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
}