//
//  SMB2SetInfo.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/31/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

extension SMB2 {
    // MARK: SMB2 Set Info
    struct SetInfoRequest: SMBRequest {
        let header: Header
        let buffer: NSData?
        
        
        
        func data() -> NSData {
            return NSData()
        }
        
        struct Header {
            let size: UInt16 = 33
            let infoType: UInt8
            private let infoClass: UInt8
            let bufferLength: UInt32
            let bufferOffset: UInt16
            private let reserved: UInt16
            let securityInfo: FileSecurityInfo
            let fileId: FileId
        }
    }
    
    struct SetInfoResponse: SMBResponse {
        let size: UInt16
        
        init() {
            self.size = 2
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
    }
}