//
//  CIFSTypes.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

// codebeat:disable[TOO_MANY_IVARS]
// SMB/CIFS Types
struct SMB1 {
    struct Header { // 32 bytes
        // header is always \u{ff}SMB
        let protocolID: UInt32
        static let protocolConst: UInt32 = 0x424d53ff
        fileprivate var _command: UInt8
        var command: Command {
            get {
                return Command(rawValue: _command) ?? .INVALID
            }
            set {
                _command = newValue.rawValue
            }
        }
        // error messages from the server to the client
        fileprivate var _status: (UInt8, UInt8, UInt8, UInt8)
        var error: (Class: UInt8, code: UInt16) {
            get {
                return (_status.0, UInt16(_status.2) + (UInt16(_status.3) << 8))
            }
            set {
                _status = (newValue.Class, 0, UInt8(newValue.code & 0xff), UInt8(newValue.code >> 8))
            }
        }
        var ntStatus: UInt32 {
            get {
                let statusLo = UInt32(_status.0) + UInt32(_status.1) << 8
                let statusHi = UInt32(_status.2) + UInt32(_status.3) << 8
                return statusHi << 16 + statusLo
            }
            set {
                _status = (UInt8(newValue & 0xff), UInt8(newValue >> 8 & 0xff), UInt8(newValue >> 16 & 0xff), UInt8(newValue >> 24 & 0xff))
            }
        }
        var flags: Flags
        var flags2: Flags2
        var pidHigh: UInt16
        //  encryption key used for validating messages over connectionless transports
        fileprivate var _securityKey: (UInt16, UInt16)
        var securityKey: UInt32 {
            get {
                return UInt32(_securityKey.1) << 16 + UInt32(_securityKey.0)
            }
            set {
                _securityKey = (UInt16(newValue & 0xffff), UInt16(newValue >> 16))
            }
        }
        ///  Connection identifier
        var securityCID: UInt16
        ///  Identifier of the sequence of a message over connectionless transports
        var securitySequenceNumber: UInt16
        fileprivate var ununsed: UInt16
        var treeId: UInt16
        var pidLow: UInt16
        var userId: UInt16
        var multiplexId: UInt16
        var pid: UInt32 {
            get {
                return UInt32(pidLow) + UInt32(pidHigh) << 16
            }
            set {
                pidLow = UInt16(newValue & 0xffff)
                pidHigh = UInt16(newValue >> 16)
            }
        }
        
        // codebeat:disable[ARITY]
        init(command: Command, treeId: UInt16, pid: UInt32, userId: UInt16, multiplexId: UInt16, flags: Flags, flags2: Flags2 = [.LONG_NAMES, .ERR_STATUS, .UNICODE], ntStatus: UInt32 = 0, securityKey: UInt32 = 0, securityCID: UInt16 = 0, securitySequenceNumber: UInt16 = 0) {
            self.protocolID = Header.protocolConst
            self._command = command.rawValue
            _status = (UInt8(ntStatus & 0xff), UInt8(ntStatus >> 8 & 0xff), UInt8(ntStatus >> 16 & 0xff), UInt8(ntStatus >> 24 & 0xff))
            self.flags = flags
            self.flags2 = flags2
            self._securityKey = (UInt16(securityKey & 0xffff), UInt16(securityKey >> 16))
            self.securityCID = securityCID
            self.securitySequenceNumber = securitySequenceNumber
            self.ununsed = 0
            self.treeId = treeId
            self.pidLow = UInt16(pid & 0xffff)
            self.pidHigh = UInt16(pid >> 16)
            self.userId = userId
            self.multiplexId = multiplexId
        }
        // codebeat:enable[ARITY]
    }
    
    struct Flags: OptionSet {
        let rawValue: UInt8
        
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        /** This bit is set (1) in the NEGOTIATE (0x72) Response if the server supports
         * LOCK_AND_READ (0x13) and WRITE_AND_UNLOCK (0x14) commands. */
        static let LOCK_AND_READ_OK       = Flags(rawValue: 0x01)
        static let BUF_AVAIL              = Flags(rawValue: 0x02)
        static let CASE_INSENSITIVE       = Flags(rawValue: 0x08)
        static let CANONICALIZED_PATHS    = Flags(rawValue: 0x10)
        static let OPLOCK                 = Flags(rawValue: 0x20)
        static let OPBATCH                = Flags(rawValue: 0x40)
        /**  When on, this message is being sent from the server in response to a client request. */
        static let REPLY                  = Flags(rawValue: 0x80)
    }
    
    struct Flags2: OptionSet {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        /** Client: the message MAY contain long file names. */
        static let LONG_NAMES             = Flags2(rawValue: 0x0001)
        /** Client: the client is aware of extended attributes (EAs). */
        static let EAS                    = Flags2(rawValue: 0x0002)
        /** Client: the client is requesting signing (if signing is not yet active) or the message
         * being sent is signed. This bit is used on the SMB header of an SESSION_SETUP_ANDX */
        static let SMB_SECURITY_SIGNATURE = Flags2(rawValue: 0x0004)
        ///  Reserved but not implemented.
        static let IS_LONG_NAME           = Flags2(rawValue: 0x0040)
        /** client aware of Extended Security negotiation */
        static let EXT_SEC                = Flags2(rawValue:  0x0800)
        /** any pathnames in this SMB SHOULD be resolved in the Distributed File System (DFS) */
        static let DFS                    = Flags2(rawValue: 0x1000)
        /**
         * This flag is useful only on a read request. If the bit is set, then the client MAY read
         * the file if the client does not have read permission but does have execute permission. */
        static let PAGING_IO              = Flags2(rawValue:  0x2000) // READ_IF_EXECUTE
        /**
         * Client: the server MUST return errors as 32-bit NTSTATUS codes in the response
         * Server: the Status field in the header is formatted as an NTSTATUS cod */
        static let ERR_STATUS             = Flags2(rawValue: 0x4000)
        /**
         * Each field that contains a string in this SMB message MUST be encoded
         * as an array of 16-bit Unicode characters */
        static let UNICODE                = Flags2(rawValue: 0x8000)
    }
    
    enum Command: UInt8 {
        case CREATE_DIRECTORY       = 0x00
        case DELETE_DIRECTORY       = 0x01
        case OPEN                   = 0x02
        case CREATE                 = 0x03
        case CLOSE                  = 0x04
        case FLUSH                  = 0x05
        case DELETE                 = 0x06
        case RENAME                 = 0x07
        case QUERY_INFORMATION      = 0x08
        case SET_INFORMATION        = 0x09
        case READ                   = 0x0A
        case WRITE                  = 0x0B
        case LOCK_BYTE_RANGE        = 0x0C
        case UNLOCK_BYTE_RANGE      = 0x0D
        case CREATE_TEMPORARY       = 0x0E
        case CREATE_NEW             = 0x0F
        case CHECK_DIRECTORY        = 0x10
        case PROCESS_EXIT           = 0x11
        case SEEK                   = 0x12
        case LOCK_AND_READ          = 0x13
        case WRITE_AND_UNLOCK       = 0x14
        case READ_RAW               = 0x1A
        case READ_MPX               = 0x1B
        case READ_MPX_SECONDARY     = 0x1C
        case WRITE_RAW              = 0x1D
        case WRITE_MPX              = 0x1E
        case WRITE_COMPLETE         = 0x20
        case SET_INFORMATION2       = 0x22
        case QUERY_INFORMATION2     = 0x23
        case LOCKING_ANDX           = 0x24
        case TRANSACTION            = 0x25
        case TRANSACTION_SECONDARY  = 0x26
        case IOCTL                  = 0x27
        case IOCTL_SECONDARY        = 0x28
        case COPY                   = 0x29
        case MOVE                   = 0x2A
        case ECHO                   = 0x2B
        case WRITE_AND_CLOSE        = 0x2C
        case OPEN_ANDX              = 0x2D
        case READ_ANDX              = 0x2E
        case WRITE_ANDX             = 0x2F
        case CLOSE_AND_TREE_DISC    = 0x31
        case TRANSACTION2           = 0x32
        case TRANSACTION2_SECONDARY = 0x33
        case FIND_CLOSE2            = 0x34
        case FIND_NOTIFY_CLOSE      = 0x35
        case TREE_CONNECT           = 0x70
        case TREE_DISCONNECT        = 0x71
        case NEGOTIATE              = 0x72
        case SESSION_SETUP_ANDX     = 0x73
        case LOGOFF_ANDX            = 0x74
        case TREE_CONNECT_ANDX      = 0x75
        case QUERY_INFORMATION_DISK = 0x80
        case SEARCH                 = 0x81
        case FIND                   = 0x82
        case FIND_UNIQUE            = 0x83
        case NT_TRANSACT            = 0xA0
        case NT_TRANSACT_SECONDARY  = 0xA1
        case NT_CREATE_ANDX         = 0xA2
        case NT_CANCEL              = 0xA4
        case OPEN_PRINT_FILE        = 0xC0
        case WRITE_PRINT_FILE       = 0xC1
        case CLOSE_PRINT_FILE       = 0xC2
        case GET_PRINT_QUEUE        = 0xC3
        case READ_BULK              = 0xD8
        case WRITE_BULK             = 0xD9
        case WRITE_BULK_DATA        = 0xDA
        case INVALID                = 0xFE
    }
}
// codebeat:enable[TOO_MANY_IVARS]
