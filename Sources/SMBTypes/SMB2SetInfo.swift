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