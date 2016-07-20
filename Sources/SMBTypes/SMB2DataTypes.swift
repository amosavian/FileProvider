//
//  SMB2DataTypes.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

protocol SMBRequest {
    func data() -> NSData
}

protocol SMBResponse {
    init? (data: NSData)
}

protocol IOCtlRequestProtocol: SMBRequest {}
protocol IOCtlResponseProtocol: SMBResponse {}


struct SMBTime {
    var time: UInt64
    
    init(time: UInt64) {
        self.time = time
    }
    
    init(unixTime: UInt) {
        self.time = (UInt64(unixTime) + 11644473600) * 10000000
    }
    
    init(timeIntervalSince1970: NSTimeInterval) {
        self.time = UInt64((timeIntervalSince1970 + 11644473600) * 10000000)
    }
    
    init(date: NSDate) {
        self.init(timeIntervalSince1970: date.timeIntervalSince1970)
    }
    
    var unixTime: UInt {
        return UInt(self.time / 10000000 - 11644473600)
    }
    
    var date: NSDate {
        return NSDate(timeIntervalSince1970: Double(self.time) / 10000000 - 11644473600)
    }
}
