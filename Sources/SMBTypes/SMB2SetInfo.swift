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
    struct SetInfoRequest: SMBRequestBody {
        static var command: SMB2.Command = .SET_INFO
        
        let header: Header
        let buffer: Data?
        
        func data() -> Data {
            var result = Data(value: header)
            result.append(buffer ?? Data())
            return result 
        }
        
        struct Header {
            let size: UInt16 = 33
            let infoType: UInt8
            fileprivate let infoClass: UInt8
            let bufferLength: UInt32
            let bufferOffset: UInt16
            fileprivate let reserved: UInt16
            let securityInfo: FileSecurityInfo
            let fileId: FileId
        }
    }
    
    struct SetInfoResponse: SMBResponseBody {
        let size: UInt16
        
        init() {
            self.size = 2
        }
    }
}
