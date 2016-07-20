//
//  SMBTransmitter.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

protocol SMBRequest {
    func data() -> NSData
}

protocol SMBResponse {
    init? (data: NSData)
}

internal func encode<T>(inout value: T) -> NSData {
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}

internal func encode<T>(value: T) -> NSData {
    var value = value
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}

internal func decode<T>(data: NSData) -> T {
    let pointer = UnsafeMutablePointer<T>.alloc(sizeof(T.Type))
    data.getBytes(pointer, length: sizeof(T.Type))
    
    return pointer.move()
}

// This client implementation is for little-endian platform, namely x86, x64 & arm
// For big-endian platforms like PowerPC, there must be a huge overhaul

class SMBProtocolClient: TCPSocketClient {
    var currentMessageID: UInt64 = 0
    
    func negotiateToSMB2() -> SMB2.NegotiateResponse? {
        let smbHeader = SMB2.Header(command: .NEGOTIATE, creditRequestResponse: 126, messageId: messageId(), treeId: 0, sessionId: 0)
        currentMessageID += 1
        let negMessage = SMB2.NegotiateRequest(request: SMB2.NegotiateRequest.Header(capabilities: []))
        SMBProtocolClient.createSMB2Message(smbHeader, message: negMessage)
        do {
            try self.send(data: nil)
        } catch _ {
            return nil
        }
        self.waitUntilResponse()
        let response = try? SMBProtocolClient.digestSMB2Message(dataReceived)
        return response??.message as? SMB2.NegotiateResponse
    }
    
    func sessionSetupForSMB2() -> SMB2.SessionSetupResponse? {
        return nil
    }
    
    func messageId() -> UInt64 {
        defer {
            currentMessageID += 1
        }
        return currentMessageID
    }
    
    // MARK: create and analyse messages
    
    class func determineSMBVersion(data: NSData) -> Float {
        var smbverChar: Int8 = 0
        data.getBytes(&smbverChar, length: 1)
        let version = 0 - smbverChar
        return Float(version)
    }
    
    class func digestSMBMessage(data: NSData) throws -> (header: SMB1.Header, blocks: [(params: [UInt16], message: NSData?)]) {
        guard data.length > 30 else {
            throw NSURLError.BadServerResponse
        }
        var buffer = [UInt8](count: data.length, repeatedValue: 0)
        guard determineSMBVersion(data) == 1 else {
            throw SMBFileProviderError.IncompatibleHeader
        }
        let headersize = sizeof(SMB1.Header.self)
        let header: SMB1.Header = decode(data)
        var blocks = [(params: [UInt16], message: NSData?)]()
        var offset = headersize
        while offset < data.length {
            let paramWords: [UInt16]
            let paramWordsCount = Int(buffer[offset])
            guard data.length > (paramWordsCount * 2 + offset) else {
                throw SMBFileProviderError.IncorrectParamsLength
            }
            offset += sizeof(UInt8)
            var rawParamWords = [UInt8](buffer[offset..<(offset + paramWordsCount * 2)])
            let paramData = NSData(bytesNoCopy: &rawParamWords, length: rawParamWords.count)
            paramWords = decode(paramData)
            offset += paramWordsCount * 2
            let messageBytesCountLittleEndian = [UInt8](buffer[offset...(offset + 1)])
            let messageBytesCount = Int(UnsafePointer<UInt16>(messageBytesCountLittleEndian).memory)
            offset += sizeof(UInt16)
            guard data.length >= (offset + messageBytesCount) else {
                throw SMBFileProviderError.IncorrectMessageLength
            }
            var rawMessage = [UInt8](buffer[offset..<(offset + messageBytesCount)])
            offset += messageBytesCount
            let message = NSData(bytes: &rawMessage, length: rawMessage.count)
            blocks.append((params: paramWords, message: message))
        }
        return (header, blocks)
    }
    
    class func digestSMB2Message(data: NSData) throws -> (header: SMB2.Header, message: SMBResponse?)? {
        guard data.length > 65 else {
            throw NSURLError.BadServerResponse
        }
        guard determineSMBVersion(data) == 2 else {
            throw SMBFileProviderError.IncompatibleHeader
        }
        let headersize = sizeof(SMB2.Header.self)
        let headerData = data.subdataWithRange(NSRange(location: 0, length: headersize))
        let messageSize = data.length - headersize
        let messageData = data.subdataWithRange(NSRange(location: headersize, length: messageSize))
        let header: SMB2.Header = decode(headerData)
        switch header.command {
        case .NEGOTIATE:
            return (header, SMB2.NegotiateResponse(data: messageData))
        case .SESSION_SETUP:
            return (header, SMB2.SessionSetupResponse(data: messageData))
        case .LOGOFF:
            return (header, SMB2.LogOff(data: messageData))
        case .TREE_CONNECT:
            return (header, SMB2.TreeConnectResponse(data: messageData))
        case .TREE_DISCONNECT:
            return (header, SMB2.TreeDisconnect(data: messageData))
        case .CREATE:
            return (header, SMB2.CreateResponse(data: messageData))
        case .CLOSE:
            return (header, SMB2.CloseResponse(data: messageData))
        case .FLUSH:
            return (header, SMB2.FlushResponse(data: messageData))
        case .READ:
            return (header, nil) // FIXME:
        case .WRITE:
            return (header, nil) // FIXME:
        case .LOCK:
            return (header, nil) // FIXME:
        case .IOCTL:
            return (header, nil)
        case .CANCEL:
            return (header, nil)
        case .ECHO:
            return (header, SMB2.Echo(data: messageData))
        case .QUERY_DIRECTORY:
            return (header, nil) // FIXME:
        case .CHANGE_NOTIFY:
            return (header, nil) // FIXME:
        case .QUERY_INFO:
            return (header, nil) // FIXME:
        case .SET_INFO:
            return (header, nil) // FIXME:
        case .OPLOCK_BREAK:
            return (header, nil) // FIXME:
        case .INVALID:
            throw SMBFileProviderError.InvalidCommand
        }
    }
    
    class func createSMBMessage(header: SMB1.Header, blocks: [(params: NSData?, message: NSData?)]) -> NSData {
        var headerv = header
        let result = NSMutableData(data: encode(&headerv))
        for block in blocks {
            var paramWordsCount = UInt8(block.params?.length ?? 0)
            result.appendBytes(&paramWordsCount, length: sizeofValue(paramWordsCount))
            if let params = block.params {
                result.appendData(params)
            }
            var messageLen = UInt16(block.message?.length ?? 0)
            result.appendBytes(&messageLen, length: sizeofValue(messageLen))
            if let message = block.message {
                result.appendData(message)
            }
        }
        return result
    }
    
    class func createSMB2Message(header: SMB2.Header, message: SMBRequest) -> NSData {
        var headerv = header
        let result = NSMutableData(data: encode(&headerv))
        result.appendData(message.data())
        return result
    }
}

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

protocol FileProviderSMBHeader {
    var protocolID: UInt32 { get }
    static var protocolConst: UInt32 { get }
}

// SMB/CIFS Types
struct SMB1 {
    struct Header { // 32 bytes
        // header is always \u{ff}SMB
        let protocolID: UInt32
        static let protocolConst: UInt32 = 0x424d53ff
        private var _command: UInt8
        var command: Command {
            get {
                return Command(rawValue: _command) ?? .INVALID
            }
            set {
                _command = newValue.rawValue
            }
        }
        // error messages from the server to the client
        private var _status: (UInt8, UInt8, UInt8, UInt8)
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
        private var _securityKey: (UInt16, UInt16)
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
        private var ununsed: UInt16
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
        
        init(command: Command, ntStatus: UInt32 = 0, flags: Flags, flags2: Flags2 = [.LONG_NAMES, .ERR_STATUS, .UNICODE], securityKey: UInt32 = 0, securityCID: UInt16 = 0, securitySequenceNumber: UInt16 = 0, treeId: UInt16, pid: UInt32, userId: UInt16, multiplexId: UInt16) {
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
    }
    
    struct Flags: OptionSetType {
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
    
    struct Flags2: OptionSetType {
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

/// Error Types and Description

enum NTStatus: UInt32, ErrorType, CustomStringConvertible {
    case SUCCESS                        = 0x00000000
    case NOT_IMPLEMENTED                = 0xC0000002
    case INVALID_DEVICE_REQUEST         = 0xC0000010
    case ILLEGAL_FUNCTION               = 0xC00000AF
    case NO_SUCH_FILE                   = 0xC000000F
    case NO_SUCH_DEVICE                 = 0xC000000E
    case OBJECT_NAME_NOT_FOUND          = 0xC0000034
    case OBJECT_PATH_INVALID            = 0xC0000039
    case OBJECT_PATH_NOT_FOUND          = 0xC000003A
    case OBJECT_PATH_SYNTAX_BAD         = 0xC000003B
    case DFS_EXIT_PATH_FOUND            = 0xC000009B
    case REDIRECTOR_NOT_STARTED         = 0xC00000FB
    case TOO_MANY_OPENED_FILES          = 0xC000011F
    case ACCESS_DENIED                  = 0xC0000022
    case INVALID_LOCK_SEQUENCE          = 0xC000001E
    case INVALID_VIEW_SIZE              = 0xC000001F
    case ALREADY_COMMITTED              = 0xC0000021
    case PORT_CONNECTION_REFUSED        = 0xC0000041
    case THREAD_IS_TERMINATING          = 0xC000004B
    case DELETE_PENDING                 = 0xC0000056
    case PRIVILEGE_NOT_HELD             = 0xC0000061
    case LOGON_FAILURE                  = 0xC000006D
    case FILE_IS_A_DIRECTORY            = 0xC00000BA
    case FILE_RENAMED                   = 0xC00000D5
    case PROCESS_IS_TERMINATING         = 0xC000010A
    case DIRECTORY_NOT_EMPTY            = 0xC0000101
    case CANNOT_DELETE                  = 0xC0000121
    case FILE_NOT_AVAILABLE             = 0xC0000467
    case FILE_DELETED                   = 0xC0000123
    case SMB_BAD_FID                    = 0x00060001
    case INVALID_HANDLE                 = 0xC0000008
    case OBJECT_TYPE_MISMATCH           = 0xC0000024
    case PORT_DISCONNECTED              = 0xC0000037
    case INVALID_PORT_HANDLE            = 0xC0000042
    case FILE_CLOSED                    = 0xC0000128
    case HANDLE_NOT_CLOSABLE            = 0xC0000235
    case SECTION_TOO_BIG                = 0xC0000040
    case TOO_MANY_PAGING_FILES          = 0xC0000097
    case INSUFF_SERVER_RESOURCES        = 0xC0000205
    case OS2_INVALID_ACCESS             = 0x000C0001
    case ACCESS_DENIED_2                = 0xC00000CA
    case DATA_ERROR                     = 0xC000009C
    case NOT_SAME_DEVICE                = 0xC00000D4
    case NO_MORE_FILES                  = 0x80000006
    case NO_MORE_ENTRIES                = 0x8000001A
    case UNSUCCESSFUL                   = 0xC0000001
    case SHARING_VIOLATION              = 0xC0000043
    case FILE_LOCK_CONFLICT             = 0xC0000054
    case LOCK_NOT_GRANTED               = 0xC0000055
    case END_OF_FILE                    = 0xC0000011
    case NOT_SUPPORTED                  = 0xC00000BB
    case OBJECT_NAME_COLLISION          = 0xC0000035
    case INVALID_PARAMETER              = 0xC000000D
    case OS2_INVALID_LEVEL              = 0x007C0001
    case OS2_NEGATIVE_SEEK              = 0x00830001
    case RANGE_NOT_LOCKED               = 0xC000007E
    case OS2_NO_MORE_SIDS               = 0x00710001
    case OS2_CANCEL_VIOLATION           = 0x00AD0001
    case OS2_ATOMIC_LOCKS_NOT_SUPPORTED = 0x00AE0001
    case INVALID_INFO_CLASS             = 0xC0000003
    case INVALID_PIPE_STATE             = 0xC00000AD
    case INVALID_READ_MODE              = 0xC00000B4
    case OS2_CANNOT_COPY                = 0x010A0001
    case STOPPED_ON_SYMLINK             = 0x8000002D
    case INSTANCE_NOT_AVAILABLE         = 0xC00000AB
    case PIPE_NOT_AVAILABLE             = 0xC00000AC
    case PIPE_BUSY                      = 0xC00000AE
    case PIPE_CLOSING                   = 0xC00000B1
    case PIPE_EMPTY                     = 0xC00000D9
    case PIPE_DISCONNECTED              = 0xC00000B0
    case BUFFER_OVERFLOW                = 0x80000005
    case MORE_PROCESSING_REQUIRED       = 0xC0000016
    case EA_TOO_LARGE                   = 0xC0000050
    case OS2_EAS_DIDNT_FIT              = 0x01130001
    case EAS_NOT_SUPPORTED              = 0xC000004F
    case EA_LIST_INCONSISTENT           = 0x80000014
    case OS2_EA_ACCESS_DENIED           = 0x03E20001
    case NOTIFY_ENUM_DIR                = 0x0000010C
    case INVALID_SMB                    = 0x00010002
    case WRONG_PASSWORD                 = 0xC000006A
    case PATH_NOT_COVERED               = 0xC0000257
    case NETWORK_NAME_DELETED           = 0xC00000C9
    case SMB_BAD_TID                    = 0x00050002
    case BAD_NETWORK_NAME               = 0xC00000CC
    case BAD_DEVICE_TYPE                = 0xC00000CB
    case SMB_BAD_COMMAND                = 0x00160002
    case PRINT_QUEUE_FULL               = 0xC00000C6
    case NO_SPOOL_SPACE                 = 0xC00000C7
    case PRINT_CANCELLED                = 0xC00000C8
    case UNEXPECTED_NETWORK_ERROR       = 0xC00000C4
    case IO_TIMEOUT                     = 0xC00000B5
    case REQUEST_NOT_ACCEPTED           = 0xC00000D0
    case TOO_MANY_SESSIONS              = 0xC00000CE
    case SMB_BAD_UID                    = 0x005B0002
    case SMB_USE_MPX                    = 0x00FA0002
    case SMB_USE_STANDARD               = 0x00FB0002
    case SMB_CONTINUE_MPX               = 0x00FC0002
    case ACCOUNT_DISABLED               = 0xC0000072
    case ACCOUNT_EXPIRED                = 0xC0000193
    case INVALID_WORKSTATION            = 0xC0000070
    case INVALID_LOGON_HOURS            = 0xC000006F
    case PASSWORD_EXPIRED               = 0xC0000071
    case PASSWORD_MUST_CHANGE           = 0xC0000224
    case SMB_NO_SUPPORT                 = 0xFFFF0002
    case MEDIA_WRITE_PROTECTED          = 0xC00000A2
    case NO_MEDIA_IN_DEVICE             = 0xC0000013
    case INVALID_DEVICE_STATE           = 0xC0000184
    case DATA_ERROR_2                   = 0xC000003E
    case CRC_ERROR                      = 0xC000003F
    case DISK_CORRUPT_ERROR             = 0xC0000032
    case NONEXISTENT_SECTOR             = 0xC0000015
    case DEVICE_PAPER_EMPTY             = 0x8000000E
    case WRONG_VOLUME                   = 0xC0000012
    case DISK_FULL                      = 0xC000007F
    case BUFFER_TOO_SMALL               = 0xC0000023
    case BAD_IMPERSONATION_LEVEL        = 0xC00000A5
    case USER_SESSION_DELETED           = 0xC0000203
    case NETWORK_SESSION_EXPIRED        = 0xC000035C
    case SMB_TOO_MANY_UIDS              = 0xC000205A
    
    var description: String {
        switch self {
        case NOT_IMPLEMENTED, INVALID_DEVICE_REQUEST, ILLEGAL_FUNCTION:
            return "Invalid Function."
        case NO_SUCH_FILE, NO_SUCH_DEVICE, OBJECT_NAME_NOT_FOUND:
            return "File not found."
        case OBJECT_PATH_INVALID, OBJECT_PATH_NOT_FOUND, OBJECT_PATH_SYNTAX_BAD, DFS_EXIT_PATH_FOUND, REDIRECTOR_NOT_STARTED:
            return "A component in the path prefix is not a directory."
        case TOO_MANY_OPENED_FILES:
            return "Too many open files. No FIDs are available."
        case ACCESS_DENIED, INVALID_LOCK_SEQUENCE, INVALID_VIEW_SIZE, ALREADY_COMMITTED, PORT_CONNECTION_REFUSED, THREAD_IS_TERMINATING, DELETE_PENDING, PRIVILEGE_NOT_HELD, LOGON_FAILURE, FILE_IS_A_DIRECTORY, FILE_RENAMED, PROCESS_IS_TERMINATING, CANNOT_DELETE, FILE_DELETED:
            return "Access denied."
        case SMB_BAD_FID, INVALID_HANDLE, OBJECT_TYPE_MISMATCH, PORT_DISCONNECTED, INVALID_PORT_HANDLE, FILE_CLOSED, HANDLE_NOT_CLOSABLE:
            return "Invalid FID."
        case SECTION_TOO_BIG, TOO_MANY_PAGING_FILES, INSUFF_SERVER_RESOURCES:
            return "Insufficient server memory to perform the requested operation."
        case OS2_INVALID_ACCESS:
            return "Invalid open mode."
        case DATA_ERROR:
            return "Bad data. (May be generated by IOCTL calls on the server.)"
        case DIRECTORY_NOT_EMPTY:
            return "Remove of directory failed because it was not empty."
        case NOT_SAME_DEVICE:
            return "A file system operation (such as a rename) across two devices was attempted."
        case NO_MORE_FILES:
            return "No (more) files found following a file search command."
        case UNSUCCESSFUL:
            return "General error."
        case SHARING_VIOLATION:
            return "Sharing violation. A requested open mode conflicts with the sharing mode of an existing file handle."
        case FILE_LOCK_CONFLICT, LOCK_NOT_GRANTED:
            return "A lock request specified an invalid locking mode, or conflicted with an existing file lock."
        case END_OF_FILE:
            return "Attempted to read beyond the end of the file."
        case NOT_SUPPORTED:
            return "This command is not supported by the server."
        case OBJECT_NAME_COLLISION:
            return "An attempt to create a file or directory failed because an object with the same pathname already exists."
        case INVALID_PARAMETER:
            return "A parameter supplied with the message is invalid."
        case OS2_INVALID_LEVEL:
            return "Invalid information level."
        case OS2_NEGATIVE_SEEK:
            return "An attempt was made to seek to a negative absolute offset within a file."
        case RANGE_NOT_LOCKED:
            return "The byte range specified in an unlock request was not locked."
        case OS2_NO_MORE_SIDS:
            return "Maximum number of searches has been exhausted."
        case OS2_CANCEL_VIOLATION:
            return "No lock request was outstanding for the supplied cancel region."
        case OS2_ATOMIC_LOCKS_NOT_SUPPORTED:
            return "The file system does not support atomic changes to the lock type."
        case INVALID_INFO_CLASS, INVALID_PIPE_STATE, INVALID_READ_MODE:
            return "Invalid named pipe."
        case OS2_CANNOT_COPY:
            return "The copy functions cannot be used."
        case INSTANCE_NOT_AVAILABLE, PIPE_NOT_AVAILABLE, PIPE_BUSY:
            return "All instances of the designated named pipe are busy."
        case PIPE_CLOSING, PIPE_EMPTY:
            return "The designated named pipe is in the process of being closed."
        case PIPE_DISCONNECTED:
            return "The designated named pipe exists, but there is no server process listening on the server side."
        case BUFFER_OVERFLOW, MORE_PROCESSING_REQUIRED:
            return "There is more data available to read on the designated named pipe."
        case EA_TOO_LARGE, OS2_EAS_DIDNT_FIT:
            return "Either there are no extended attributes, or the available extended attributes did not fit into the response."
        case EAS_NOT_SUPPORTED:
            return "The server file system does not support Extended Attributes."
        case OS2_EA_ACCESS_DENIED:
            return "Access to the extended attribute was denied."
        default:
            return ""
        }
    }
}