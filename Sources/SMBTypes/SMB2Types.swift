//
//  SMB2Types.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

protocol FileProviderSMBHeader {
    var protocolID: UInt32 { get }
    static var protocolConst: UInt32 { get }
}

// SMB2 Types
struct SMB2 {
    struct Header: FileProviderSMBHeader { // 64 bytes
        // header is always \u{fe}SMB
        let protocolID: UInt32
        static let protocolConst: UInt32 = 0x424d53fe
        let size: UInt16
        let creditCharge: UInt16
        // error messages from the server to the client
        let status: NTStatus
        enum StatusSeverity: UInt8 {
            case success = 0, information, warning, error
        }
        var statusDetails: (severity: StatusSeverity, customer: Bool, facility: UInt16, code: UInt16) {
            let severity = StatusSeverity(rawValue: UInt8(status.rawValue >> 30))!
            return (severity, status.rawValue & 0x20000000 != 0,
                      UInt16((status.rawValue & 0x0FFF0000) >> 16),
                       UInt16(status.rawValue & 0x0000FFFF))
        }
        let command: Command
        let creditRequestResponse: UInt16
        let flags: Flags
        var nextCommand: UInt32
        let messageId: UInt64
        fileprivate let reserved: UInt32
        let treeId: UInt32
        var asyncId: UInt64 {
            get {
                return UInt64(reserved) + (UInt64(treeId) << 32)
            }
        }
        let sessionId: UInt64
        let signature: (UInt64, UInt64)
        
        // codebeat:disable[ARITY]
        init(command: Command, status: NTStatus = .SUCCESS, creditCharge: UInt16 = 0, creditRequestResponse: UInt16, flags: Flags = [], nextCommand: UInt32 = 0, messageId: UInt64, treeId: UInt32, sessionId: UInt64, signature: (UInt64, UInt64) = (0, 0)) {
            self.protocolID = type(of: self).protocolConst
            self.size = 64
            self.status = status
            self.command = command
            self.creditCharge = creditCharge
            self.creditRequestResponse = creditRequestResponse
            self.flags = flags
            self.nextCommand = nextCommand
            self.messageId = messageId
            self.reserved = 0
            self.treeId = treeId
            self.sessionId = sessionId
            self.signature = signature
        }
        
        init(asyncCommand: Command, status: NTStatus = .SUCCESS, creditCharge: UInt16 = 0, creditRequestResponse: UInt16, flags: Flags = [.ASYNC_COMMAND], nextCommand: UInt32 = 0, messageId: UInt64, asyncId: UInt64, sessionId: UInt64, signature: (UInt64, UInt64) = (0, 0)) {
            self.protocolID = type(of: self).protocolConst
            self.size = 64
            self.status = status
            self.command = asyncCommand
            self.creditCharge = creditCharge
            self.creditRequestResponse = creditRequestResponse
            self.flags = flags.union([Flags.ASYNC_COMMAND])
            self.nextCommand = nextCommand
            self.messageId = messageId
            self.reserved = UInt32(asyncId & 0xffffffff)
            self.treeId = UInt32(asyncId >> 32)
            self.sessionId = sessionId
            self.signature = signature
        }
        // codebeat:enable[ARITY]
    }
    
    struct Flags: OptionSet {
        var rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        var priorityMask: UInt8 {
            get {
                return UInt8((rawValue & Flags.PRIORITY_MASK.rawValue)  >> 4)
            }
            set {
                rawValue = (rawValue & 0xffffff8f) | (UInt32(newValue & 0x7) << 4)
            }
        }
        
        static let SERVER_TO_REDIR       = Flags(rawValue: 0x00000001)
        static let ASYNC_COMMAND         = Flags(rawValue: 0x00000002)
        static let RELATED_OPERATIONS    = Flags(rawValue: 0x00000004)
        static let SIGNED                = Flags(rawValue: 0x00000008)
        fileprivate static let PRIORITY_MASK = Flags(rawValue: 0x00000070)
        static let DFS_OPERATIONS        = Flags(rawValue: 0x10000000)
        static let REPLAY_OPERATION      = Flags(rawValue: 0x20000000)
    }
    
    struct Command: Option {
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        
        let rawValue: UInt16
        
        public static let NEGOTIATE              = Command(rawValue: 0x0000)
        public static let SESSION_SETUP          = Command(rawValue: 0x0001)
        public static let LOGOFF                 = Command(rawValue: 0x0002)
        public static let TREE_CONNECT           = Command(rawValue: 0x0003)
        public static let TREE_DISCONNECT        = Command(rawValue: 0x0004)
        public static let CREATE                 = Command(rawValue: 0x0005)
        public static let CLOSE                  = Command(rawValue: 0x0006)
        public static let FLUSH                  = Command(rawValue: 0x0007)
        public static let READ                   = Command(rawValue: 0x0008)
        public static let WRITE                  = Command(rawValue: 0x0009)
        public static let LOCK                   = Command(rawValue: 0x000A)
        public static let IOCTL                  = Command(rawValue: 0x000B)
        public static let CANCEL                 = Command(rawValue: 0x000C)
        public static let ECHO                   = Command(rawValue: 0x000D)
        public static let QUERY_DIRECTORY        = Command(rawValue: 0x000E)
        public static let CHANGE_NOTIFY          = Command(rawValue: 0x000F)
        public static let QUERY_INFO             = Command(rawValue: 0x0010)
        public static let SET_INFO               = Command(rawValue: 0x0011)
        public static let OPLOCK_BREAK           = Command(rawValue: 0x0012)
        public static let INVALID                = Command(rawValue: 0xFFFF)
    }
    
    // MARK: SMB2 Oplock Break
    
    
}
