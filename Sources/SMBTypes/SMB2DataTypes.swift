//
//  SMB2DataTypes.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

protocol Option: RawRepresentable, Hashable {
    
}

extension Option where RawValue: Hashable {
    var hashValue: Int {
        return rawValue.hashValue
    }
}

extension Option where RawValue: Equatable {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

protocol SMBRequestBody {
    static var command: SMB2.Command { get }
    func data() -> Data
}

extension SMBRequestBody {
    var command: SMB2.Command {
        #if swift(>=3.1)
            return Swift.type(of: self).command
        #else
            return type(of: self).command
        #endif
    }
    
    func data() -> Data {
        return Data(value: self)
    }
}

protocol SMBResponseBody {
    init? (data: Data)
}

extension SMBResponseBody {
    init? (data: Data) {
        if let v: Self = data.scanValue() {
            self = v
        } else {
            return nil
        }
    }
}

typealias SMBRequest = (header: SMB2.Header, body: SMBRequestBody?)
typealias SMBResponse = (header: SMB2.Header, body: SMBResponseBody?)

protocol IOCtlRequestProtocol: SMBRequestBody {}
protocol IOCtlResponseProtocol: SMBResponseBody {}


struct SMBTime {
    var time: Int64
    
    init(time: Int64) {
        self.time = time
    }
    
    init(unixTime: UInt) {
        self.time = (Int64(unixTime) + 11644473600) * 10000000
    }
    
    init(timeIntervalSince1970: TimeInterval) {
        self.time = Int64((timeIntervalSince1970 + 11644473600) * 10000000)
    }
    
    init(date: Date) {
        self.init(timeIntervalSince1970: date.timeIntervalSince1970)
    }
    
    var unixTime: UInt {
        return UInt(self.time / 10000000 - 11644473600)
    }
    
    var date: Date {
        return Date(timeIntervalSince1970: Double(self.time) / 10000000 - 11644473600)
    }
}
