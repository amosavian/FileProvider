//
//  SMBTransmitter.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/10/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

class SMBProtocolTransmitter: TCPSocketTransmitter {
    class func digestSMBMessage(data: NSData) throws -> (header: FileProviderSMBHeader, blocks: [(params: [UInt16], message: NSData?)]) {
        guard data.length > 30 else {
            throw NSURLError.BadServerResponse
        }
        var buffer = [UInt8](count: data.length, repeatedValue: 0)
        data.getBytes(&buffer, length: data.length)
        let smbver = buffer[0] == 0xff ? 1 : (buffer[0] == 0xfe ? 2 : 0)
        guard smbver > 0 else {
            throw SMBFileProviderError.BadHeader
        }
        let headersize = smbver == 2 ? sizeof(SMB2.Header.self) : sizeof(SMB1.Header.self)
        var rawHeader = buffer[0..<headersize]
        let headerData = NSData(bytesNoCopy: &rawHeader, length: headersize)
        let header: FileProviderSMBHeader = decode(headerData)
        if header.protocolID == SMB1.Header.protocolConst {
            var blocks = [(params: [UInt16], message: NSData?)]()
            var offset = headersize
            while offset < data.length {
                let paramWords: [UInt16]
                if header.protocolID == SMB1.Header.protocolConst {
                    let paramWordsCount = Int(buffer[offset])
                    guard data.length > (paramWordsCount * 2 + offset) else {
                        throw SMBFileProviderError.IncorrectParamsLength
                    }
                    offset += sizeof(UInt8)
                    var rawParamWords = [UInt8](buffer[offset..<(offset + paramWordsCount * 2)])
                    let paramData = NSData(bytesNoCopy: &rawParamWords, length: rawParamWords.count)
                    paramWords = decode(paramData)
                    offset += paramWordsCount * 2
                } else {
                    paramWords = []
                }
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
        throw SMBFileProviderError.BadHeader
    }
    
    class func createSMBMessage(header: FileProviderSMBHeader, blocks: [(params: NSData?, message: NSData?)]) -> NSData {
        var headerv = header
        let result = NSMutableData(data: encode(&headerv))
        for block in blocks {
            if header.protocolID == SMB1.Header.protocolConst {
                var paramWordsCount = UInt8(block.params?.length ?? 0)
                result.appendBytes(&paramWordsCount, length: sizeofValue(paramWordsCount))
                if let params = block.params {
                    result.appendData(params)
                }
            }
            var messageLen = UInt16(block.message?.length ?? 0)
            result.appendBytes(&messageLen, length: sizeofValue(messageLen))
            if let message = block.message {
                result.appendData(message)
            }
        }
        return result
    }
    
    func negotiateToSMB2() -> SMB2.NegotiateResponse? {
        let negHeader = SMB2.Header(command: .NEGOTIATE, creditRequestResponse: 126, messageId: 0, treeId: 0, sessionId: 0)
        let negMessage = NSData()
        SMBProtocolTransmitter.createSMBMessage(negHeader, blocks: [(params: nil, message: negMessage)])
        _ = try? self.send(data: nil)
        self.waitForResponse()
        if let response = try? SMBProtocolTransmitter.digestSMBMessage(dataRecieved) where response.blocks.count > 0 {
            if let message = response.blocks[0].message {
                return SMB2.NegotiateResponse(data: message)
            }
        }
        return nil
    }
    
    func sessionSetupForSMB2() {
        
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
        return UInt(self.time / 10000000) - 11644473600
    }
    
    var date: NSDate {
        return NSDate(timeIntervalSince1970: Double(self.time) / 10000000 - 11644473600)
    }
}

protocol FileProviderSMBHeader {
    var protocolID: UInt32 { get set }
    static var protocolConst: UInt32 { get }
}

// SMB/CIFS Types
struct SMB1 {
    struct Header { // 32 bytes
        // header is always \u{ff}SMB
        var protocolID: UInt32
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
        private var _status1: UInt8
        private var _status2: UInt8
        private var _status3: UInt8
        private var _status4: UInt8
        var error: (Class: UInt8, code: UInt16) {
            get {
                return (_status1, UInt16(_status3) + (UInt16(_status4) << 8))
            }
            set {
                _status1 = newValue.Class
                _status2 = 0
                _status3 = UInt8(newValue.code & 0xff)
                _status4 = UInt8(newValue.code >> 8)
            }
        }
        var ntStatus: UInt32 {
            get {
                let statusLo = UInt32(_status1) + UInt32(_status2) << 8
                let statusHi = UInt32(_status3) + UInt32(_status4) << 8
                return statusHi << 16 + statusLo
            }
            set {
                _status1 = UInt8(newValue & 0xff)
                _status2 = UInt8(newValue >> 8 & 0xff)
                _status3 = UInt8(newValue >> 16 & 0xff)
                _status4 = UInt8(newValue >> 24 & 0xff)
            }
        }
        var flags: Flags
        var flags2: Flags2
        var pidHigh: UInt16
        //  encryption key used for validating messages over connectionless transports
        private var _securityKeyLo: UInt16
        private var _securityKeyHi: UInt16
        var securityKey: UInt32 {
            get {
                return UInt32(_securityKeyHi) << 16 + UInt32(_securityKeyLo)
            }
            set {
                _securityKeyHi = UInt16(newValue >> 16)
                _securityKeyLo = UInt16(newValue & 0xffff)
            }
        }
        //  connection identifier
        var securityCID: UInt16
        //  identifier of the sequence of a message over connectionless transports
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
            self._status1 = UInt8(ntStatus & 0xff)
            self._status2 = UInt8(ntStatus >> 8 & 0xff)
            self._status3 = UInt8(ntStatus >> 16 & 0xff)
            self._status4 = UInt8(ntStatus >> 24 & 0xff)
            self.flags = flags
            self.flags2 = flags2
            self._securityKeyHi = UInt16(securityKey >> 16)
            self._securityKeyLo = UInt16(securityKey & 0xffff)
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
        /* This bit is set (1) in the NEGOTIATE (0x72) Response if the server supports
         * LOCK_AND_READ (0x13) and WRITE_AND_UNLOCK (0x14) commands. */
        static let LOCK_AND_READ_OK       = Flags(rawValue: 0x01)
        static let BUF_AVAIL              = Flags(rawValue: 0x02)
        static let CASE_INSENSITIVE       = Flags(rawValue: 0x08)
        static let CANONICALIZED_PATHS    = Flags(rawValue: 0x10)
        static let OPLOCK                 = Flags(rawValue: 0x20)
        static let OPBATCH                = Flags(rawValue: 0x40)
        /*  When on, this message is being sent from the server in response to a client request. */
        static let REPLY                  = Flags(rawValue: 0x80)
    }
    
    struct Flags2: OptionSetType {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        /* Client: the message MAY contain long file names. */
        static let LONG_NAMES             = Flags2(rawValue: 0x0001)
        /* Client: the client is aware of extended attributes (EAs). */
        static let EAS                    = Flags2(rawValue: 0x0002)
        /* Client: the client is requesting signing (if signing is not yet active) or the message
         * being sent is signed. This bit is used on the SMB header of an SESSION_SETUP_ANDX */
        static let SMB_SECURITY_SIGNATURE = Flags2(rawValue: 0x0004)
        //  Reserved but not implemented.
        static let IS_LONG_NAME           = Flags2(rawValue: 0x0040)
        /* client aware of Extended Security negotiation */
        static let EXT_SEC                = Flags2(rawValue:  0x0800)
        /* any pathnames in this SMB SHOULD be resolved in the Distributed File System (DFS) */
        static let DFS                    = Flags2(rawValue: 0x1000)
        /*
         * This flag is useful only on a read request. If the bit is set, then the client MAY read
         * the file if the client does not have read permission but does have execute permission. */
        static let PAGING_IO              = Flags2(rawValue:  0x2000) // READ_IF_EXECUTE
        /*
         * Client: the server MUST return errors as 32-bit NTSTATUS codes in the response
         * Server: the Status field in the header is formatted as an NTSTATUS cod */
        static let ERR_STATUS             = Flags2(rawValue: 0x4000)
        /*
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

// SMB2 Types
struct SMB2 {
    struct Header: FileProviderSMBHeader { // 64 bytes
        // header is always \u{fe}SMB
        var protocolID: UInt32
        static let protocolConst: UInt32 = 0x424d53fe
        var size: UInt16
        var creditCharge: UInt16
        // error messages from the server to the client
        var status: UInt32
        enum StatusSeverity: UInt8 {
            case Success = 0, Information, Warning, Error
        }
        var statusDetails: (severity: StatusSeverity, customer: Bool, facility: UInt16, code: UInt16) {
            let severity = StatusSeverity(rawValue: UInt8(status >> 30))!
            return (severity, status & 0x20000000 != 0, UInt16((status & 0x0FFF0000) >> 16), UInt16(status & 0x0000FFFF))
        }
        private var _command: UInt16
        var command: Command {
            get {
                return Command(rawValue: _command) ?? .INVALID
            }
            set {
                _command = newValue.rawValue
            }
        }
        var creditRequestResponse: UInt16
        var flags: Flags
        var nextCommand: UInt32
        var messageId: UInt64
        private var reserved: UInt32
        var treeId: UInt32
        var asyncId: UInt64 {
            get {
                return UInt64(reserved) + (UInt64(treeId) << 32)
            }
            set {
                reserved = UInt32(newValue & 0xffffffff)
                treeId = UInt32(newValue >> 32)
            }
        }
        var sessionId: UInt64
        var signatureLo: UInt64
        var signatureHi: UInt64
        
        init(command: Command, status: NTStatus = .SUCCESS, creditCharge: UInt16 = 0, creditRequestResponse: UInt16, flags: Flags = [], nextCommand: UInt32 = 0, messageId: UInt64, treeId: UInt32, sessionId: UInt64,signatureLo: UInt64 = 0, signatureHi: UInt64 = 0) {
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
            self.signatureLo = signatureLo
            self.signatureHi = signatureHi
        }
        
        init(asyncCommand: Command, status: NTStatus = .SUCCESS, creditCharge: UInt16 = 0, creditRequestResponse: UInt16, flags: Flags = [.ASYNC_COMMAND], nextCommand: UInt32 = 0, messageId: UInt64, asyncId: UInt64, sessionId: UInt64,signatureLo: UInt64 = 0, signatureHi: UInt64 = 0) {
            self.protocolID = self.dynamicType.protocolConst
            self.size = 64
            self.status = status.rawValue
            self._command = asyncCommand.rawValue
            self.creditCharge = creditCharge
            self.creditRequestResponse = creditRequestResponse
            self.flags = flags.union([Flags.ASYNC_COMMAND])
            self.nextCommand = nextCommand
            self.messageId = messageId
            self.reserved = 0
            reserved = UInt32(asyncId & 0xffffffff)
            treeId = UInt32(asyncId >> 32)
            self.sessionId = sessionId
            self.signatureLo = signatureLo
            self.signatureHi = signatureHi
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
    
    struct NegotiateContextType: OptionSetType {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        static let PREAUTH_INTEGRITY_CAPABILITIES   = NegotiateContextType(rawValue: 0x0001)
        static let ENCRYPTION_CAPABILITIES          = NegotiateContextType(rawValue: 0x0002)
    }
    
    struct NegotiateRequest {
        let request: NegotiateRequest.Header
        let dialects: [UInt16]
        let contexts: [(type: NegotiateContextType, data: NSData)]
        
        init(request: NegotiateRequest.Header, dialects: [UInt16] = [0x0202], contexts: [(type: NegotiateContextType, data: NSData)] = []) {
            self.request = request
            self.dialects = dialects
            self.contexts = contexts
        }
        
        func data() -> NSData {
            var request = self.request
            request.dialectCount = UInt16(dialects.count)
            let dialectData = NSMutableData()
            for dialect in dialects {
                var dialect = dialect
                dialectData.appendBytes(&dialect, length: 2)
            }
            let pad = ((1024 - dialectData.length) % 8)
            dialectData.increaseLengthBy(pad)
            request.contextOffset = UInt32(sizeof(request.dynamicType.self)) + UInt32(dialectData.length)
            request.contextCount = UInt16(contexts.count)
            let contextData = NSMutableData()
            for context in contexts {
                var contextType = context.type.rawValue
                contextData.appendBytes(&contextType, length: 2)
                var dataLen = UInt16(context.data.length)
                contextData.increaseLengthBy(4)
                contextData.appendBytes(&dataLen, length: 2)
            }
            let result = NSMutableData(data: encode(&request))
            result.appendData(dialectData)
            result.appendData(contextData)
            return result
        }
        
        struct Header {
            var size: UInt16
            var dialectCount: UInt16
            let singing: NegotiateSinging
            private let reserved: UInt16
            let capabilities: GlobalCapabilities
            let guid: uuid_t
            var contextOffset: UInt32
            var contextCount: UInt16
            private let reserved2: UInt16
            var clientStartTime: SMBTime {
                let time = UInt64(contextOffset) + (UInt64(contextCount) << 32) + (UInt64(contextCount) << 48)
                return SMBTime(time: time)
            }
            
            init(singing: NegotiateSinging, capabilities: GlobalCapabilities, guid: uuid_t? = nil, clientStartTime: SMBTime? = nil) {
                self.size = 36
                self.dialectCount = 0
                self.singing = [.ENABLED]
                self.reserved = 0
                self.capabilities = []
                self.guid = guid ?? (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                if let clientStartTime = clientStartTime {
                    let time = clientStartTime.time
                    self.contextOffset = UInt32(time & 0xffffffff)
                    self.contextCount = UInt16(time & 0x0000ffff00000000 >> 32)
                    self.reserved2 = UInt16(time >> 48)
                } else {
                    self.contextOffset = 0
                    self.contextCount = 0
                    self.reserved2 = 0
                }
            }
        }
    }
    
    struct NegotiateResponse {
        let header: NegotiateResponse.Header
        let buffer: NSData?
        let contexts: [(type: NegotiateContextType, data: NSData)]
        
        init? (data: NSData) {
            if data.length < 64 {
                return nil
            }
            let headerData = data.subdataWithRange(NSRange(location: 0, length: sizeof(NegotiateResponse.Header.self)))
            self.header = decode(headerData)
            if Int(header.size) != sizeof(NegotiateResponse.Header.self) {
                return nil
            }
            let bufOffset = Int(self.header.bufferOffset)
            let bufLen = Int(self.header.bufferLength)
            if bufOffset > 0 && bufLen > 0 && data.length >= bufOffset + bufLen {
                self.buffer = data.subdataWithRange(NSRange(location: bufOffset, length: bufLen))
            } else {
                self.buffer = nil
            }
            /*if self.header.contextCount > 0 && self.header.contextOffset > 0 {
                // TODO: NegotiateResponse context support for SMB3
            }*/
            self.contexts = []
        }
        
        struct Header {
            let size: UInt16
            let singing: NegotiateSinging
            let dialect: UInt16
            let contextCount: UInt16
            let serverGuid: uuid_t
            let capabilities: GlobalCapabilities
            let maxTransactSize: UInt32
            let maxReadSize: UInt32
            let maxWriteSize: UInt32
            let systemTime: SMBTime
            let serverStartTime: SMBTime
            let bufferOffset: UInt16
            let bufferLength: UInt16
            let contextOffset: UInt32
        }
    }
    
    struct NegotiateSinging: OptionSetType {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        static let ENABLED   = NegotiateSinging(rawValue: 0x0001)
        static let REQUIRED  = NegotiateSinging(rawValue: 0x0002)
    }
    
    struct GlobalCapabilities: OptionSetType {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        static let DFS                  = GlobalCapabilities(rawValue: 0x00000001)
        static let LEASING              = GlobalCapabilities(rawValue: 0x00000002)
        static let LARGE_MTU            = GlobalCapabilities(rawValue: 0x00000004)
        static let MULTI_CHANNEL        = GlobalCapabilities(rawValue: 0x00000008)
        static let PERSISTENT_HANDLES   = GlobalCapabilities(rawValue: 0x00000010)
        static let DIRECTORY_LEASING    = GlobalCapabilities(rawValue: 0x00000020)
        static let ENCRYPTION           = GlobalCapabilities(rawValue: 0x00000040)
    }
}

// Error Types and Description
enum NTStatus: UInt32, ErrorType, CustomStringConvertible {
    case SUCCESS                    = 0x00000000
    case NOT_IMPLEMENTED            = 0xC0000002
    case INVALID_DEVICE_REQUEST     = 0xC0000010
    case ILLEGAL_FUNCTION           = 0xC00000AF
    case NO_SUCH_FILE               = 0xC000000F
    case NO_SUCH_DEVICE             = 0xC000000E
    case OBJECT_NAME_NOT_FOUND      = 0xC0000034
    case OBJECT_PATH_INVALID        = 0xC0000039
    case OBJECT_PATH_NOT_FOUND      = 0xC000003A
    case OBJECT_PATH_SYNTAX_BAD     = 0xC000003B
    case DFS_EXIT_PATH_FOUND        = 0xC000009B
    case REDIRECTOR_NOT_STARTED     = 0xC00000FB
    case TOO_MANY_OPENED_FILES      = 0xC000011F
    case ACCESS_DENIED              = 0xC0000022
    case INVALID_LOCK_SEQUENCE      = 0xC000001E
    case INVALID_VIEW_SIZE          = 0xC000001F
    case ALREADY_COMMITTED          = 0xC0000021
    case PORT_CONNECTION_REFUSED    = 0xC0000041
    case THREAD_IS_TERMINATING      = 0xC000004B
    case DELETE_PENDING             = 0xC0000056
    case PRIVILEGE_NOT_HELD         = 0xC0000061
    case LOGON_FAILURE              = 0xC000006D
    case FILE_IS_A_DIRECTORY        = 0xC00000BA
    case FILE_RENAMED               = 0xC00000D5
    case PROCESS_IS_TERMINATING     = 0xC000010A
    case DIRECTORY_NOT_EMPTY        = 0xC0000101
    case CANNOT_DELETE              = 0xC0000121
    case FILE_NOT_AVAILABLE         = 0xC0000467
    case FILE_DELETED               = 0xC0000123
    case SMB_BAD_FID                = 0x00060001
    case INVALID_HANDLE             = 0xC0000008
    case OBJECT_TYPE_MISMATCH       = 0xC0000024
    case PORT_DISCONNECTED          = 0xC0000037
    case INVALID_PORT_HANDLE        = 0xC0000042
    case FILE_CLOSED                = 0xC0000128
    case HANDLE_NOT_CLOSABLE        = 0xC0000235
    case SECTION_TOO_BIG            = 0xC0000040
    case TOO_MANY_PAGING_FILES      = 0xC0000097
    case INSUFF_SERVER_RESOURCES    = 0xC0000205
    case OS2_INVALID_ACCESS         = 0x000C0001
    case ACCESS_DENIED_2            = 0xC00000CA
    case DATA_ERROR                 = 0xC000009C
    case NOT_SAME_DEVICE            = 0xC00000D4
    case NO_MORE_FILES              = 0x80000006
    case NO_MORE_ENTRIES            = 0x8000001A
    case UNSUCCESSFUL               = 0xC0000001
    case SHARING_VIOLATION          = 0xC0000043
    case FILE_LOCK_CONFLICT         = 0xC0000054
    case LOCK_NOT_GRANTED           = 0xC0000055
    case END_OF_FILE                = 0xC0000011
    case NOT_SUPPORTED              = 0xC00000BB
    case OBJECT_NAME_COLLISION      = 0xC0000035
    case INVALID_PARAMETER          = 0xC000000D
    case OS2_INVALID_LEVEL          = 0x007C0001
    case OS2_NEGATIVE_SEEK          = 0x00830001
    case RANGE_NOT_LOCKED           = 0xC000007E
    case OS2_NO_MORE_SIDS           = 0x00710001
    case OS2_CANCEL_VIOLATION       = 0x00AD0001
    case OS2_ATOMIC_LOCKS_NOT_SUPPORTED = 0x00AE0001
    case INVALID_INFO_CLASS         = 0xC0000003
    case INVALID_PIPE_STATE         = 0xC00000AD
    case INVALID_READ_MODE          = 0xC00000B4
    case OS2_CANNOT_COPY            = 0x010A0001
    case STOPPED_ON_SYMLINK         = 0x8000002D
    case INSTANCE_NOT_AVAILABLE     = 0xC00000AB
    case PIPE_NOT_AVAILABLE         = 0xC00000AC
    case PIPE_BUSY                  = 0xC00000AE
    case PIPE_CLOSING               = 0xC00000B1
    case PIPE_EMPTY                 = 0xC00000D9
    case PIPE_DISCONNECTED          = 0xC00000B0
    case BUFFER_OVERFLOW            = 0x80000005
    case MORE_PROCESSING_REQUIRED   = 0xC0000016
    case EA_TOO_LARGE               = 0xC0000050
    case OS2_EAS_DIDNT_FIT          = 0x01130001
    case EAS_NOT_SUPPORTED          = 0xC000004F
    case EA_LIST_INCONSISTENT       = 0x80000014
    case OS2_EA_ACCESS_DENIED       = 0x03E20001
    case NOTIFY_ENUM_DIR            = 0x0000010C
    case INVALID_SMB                = 0x00010002
    case WRONG_PASSWORD             = 0xC000006A
    case PATH_NOT_COVERED           = 0xC0000257
    case NETWORK_NAME_DELETED       = 0xC00000C9
    case SMB_BAD_TID                = 0x00050002
    case BAD_NETWORK_NAME           = 0xC00000CC
    case BAD_DEVICE_TYPE            = 0xC00000CB
    case SMB_BAD_COMMAND            = 0x00160002
    case PRINT_QUEUE_FULL           = 0xC00000C6
    case NO_SPOOL_SPACE             = 0xC00000C7
    case PRINT_CANCELLED            = 0xC00000C8
    case UNEXPECTED_NETWORK_ERROR   = 0xC00000C4
    case IO_TIMEOUT                 = 0xC00000B5
    case REQUEST_NOT_ACCEPTED       = 0xC00000D0
    case TOO_MANY_SESSIONS          = 0xC00000CE
    case SMB_BAD_UID                = 0x005B0002
    case SMB_USE_MPX                = 0x00FA0002
    case SMB_USE_STANDARD           = 0x00FB0002
    case SMB_CONTINUE_MPX           = 0x00FC0002
    case ACCOUNT_DISABLED           = 0xC0000072
    case ACCOUNT_EXPIRED            = 0xC0000193
    case INVALID_WORKSTATION        = 0xC0000070
    case INVALID_LOGON_HOURS        = 0xC000006F
    case PASSWORD_EXPIRED           = 0xC0000071
    case PASSWORD_MUST_CHANGE       = 0xC0000224
    case SMB_NO_SUPPORT             = 0xFFFF0002
    case MEDIA_WRITE_PROTECTED      = 0xC00000A2
    case NO_MEDIA_IN_DEVICE         = 0xC0000013
    case INVALID_DEVICE_STATE       = 0xC0000184
    case DATA_ERROR_2               = 0xC000003E
    case CRC_ERROR                  = 0xC000003F
    case DISK_CORRUPT_ERROR         = 0xC0000032
    case NONEXISTENT_SECTOR         = 0xC0000015
    case DEVICE_PAPER_EMPTY         = 0x8000000E
    case WRONG_VOLUME               = 0xC0000012
    case DISK_FULL                  = 0xC000007F
    
    
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