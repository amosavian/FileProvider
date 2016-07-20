//
//  SMB2Types.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

// SMB2 Types
struct SMB2 {
    struct Header: FileProviderSMBHeader { // 64 bytes
        // header is always \u{fe}SMB
        let protocolID: UInt32
        static let protocolConst: UInt32 = 0x424d53fe
        let size: UInt16
        let creditCharge: UInt16
        // error messages from the server to the client
        let status: UInt32
        enum StatusSeverity: UInt8 {
            case Success = 0, Information, Warning, Error
        }
        var statusDetails: (severity: StatusSeverity, customer: Bool, facility: UInt16, code: UInt16) {
            let severity = StatusSeverity(rawValue: UInt8(status >> 30))!
            return (severity, status & 0x20000000 != 0, UInt16((status & 0x0FFF0000) >> 16), UInt16(status & 0x0000FFFF))
        }
        private let _command: UInt16
        var command: Command {
            get {
                return Command(rawValue: _command) ?? .INVALID
            }
        }
        let creditRequestResponse: UInt16
        let flags: Flags
        var nextCommand: UInt32
        let messageId: UInt64
        private let reserved: UInt32
        let treeId: UInt32
        var asyncId: UInt64 {
            get {
                return UInt64(reserved) + (UInt64(treeId) << 32)
            }
        }
        let sessionId: UInt64
        let signature: (UInt64, UInt64)
        
        init(command: Command, status: NTStatus = .SUCCESS, creditCharge: UInt16 = 0, creditRequestResponse: UInt16, flags: Flags = [], nextCommand: UInt32 = 0, messageId: UInt64, treeId: UInt32, sessionId: UInt64, signature: (UInt64, UInt64) = (0, 0)) {
            self.protocolID = self.dynamicType.protocolConst
            self.size = 64
            self.status = status.rawValue
            self._command = command.rawValue
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
            self.protocolID = self.dynamicType.protocolConst
            self.size = 64
            self.status = status.rawValue
            self._command = asyncCommand.rawValue
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
    }
    
    struct Flags: OptionSetType {
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
        private static let PRIORITY_MASK = Flags(rawValue: 0x00000070)
        static let DFS_OPERATIONS        = Flags(rawValue: 0x10000000)
        static let REPLAY_OPERATION      = Flags(rawValue: 0x20000000)
    }
    
    enum Command: UInt16 {
        case NEGOTIATE              = 0x0000
        case SESSION_SETUP          = 0x0001
        case LOGOFF                 = 0x0002
        case TREE_CONNECT           = 0x0003
        case TREE_DISCONNECT        = 0x0004
        case CREATE                 = 0x0005
        case CLOSE                  = 0x0006
        case FLUSH                  = 0x0007
        case READ                   = 0x0008
        case WRITE                  = 0x0009
        case LOCK                   = 0x000A
        case IOCTL                  = 0x000B
        case CANCEL                 = 0x000C
        case ECHO                   = 0x000D
        case QUERY_DIRECTORY        = 0x000E
        case CHANGE_NOTIFY          = 0x000F
        case QUERY_INFO             = 0x0010
        case SET_INFO               = 0x0011
        case OPLOCK_BREAK           = 0x0012
        case INVALID                = 0xFFFF
    }
    
    // MARK: SMB2 Oplock Break
    
}
