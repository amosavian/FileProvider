//
//  SMB2Types.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

protocol IOCtlRequestProtocol: SMBRequest {}
protocol IOCtlResponseProtocol: SMBResponse {}

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
    
    // MARK: SMB2 Negotiating
    
    struct NegotiateRequest: SMBRequest {
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
            
            init(singing: NegotiateSinging = [.ENABLED], capabilities: GlobalCapabilities, guid: uuid_t? = nil, clientStartTime: SMBTime? = nil) {
                self.size = 36
                self.dialectCount = 0
                self.singing = singing
                self.reserved = 0
                self.capabilities = capabilities
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
    
    struct NegotiateResponse: SMBResponse {
        let header: NegotiateResponse.Header
        let buffer: NSData?
        let contexts: [(type: NegotiateContextType, data: NSData)]
        
        init? (data: NSData) {
            if data.length < 64 {
                return nil
            }
            self.header = decode(data)
            if Int(header.size) != 65 {
                return nil
            }
            let bufOffset = Int(self.header.bufferOffset) - sizeof(SMB2.Header.self)
            let bufLen = Int(self.header.bufferLength)
            if bufOffset > 0 && bufLen > 0 && data.length >= bufOffset + bufLen {
                self.buffer = data.subdataWithRange(NSRange(location: bufOffset, length: bufLen))
            } else {
                self.buffer = nil
            }
            let contextCount = Int(self.header.contextCount)
            let contextOffset = Int(self.header.contextOffset) - sizeof(SMB2.Header.self)
            if  contextCount > 0 &&  contextOffset > 0 {
                // TODO: NegotiateResponse context support for SMB3
                self.contexts = []
            } else {
                self.contexts = []
            }
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
    
    struct NegotiateContextType: OptionSetType {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        static let PREAUTH_INTEGRITY_CAPABILITIES   = NegotiateContextType(rawValue: 0x0001)
        static let ENCRYPTION_CAPABILITIES          = NegotiateContextType(rawValue: 0x0002)
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
    
    // MARK: SMB2 Session Setup
    
    struct SessionSetupRequest: SMBRequest {
        let header: SessionSetupRequest.Header
        let buffer: NSData?
        
        init(header: SessionSetupRequest.Header, buffer: NSData) {
            self.header = header
            self.buffer = buffer
        }
        
        func data() -> NSData {
            var header = self.header
            header.bufferOffset = UInt16(sizeof(SMB2.Header.self) + sizeof(SessionSetupRequest.Header.self))
            header.bufferLength = UInt16(buffer?.length ?? 0)
            let result = NSMutableData(data: encode(&header))
            if let buffer = self.buffer {
                result.appendData(buffer)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            let flags: SessionSetupRequest.Flags
            let signing: SessionSetupSinging
            let capabilities: GlobalCapabilities
            private let channel: UInt32
            var bufferOffset: UInt16
            var bufferLength: UInt16
            let sessionId: UInt64
            
            init(sessionId: UInt64, flags: SessionSetupRequest.Flags = [], singing: SessionSetupSinging, capabilities: GlobalCapabilities) {
                self.size = 25
                self.flags = flags
                self.signing = singing
                self.capabilities = capabilities
                self.channel = 0
                self.bufferOffset = 0
                self.bufferLength = 0
                self.sessionId = sessionId
            }
        }
        
        /// Works the client implements the SMB 3.x dialect family
        struct Flags: OptionSetType {
            let rawValue: UInt8
            
            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            static let BINDING = NegotiateSinging(rawValue: 0x01)
        }
    }
    
    struct SessionSetupResponse: SMBResponse {
        let header: SessionSetupResponse.Header
        let buffer: NSData?
        
        init? (data: NSData) {
            if data.length < 64 {
                return nil
            }
            self.header = decode(data)
            if Int(header.size) != 9 {
                return nil
            }
            let bufOffset = Int(self.header.bufferOffset) - sizeof(SMB2.Header.self)
            let bufLen = Int(self.header.bufferLength)
            if bufOffset > 0 && bufLen > 0 && data.length >= bufOffset + bufLen {
                self.buffer = data.subdataWithRange(NSRange(location: bufOffset, length: bufLen))
            } else {
                self.buffer = nil
            }
        }
        
        struct Header {
            let size: UInt16
            let flags: SessionSetupResponse.Flags
            let bufferOffset: UInt16
            let bufferLength: UInt16
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt16
            
            init(rawValue: UInt16) {
                self.rawValue = rawValue
            }
            
            static let IS_GUEST     = Flags(rawValue: 0x0001)
            static let IS_NULL      = Flags(rawValue: 0x0002)
            static let ENCRYPT_DATA = Flags(rawValue: 0x0004)
        }
    }
    
    struct SessionSetupSinging: OptionSetType {
        let rawValue: UInt8
        
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        static let ENABLED   = NegotiateSinging(rawValue: 0x01)
        static let REQUIRED  = NegotiateSinging(rawValue: 0x02)
    }
    
    // MARK: SMB2 Log off
    
    struct LogOff: SMBRequest, SMBResponse {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
    
    // MARK: SMB2 Tree Connect
    
    struct TreeConnectRequest: SMBRequest {
        let header: TreeConnectRequest.Header
        let buffer: NSData?
        var path: String {
            return ""
        }
        var share: String {
            return ""
        }
        
        init? (header: TreeConnectRequest.Header, host: String, share: String) {
            guard !host.containsString("/") && !host.containsString("/") && !share.containsString("/") && !share.containsString("/") else {
                return nil
            }
            self.header = header
            let path = "\\\\\(host)\\\(share)"
            self.buffer = path.dataUsingEncoding(NSUTF8StringEncoding)
        }
        
        func data() -> NSData {
            var header = self.header
            header.pathOffset = UInt16(sizeof(SMB2.Header.self) + sizeof(TreeConnectRequest.Header.self))
            header.pathLength = UInt16(buffer?.length ?? 0)
            let result = NSMutableData(data: encode(&header))
            if let buffer = self.buffer {
                result.appendData(buffer)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            let flags: TreeConnectRequest.Flags
            var pathOffset: UInt16
            var pathLength: UInt16
            
            init(flags: TreeConnectRequest.Flags) {
                self.size = 9
                self.flags = flags
                self.pathOffset = 0
                self.pathLength = 0
            }
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt16
            
            init(rawValue: UInt16) {
                self.rawValue = rawValue
            }
            
            static let SHAREFLAG_CLUSTER_RECONNECT = Flags(rawValue: 0x0001)
        }
    }
    
    struct TreeConnectResponse: SMBResponse {
        let size: UInt16  // = 16
        private let _type: UInt8
        var type: ShareType {
            return ShareType(rawValue: _type) ?? .UNKNOWN
        }
        private let reserved: UInt8
        let flags: TreeConnectResponse.ShareFlags
        let capabilities: TreeConnectResponse.Capabilities
        let maximalAccess: FileAccessMask
        
        init? (data: NSData) {
            if data.length != 16 {
                return nil
            }
            self = decode(data)
        }
        
        enum ShareType: UInt8 {
            case UNKNOWN  = 0x00
            case DISK     = 0x01
            case PIPE     = 0x02
            case PRINT    = 0x03
        }
        
        struct ShareFlags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let DFS                          = ShareFlags(rawValue: 0x00000001)
            static let DFS_ROOT                     = ShareFlags(rawValue: 0x00000002)
            static let MANUAL_CACHING               = ShareFlags(rawValue: 0x00000000)
            static let AUTO_CACHING                 = ShareFlags(rawValue: 0x00000010)
            static let VDO_CACHING                  = ShareFlags(rawValue: 0x00000020)
            static let NO_CACHING                   = ShareFlags(rawValue: 0x00000030)
            static let RESTRICT_EXCLUSIVE_OPENS     = ShareFlags(rawValue: 0x00000100)
            static let FORCE_SHARED_DELETE          = ShareFlags(rawValue: 0x00000200)
            static let ALLOW_NAMESPACE_CACHING      = ShareFlags(rawValue: 0x00000400)
            static let ACCESS_BASED_DIRECTORY_ENUM  = ShareFlags(rawValue: 0x00000800)
            static let FORCE_LEVELII_OPLOCK         = ShareFlags(rawValue: 0x00001000)
            static let ENABLE_HASH_V1               = ShareFlags(rawValue: 0x00002000)
            static let ENABLE_HASH_V2               = ShareFlags(rawValue: 0x00004000)
            static let ENCRYPT_DATA                 = ShareFlags(rawValue: 0x00008000)
        }
        
        struct Capabilities: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let DFS                      = Capabilities(rawValue: 0x00000008)
            static let CONTINUOUS_AVAILABILITY  = Capabilities(rawValue: 0x00000010)
            static let SCALEOUT                 = Capabilities(rawValue: 0x00000020)
            static let CLUSTER                  = Capabilities(rawValue: 0x00000040)
            static let ASYMMETRIC               = Capabilities(rawValue: 0x00000080)
        }
    }
    
    // MARK: SMB2 Tree Disconnect
    
    struct TreeDisconnect: SMBRequest, SMBResponse {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
    
    // MARK: SMB2 Create
    
    struct CreateRequest: SMBRequest {
        let header: CreateRequest.Header
        let name: String?
        let contexts: [CreateContext]
        
        init (header: CreateRequest.Header, name: String? = nil, contexts: [CreateContext] = []) {
            self.header = header
            self.name = name
            self.contexts = contexts
        }
        
        func data() -> NSData {
            var header = self.header
            var offset = 0x78 //UInt16(sizeof(SMB2.Header.self) + sizeof(CreateContext.Header.self) - 1)
            let body = NSMutableData()
            if let name = self.name, let nameData = name.dataUsingEncoding(NSUTF8StringEncoding) {
                header.nameOffset = UInt16(offset)
                header.nameLength = UInt16(nameData.length)
                offset += nameData.length
                body.appendData(nameData)
            }
            if contexts.count > 0 {
                // TODO: Context CreateRequest implementation, 8 bit allign offset
                header.contextOffset = UInt32(offset)
                
                
                header.contextLength = 0
                //result.appendData(nameData)
            }
            let result = NSMutableData(data: encode(&header))
            result.appendData(body)
            return result
        }
        
        struct Header {
            let size: UInt16
            private let securityFlags: UInt8
            private var _requestedOplockLevel: UInt8
            var requestedOplockLevel: OplockLevel {
                get {
                    return OplockLevel(rawValue: _requestedOplockLevel)!
                }
                set {
                    _requestedOplockLevel = newValue.rawValue
                }
            }
            private var _impersonationLevel: UInt32
            var impersonationLevel: ImpersonationLevel {
                get {
                    return ImpersonationLevel(rawValue: _impersonationLevel)!
                }
                set {
                    _impersonationLevel = newValue.rawValue
                }
            }
            private let flags: UInt64
            private let reserved: UInt64
            let access: FileAccessMask
            let fileAttributes: FileAttributes
            let shareAccess: ShareAccess
            private var _desposition: UInt32
            var desposition: CreateDisposition {
                get {
                    return CreateDisposition(rawValue: _desposition)!
                }
                set {
                    _desposition = newValue.rawValue
                }
            }
            let options: CreateOptions
            var nameOffset: UInt16
            var nameLength: UInt16
            var contextOffset: UInt32
            var contextLength: UInt32
            
            init(requestedOplockLevel: OplockLevel = .NONE, impersonationLevel: ImpersonationLevel = .Anonymous, access: FileAccessMask = [.GENERIC_ALL], fileAttributes: FileAttributes = [], shareAccess: ShareAccess = [.READ], desposition: CreateDisposition = .OPEN_IF, options: CreateOptions = []) {
                self.size = 57
                self.securityFlags = 0
                self._requestedOplockLevel = requestedOplockLevel.rawValue
                self._impersonationLevel = impersonationLevel.rawValue
                self.flags = 0
                self.reserved = 0
                self.access = access
                self.fileAttributes = fileAttributes
                self.shareAccess = shareAccess
                self._desposition = desposition.rawValue
                self.options = options
                self.nameOffset = 0
                self.nameLength = 0
                self.contextOffset = 0
                self.contextLength = 0
            }
        }
        
        struct CreateOptions: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let DIRECTORY_FILE               = CreateOptions(rawValue: 0x00000001)
            static let WRITE_THROUGH                = CreateOptions(rawValue: 0x00000002)
            static let SEQUENTIAL_ONLY              = CreateOptions(rawValue: 0x00000004)
            static let NO_INTERMEDIATE_BUFFERING    = CreateOptions(rawValue: 0x00000008)
            static let NON_DIRECTORY_FILE           = CreateOptions(rawValue: 0x00000040)
            static let NO_EA_KNOWLEDGE              = CreateOptions(rawValue: 0x00000200)
            static let RANDOM_ACCESS                = CreateOptions(rawValue: 0x00000800)
            static let DELETE_ON_CLOSE              = CreateOptions(rawValue: 0x00001000)
            static let OPEN_BY_FILE_ID              = CreateOptions(rawValue: 0x00002000)
            static let OPEN_FOR_BACKUP_INTENT       = CreateOptions(rawValue: 0x00004000)
            static let NO_COMPRESSION               = CreateOptions(rawValue: 0x00008000)
            static let OPEN_REPARSE_POINT           = CreateOptions(rawValue: 0x00200000)
            static let OPEN_NO_RECALL               = CreateOptions(rawValue: 0x00400000)
            private static let SYNCHRONOUS_IO_ALERT         = CreateOptions(rawValue: 0x00000010)
            private static let SYNCHRONOUS_IO_NONALERT      = CreateOptions(rawValue: 0x00000020)
            private static let COMPLETE_IF_OPLOCKED         = CreateOptions(rawValue: 0x00000100)
            private static let REMOTE_INSTANCE              = CreateOptions(rawValue: 0x00000400)
            private static let OPEN_FOR_FREE_SPACE_QUERY    = CreateOptions(rawValue: 0x00800000)
            private static let OPEN_REQUIRING_OPLOCK        = CreateOptions(rawValue: 0x00010000)
            private static let DISALLOW_EXCLUSIVE           = CreateOptions(rawValue: 0x00020000)
            private static let RESERVE_OPFILTER             = CreateOptions(rawValue: 0x00100000)
        }
        
        enum CreateDisposition: UInt32 {
            /// If the file already exists, supersede it. Otherwise, create the file.
            case SUPERSEDE      = 0x00000000
            /// If the file already exists, return success; otherwise, fail the operation.
            case OPEN           = 0x00000001
            /// If the file already exists, fail the operation; otherwise, create the file.
            case CREATE         = 0x00000002
            /// Open the file if it already exists; otherwise, create the file.
            case OPEN_IF        = 0x00000003
            /// Overwrite the file if it already exists; otherwise, fail the operation.
            case OVERWRITE      = 0x00000004
            /// Overwrite the file if it already exists; otherwise, create the file.
            case OVERWRITE_IF   = 0x00000005
        }
        
        enum ImpersonationLevel: UInt32 {
            case Anonymous = 0x00000000
            case Identification = 0x00000001
            case Impersonation = 0x00000002
            case Delegate = 0x00000003
        }
    }
    
    struct CreateResponse: SMBResponse {
        struct Header {
            let size: UInt16
            private let _oplockLevel: UInt8
            var oplockLevel: OplockLevel {
                return OplockLevel(rawValue: _oplockLevel)!
            }
            private let reserved: UInt32
            let creationTime: SMBTime
            let lastAccessTime: SMBTime
            let lastWriteTime: SMBTime
            let changeTime: SMBTime
            let allocationSize: UInt64
            let endOfFile: UInt64
            let fileAttributes: FileAttributes
            private let reserved2: UInt32
            let fileId: FileId
            let contextsOffset: UInt32
            let ContextsLength: UInt32
        }
        
        let header: CreateResponse.Header
        let contexts: [CreateContext]
        
        init? (data: NSData) {
            guard data.length >= sizeof(CreateResponse.Header.self) else {
                return nil
            }
            self.header = decode(data)
            if self.header.contextsOffset > 0 {
                var contexts = [CreateContext]()
                var contextOffset = Int(self.header.contextsOffset) - sizeof(SMB2.Header.self)
                while contextOffset > 0 {
                    guard contextOffset < data.length else {
                        self.contexts = contexts
                        return
                    }
                    let contextDataHeader = data.subdataWithRange(NSRange(location: contextOffset, length: sizeof(CreateContext.Header.self)))
                    if let lastContextHeader = CreateContext(data: contextDataHeader) {
                        let lastContextLen = Int(lastContextHeader.header.dataOffset) + Int(lastContextHeader.header.dataLength) - contextOffset
                        let lastContextData = data.subdataWithRange(NSRange(location: contextOffset, length: lastContextLen))
                        if let newContext = CreateContext(data: lastContextData) {
                            contexts.append(newContext)
                        }
                        contextOffset = Int(lastContextHeader.header.next) - sizeof(SMB2.Header.self)
                    }
                }
                self.contexts = contexts
            } else {
                self.contexts = []
            }
        }
    }
    
    struct CreateContext {
        struct Header {
            var next: UInt32
            let nameOffset: UInt16
            let nameLength: UInt16
            private let reserved: UInt16
            let dataOffset: UInt16
            let dataLength: UInt32
        }
        
        var header: CreateContext.Header
        let buffer: NSData
        
        init(name: ContextNames, data: NSData) {
            let nameData = NSMutableData(data: (name.rawValue).dataUsingEncoding(NSUTF8StringEncoding)!)
            self.header = CreateContext.Header(next: 0, nameOffset: 32, nameLength: UInt16(nameData.length), reserved: 0, dataOffset: UInt16(nameData.length), dataLength: UInt32(data.length))
            self.buffer = data
        }
        
        init(name: NSUUID, data: NSData) {
            var uuid = uuid_t(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
            name.getUUIDBytes(&uuid.0)
            let nameData = NSMutableData(bytes: &uuid, length: 16)
            self.header = CreateContext.Header(next: 0, nameOffset: 32, nameLength: UInt16(nameData.length), reserved: 0, dataOffset: UInt16(nameData.length), dataLength: UInt32(data.length))
            self.buffer = data
        }
        
        init? (data: NSData) {
            let headersize = sizeof(Header)
            guard data.length > headersize else {
                return nil
            }
            self.header = decode(data)
            self.buffer = data.subdataWithRange(NSRange(location: headersize, length: data.length - headersize))
        }
        
        func data() -> NSData {
            let result = NSMutableData(data: encode(header))
            result.appendData(buffer)
            return result
        }
        
        enum ContextNames: String {
            /// Request Create Context: Extended attributes
            case EA_BUFFER = "ExtA"
            /// Request Create Context: Security descriptor
            case SD_BUFFER = "SecD"
            /// Request & Response Create Context: Open to be durable
            case DURABLE_HANDLE = "DHnQ"
            case DURABLE_HANDLE_RESPONSE_V2 = "DH2Q"
            /// Request Create Context: Reconnect to a durable open after being disconnected
            case DURABLE_HANDLE_RECONNECT = "DHnC"
            /// Request Create Context: Required allocation size of the newly created file
            case ALLOCATION_SIZE = "AISi"
            /// Request & Response Create Context: Maximal access information
            case QUERY_MAXIMAL_ACCESS = "MxAc"
            case TIMEWARP_TOKEN = "TWrp"
            /// Response Create Context: DiskID of the open file in a volume.
            case QUERY_ON_DISK_ID = "QFid"
            /// Response Create Context: A lease. This value is only supported for the SMB 2.1 and 3.x dialect family.
            case LEASE = "RqLs"
        }
    }
    
    enum OplockLevel: UInt8 {
        case NONE = 0x00
        case LEVEL_II = 0x01
        case EXCLUSIVE = 0x08
        case BATCH = 0x09
        case LEASE = 0xFF
    }
    
    struct ShareAccess: OptionSetType {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static let READ     = ShareAccess(rawValue: 0x00000001)
        static let WRITE    = ShareAccess(rawValue: 0x00000002)
        static let DELETE   = ShareAccess(rawValue: 0x00000004)
    }
    
    struct FileAccessMask: OptionSetType {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        // File and Printer/Pipe Accesses
        static let FILE_READ_DATA = FileAccessMask(rawValue: 0x00000001)
        static let FILE_WRITE_DATA = FileAccessMask(rawValue: 0x00000002)
        static let FILE_APPEND_DATA = FileAccessMask(rawValue: 0x00000004)
        static let FILE_EXECUTE = FileAccessMask(rawValue: 0x00000020)
        // Directory
        static let FILE_LIST_DIRECTORY = FileAccessMask(rawValue: 0x00000001)
        static let FILE_ADD_FILE = FileAccessMask(rawValue: 0x00000002)
        static let FILE_ADD_SUBDIRECTORY = FileAccessMask(rawValue: 0x00000004)
        static let FILE_TRAVERSE = FileAccessMask(rawValue: 0x00000020)
        // Generic
        static let FILE_READ_EA = FileAccessMask(rawValue: 0x00000008)
        static let FILE_WRITE_EA = FileAccessMask(rawValue: 0x00000010)
        static let FILE_DELETE_CHILD = FileAccessMask(rawValue: 0x00000040)
        static let FILE_READ_ATTRIBUTES = FileAccessMask(rawValue: 0x00000080)
        static let FILE_WRITE_ATTRIBUTES = FileAccessMask(rawValue: 0x00000100)
        static let DELETE = FileAccessMask(rawValue: 0x00010000)
        static let READ_CONTROL = FileAccessMask(rawValue: 0x00020000)
        static let WRITE_DAC = FileAccessMask(rawValue: 0x00040000)
        static let WRITE_OWNER = FileAccessMask(rawValue: 0x00080000)
        static let SYNCHRONIZE = FileAccessMask(rawValue: 0x00100000)
        static let ACCESS_SYSTEM_SECURITY = FileAccessMask(rawValue: 0x01000000)
        static let MAXIMUM_ALLOWED = FileAccessMask(rawValue: 0x02000000)
        static let GENERIC_ALL = FileAccessMask(rawValue: 0x10000000)
        static let GENERIC_EXECUTE = FileAccessMask(rawValue: 0x20000000)
        static let GENERIC_WRITE = FileAccessMask(rawValue: 0x40000000)
        static let GENERIC_READ = FileAccessMask(rawValue: 0x80000000)
    }
    
    struct FileAttributes: OptionSetType {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static let READONLY             = FileAttributes(rawValue: 0x00000001)
        static let HIDDEN               = FileAttributes(rawValue: 0x00000002)
        static let SYSTEM               = FileAttributes(rawValue: 0x00000004)
        static let DIRECTORY            = FileAttributes(rawValue: 0x00000010)
        static let ARCHIVE              = FileAttributes(rawValue: 0x00000020)
        static let NORMAL               = FileAttributes(rawValue: 0x00000080)
        static let TEMPORARY            = FileAttributes(rawValue: 0x00000100)
        static let SPARSE_FILE          = FileAttributes(rawValue: 0x00000200)
        static let REPARSE_POINT        = FileAttributes(rawValue: 0x00000400)
        static let COMPRESSED           = FileAttributes(rawValue: 0x00000800)
        static let OFFLINE              = FileAttributes(rawValue: 0x00001000)
        static let NOT_CONTENT_INDEXED  = FileAttributes(rawValue: 0x00002000)
        static let ENCRYPTED            = FileAttributes(rawValue: 0x00004000)
        static let INTEGRITY_STREAM     = FileAttributes(rawValue: 0x00008000)
        static let NO_SCRUB_DATA        = FileAttributes(rawValue: 0x00020000)
    }
    
    struct FileId {
        let persistent: UInt64
        let volatile: UInt64
    }
    
    // MARK: SMB2 Close
    
    struct CloseRequest: SMBRequest {
        let size: UInt16
        let flags: CloseFlags
        private let reserved2: UInt32
        let filePersistantId: UInt64
        let fileVolatileId: UInt64
        
        init(filePersistantId: UInt64, fileVolatileId: UInt64) {
            self.size = 24
            self.filePersistantId = filePersistantId
            self.fileVolatileId = fileVolatileId
            self.flags = []
            self.reserved2 = 0
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
    
    struct CloseResponse: SMBResponse {
        let size: UInt16
        let flags: CloseFlags
        private let reserved: UInt32
        let creationTime: SMBTime
        let lastAccessTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let allocationSize: UInt64
        let endOfFile: UInt64
        let fileAttributes: FileAttributes
        
        init? (data: NSData) {
            self = decode(data)
        }
    }
    
    struct CloseFlags: OptionSetType {
        let rawValue: UInt16
        
        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        
        static let POSTQUERY_ATTRIB = Flags(rawValue: 0x0001)
    }
    
    // MARK: SMB2 Flush
    
    struct FlushRequest: SMBRequest {
        let size: UInt16
        private let reserved: UInt16
        private let reserved2: UInt32
        let filePersistantId: UInt64
        let fileVolatileId: UInt64
        
        init(filePersistantId: UInt64, fileVolatileId: UInt64) {
            self.size = 24
            self.filePersistantId = filePersistantId
            self.fileVolatileId = fileVolatileId
            self.reserved = 0
            self.reserved2 = 0
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
    
    struct FlushResponse: SMBResponse {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
    }
    
    // MARK: SMB2 Read
    
    struct ReadRequest: SMBRequest {
        let size: UInt16
        private let padding: UInt8
        let flags: ReadRequest.Flags
        let length: UInt32
        let offset: UInt64
        let fileId: FileId
        let minimumLength: UInt32
        private let _channel: UInt32
        var channel: Channel {
            return Channel(rawValue: _channel) ?? .NONE
        }
        let remainingBytes: UInt32
        private let channelInfoOffset: UInt16
        private let channelInfoLength: UInt16
        private let channelBuffer: UInt8
        
        init (fileId: FileId, offset: UInt64, length: UInt32, flags: ReadRequest.Flags = [], minimumLength: UInt32 = 0, remainingBytes: UInt32 = 0, channel: Channel = .NONE) {
            self.size = 49
            self.padding = 0
            self.flags = flags
            self.length = length
            self.offset = offset
            self.fileId = fileId
            self.minimumLength = minimumLength
            self._channel = channel.rawValue
            self.remainingBytes = remainingBytes
            self.channelInfoOffset = 0
            self.channelInfoLength = 0
            self.channelBuffer = 0
        }
        
        func data() -> NSData {
            return encode(read)
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt8
            
            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            static let UNBUFFERED = Flags(rawValue: 0x01)
        }
    }
    
    struct ReadRespone: SMBResponse {
        struct Header {
            let size: UInt16
            let offset: UInt8
            private let reserved: UInt8
            let length: UInt32
            let remaining: UInt32
            private let reserved2: UInt32
            
        }
        let header: ReadRespone.Header
        let buffer: NSData
        
        init?(data: NSData) {
            guard data.length > 16 else {
                return nil
            }
            self.header = decode(data)
            let headersize = sizeof(Header)
            self.buffer = data.subdataWithRange(NSRange(location: headersize, length: data.length - headersize))
        }
    }
    
    enum Channel: UInt32 {
        case NONE                   = 0x00000000
        case RDMA_V1                = 0x00000001
        case RDMA_V1_INVALIDATE     =  0x00000002
    }
    
    // MARK: SMB2 Write
    
    struct WriteRequest: SMBRequest {
        let header: WriteRequest.Header
        let channelInfo: ChannelInfo?
        let fileData: NSData
        
        struct Header {
            let size: UInt16
            let dataOffset: UInt16
            let length: UInt32
            let offset: UInt64
            let fileId: FileId
            private let _channel: UInt32
            var channel: Channel {
                return Channel(rawValue: _channel) ?? .NONE
            }
            let remainingBytes: UInt32
            let channelInfoOffset: UInt16
            let channelInfoLength: UInt16
            let flags: WriteRequest.Flags
        }
        
        init(fileId: FileId, offset: UInt64, remainingBytes: UInt32 = 0, data: NSData, channel: Channel = .NONE, channelInfo: ChannelInfo? = nil, flags: WriteRequest.Flags = []) {
            var channelInfoOffset: UInt16 = 0
            var channelInfoLength: UInt16 = 0
            if channel != .NONE, let channelInfo = channelInfo {
                channelInfoOffset = UInt16(sizeof(SMB2.Header.self) + sizeof(WriteRequest.Header.self))
                channelInfoLength = UInt16(sizeof(channelInfo.dynamicType))
            }
            let dataOffset = UInt16(sizeof(SMB2.Header.self) + sizeof(WriteRequest.Header.self)) + channelInfoLength
            self.header = WriteRequest.Header(size: UInt16(49), dataOffset: dataOffset, length: UInt32(data.length), offset: offset, fileId: fileId, _channel: channel.rawValue, remainingBytes: remainingBytes, channelInfoOffset: channelInfoOffset, channelInfoLength: channelInfoLength, flags: flags)
            self.channelInfo = channelInfo
            self.fileData = data
        }
        
        func data() -> NSData {
            let result = NSMutableData(data: encode(self.header))
            if let channelInfo = channelInfo {
                result.appendData(channelInfo.data())
            }
            result.appendData(fileData)
            return result
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let THROUGH      = Flags(rawValue: 0x00000001)
            static let UNBUFFERED   = Flags(rawValue: 0x00000002)
        }
    }
    
    struct WriteResponse: SMBResponse {
        let size: UInt16
        private let reserved: UInt16
        let writtenBytes: UInt32
        private let remaining: UInt32
        private let channelInfoOffset: UInt16
        private let channelInfoLength: UInt16
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    struct ChannelInfo: SMBRequest {
        let offset: UInt64
        let token: UInt32
        let length: UInt32
        
        func data() -> NSData {
            return encode(data)
        }
    }
    
    // MARK: SMB2 Lock
    
    struct LockElement: SMBRequest {
        let offset: UInt64
        let length: UInt64
        let flags: LockElement.Flags
        private let reserved: UInt32
        
        func data() -> NSData {
            return encode(self)
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let SHARED_LOCK      = Flags(rawValue: 0x00000001)
            static let EXCLUSIVE_LOCK   = Flags(rawValue: 0x00000002)
            static let UNLOCK           = Flags(rawValue: 0x00000004)
            static let FAIL_IMMEDIATELY = Flags(rawValue: 0x00000010)
        }
    }
    
    struct LockRequest: SMBRequest {
        let header: LockRequest.Header
        let locks: [LockElement]
        
        init(fileId: FileId,locks: [LockElement], lockSequenceNumber : Int8 = 0, lockSequenceIndex: UInt32 = 0) {
            self.header = LockRequest.Header(size: 48, lockCount: UInt16(locks.count), lockSequence: UInt32(lockSequenceNumber << 28) + lockSequenceIndex, fileId: fileId)
            self.locks = locks
        }
        
        func data() -> NSData {
            let result = NSMutableData(data: encode(header))
            for lock in locks {
                result.appendData(encode(lock))
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            private let lockCount: UInt16
            let lockSequence: UInt32
            let fileId : FileId
        }
    }
    
    struct LockResponse: SMBResponse {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
    }
    
    // MARK: SMB2 IOCTL
    
    /**
     * IOCtl usage is usually limited in SMB to pipe requests and duplicating file inside server
    */
    
    struct IOCtlRequest: SMBRequest {
        let header: Header
        let requestData:  IOCtlRequestProtocol?
        
        init(fileId: FileId ,ctlCode: IOCtlCode, requestData: IOCtlRequestProtocol?, flags: IOCtlRequest.Flags = []) {
            let offset = requestData != nil ? UInt32(sizeof(SMB2.Header.self) + sizeof(IOCtlRequest.Header.self)) : 0
            self.header = Header(size: 57, reserved: 0, _ctlCode: ctlCode.rawValue, fileId: fileId, inputOffset: offset, inputCount: UInt32((requestData?.data().length ?? 0)), maxInputResponse: 0, outputOffset: offset, outputCount: 0, maxOutputResponse: UInt32(Int32.max), flags: flags, reserved2: 0)
            self.requestData = requestData
        }
        
        func data() -> NSData {
            let result = NSMutableData(data: encode(self.header))
            if let reqData = requestData?.data() {
                result.appendData(reqData)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            private let reserved: UInt16
            private let _ctlCode: UInt32
            var ctlCode: IOCtlCode {
                return IOCtlCode(rawValue: _ctlCode)!
            }
            let fileId: FileId
            let inputOffset: UInt32
            let inputCount: UInt32
            let maxInputResponse: UInt32
            let outputOffset: UInt32
            let outputCount: UInt32
            let maxOutputResponse: UInt32
            let flags: IOCtlRequest.Flags
            private let reserved2: UInt32
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let IOCTL = Flags(rawValue: 0x00000000)
            static let FSCTL = Flags(rawValue: 0x00000001)
        }
    }
    
    struct IOCtlResponse: SMBResponse {
        let header: Header
        let responseData:  IOCtlResponseProtocol?
        
        init?(data: NSData) {
            self.header = decode(data)
            let responseRange = NSRange(location: Int(self.header.outputOffset - 64), length: Int(self.header.outputCount))
            let response = data.subdataWithRange(responseRange)
            switch self.header.ctlCode {
            case .SRV_COPYCHUNK, .SRV_COPYCHUNK_WRITE:
                self.responseData = IOCtlResponseData.SrvCopyChunk(data: response)
            case .SRV_ENUMERATE_SNAPSHOTS:
                self.responseData = IOCtlResponseData.SrvSnapshots(data: response)
            case .SRV_REQUEST_RESUME_KEY:
                self.responseData = IOCtlResponseData.ResumeKey(data: response)
            case .SRV_READ_HASH:
                self.responseData = IOCtlResponseData.ReadHash(data: response)
            case .QUERY_NETWORK_INTERFACE_INFO:
                self.responseData = IOCtlResponseData.NetworkInterfaceInfo(data: response)
            case .VALIDATE_NEGOTIATE_INFO:
                self.responseData = IOCtlResponseData.ValidateNegotiateInfo(data: response)
            default:
                self.responseData = nil
            }
        }
        
        struct Header {
            let size: UInt16
            private let reserved: UInt16
            private let _ctlCode: UInt32
            var ctlCode: IOCtlCode {
                return IOCtlCode(rawValue: _ctlCode)!
            }
            let fileId: FileId
            let inputOffset: UInt32
            let inputCount: UInt32
            let outputOffset: UInt32
            let outputCount: UInt32
            private let flags: UInt32
            private let reserved2: UInt32
        }
    }
    
    enum IOCtlCode: UInt32 {
        case DFS_GET_REFERRALS              = 0x00060194
        case DFS_GET_REFERRALS_EX           = 0x000601B0
        case SET_REPARSE_POINT              = 0x000900A4
        case FILE_LEVEL_TRIM                = 0x00098208
        case PIPE_PEEK                      = 0x0011400C
        case PIPE_WAIT                      = 0x00110018
        /// PIPE_TRANSCEIVE is valid only on a named pipe with mode set to FILE_PIPE_MESSAGE_MODE.
        case PIPE_TRANSCEIVE                = 0x0011C017
        /// Get ResumeKey used by the client to uniquely identify the source file in an FSCTL_SRV_COPYCHUNK or FSCTL_SRV_COPYCHUNK_WRITE request.
        case SRV_REQUEST_RESUME_KEY         = 0x00140078
        /// Get all the revision time-stamps that are associated with the Tree Connect share in which the open resides
        case SRV_ENUMERATE_SNAPSHOTS        = 0x00144064
        /// Reads a chunk of file for performing server side copy operations.
        case SRV_COPYCHUNK                  = 0x001440F2
        /// Retrieve data from the Content Information File associated with a specified file, not valid for the SMB 2.0.2 dialect.
        case SRV_READ_HASH                  = 0x001441BB
        /// Writes the chunk of file for performing server side copy operations.
        case SRV_COPYCHUNK_WRITE            = 0x001480F2
        /// Request resiliency for a specified open file, not valid for the SMB 2.0.2 dialect.
        case LMR_REQUEST_RESILIENCY         = 0x001401D4
        /// Get server network interface info e.g. link speed and socket address information
        case QUERY_NETWORK_INTERFACE_INFO   = 0x001401FC
        /// Request validation of a previous SMB 2 NEGOTIATE, valid for SMB 3.0 and SMB 3.0.2 dialects.
        case VALIDATE_NEGOTIATE_INFO        = 0x00140204
    }
    
    struct IOCtlRequestData {
        struct CopyChunk: IOCtlRequestProtocol {
            let sourceKey: (UInt64, UInt64, UInt64)
            let chunkCount: UInt32
            let chunks: [Chunk]
            
            func data() -> NSData {
                let result = NSMutableData(data: encode(sourceKey))
                result.appendData(encode(chunkCount))
                var reserved: UInt32 = 0
                result.appendData(encode(&reserved))
                return NSData()
            }
            
            struct Chunk {
                let sourceOffset: UInt64
                let targetOffset: UInt64
                let length: UInt32
                private let reserved: UInt32
                
                func data() -> NSData {
                    return encode(self)
                }
            }
        }
        
        struct ReadHash: IOCtlRequestProtocol {
            let _hashType: UInt32
            var hashType: IOCtlHashType {
                return IOCtlHashType(rawValue: _hashType) ?? .PEER_DIST
            }
            let _hashVersion: UInt32
            var hashVersion: IOCtlHashVersion {
                return IOCtlHashVersion(rawValue: _hashVersion) ?? .VER_1
            }
            let _hashRetrievalType: UInt32
            var hashRetrievalType: IOCtlHashRetrievalType {
                return IOCtlHashRetrievalType(rawValue: _hashRetrievalType) ?? .FILE_BASED
            }
            let length: UInt32
            let offset: UInt64
            
            init(offset: UInt64, length: UInt32, hashType: IOCtlHashType = .PEER_DIST, hashVersion: IOCtlHashVersion = .VER_1, hashRetrievalType: IOCtlHashRetrievalType = .FILE_BASED) {
                self._hashType = hashType.rawValue
                self._hashVersion = hashVersion.rawValue
                self._hashRetrievalType = hashRetrievalType.rawValue
                self.length = length
                self.offset = offset
            }
            
            func data() -> NSData {
                return encode(self)
            }
        }
        
        struct ResilencyRequest: IOCtlRequestProtocol {
            let timeout: UInt32
            private let reserved: UInt32
            
            /// The requested time the server holds the file open after a disconnect before releasing it. This time is in milliseconds.
            init(timeout: UInt32) {
                self.timeout = timeout
                self.reserved = 0
            }
            
            func data() -> NSData {
                return encode(self)
            }
        }
        
        struct ValidateNegotiateInfo: IOCtlRequestProtocol {
            let header: ValidateNegotiateInfo.Header
            let dialects: [UInt16]
            
            init(dialects: [UInt16], guid: uuid_t, capabilities: IOCtlCapabilities, securityMode: UInt16) {
                self.header = Header(capabilities: capabilities, guid: guid, securityMode: securityMode, dialectCount: UInt16(dialects.count))
                self.dialects = dialects
            }
            
            func data() -> NSData {
                let result = NSMutableData(data: encode(self.header))
                dialects.forEach { result.appendData(encode($0)) }
                return result
            }
            
            struct Header {
                let capabilities: IOCtlCapabilities
                /// Client's GUID
                let guid: uuid_t
                let securityMode: UInt16
                let dialectCount: UInt16
            }
        }
    }
    
    struct IOCtlResponseData {
        // SRV_COPYCHUNK, SRV_COPYCHUNK_WRITE
        struct SrvCopyChunk: IOCtlResponseProtocol {
            let chunksCount: UInt32
            let chunksBytesWritten: UInt32
            let totalBytesWriiten: UInt32
            
            init?(data: NSData) {
                self = decode(data)
            }
        }
        
        // SRV_ENUMERATE_SNAPSHOTS
        struct SrvSnapshots: IOCtlResponseProtocol {
            let count: UInt32
            let snapshots: [SMBTime]
            
            init?(data: NSData) {
                self.count = decode(data)
                let returnedCount: UInt32 = decode(data.subdataWithRange(NSRange(location: 4, length: 4)))
                //let size: UInt32 = decode(data.subdataWithRange(NSRange(location: 8, length: 4)))
                var snapshots = [SMBTime]()
                let dateFormatter = NSDateFormatter()
                dateFormatter.dateFormat = "'@GMT-'yyyy'.'MM'.'dd'-'HH'.'mm'.'ss"
                for i in 0..<Int(returnedCount) {
                    let offset = 24 + i * 48
                    if data.length < offset + 48 {
                        return nil
                    }
                    let datestring = String(data: data.subdataWithRange(NSRange(location: offset, length: 48)), encoding: NSUTF16StringEncoding)
                    if let datestring = datestring, let date = dateFormatter.dateFromString(datestring) {
                        snapshots.append(SMBTime(date: date))
                    }
                }
                self.snapshots = snapshots
            }
        }
        
        struct ResumeKey: IOCtlResponseProtocol {
            let key: (UInt64, UInt64, UInt64)
            private let contextLength: UInt32
            private let context: UInt32
            
            init?(data: NSData) {
                self = decode(data)
            }
        }
        
        struct ReadHash: IOCtlResponseProtocol {
            // TODO: Implement IOCTL READ_HASH
            
            init?(data: NSData) {
                self = decode(data)
            }
        }
        
        struct NetworkInterfaceInfo: IOCtlResponseProtocol {
            let items: [NetworkInterfaceInfo.Item]
            
            init?(data: NSData) {
                let count = data.length / sizeof(Item)
                guard count > 0 else {
                    return nil
                }
                var items = [Item]()
                for i in 0..<count {
                    let itemdata = data.subdataWithRange(NSRange(location: i * sizeof(Item), length: sizeof(Item)))
                    items.append(decode(itemdata))
                }
                self.items = items
            }
            
            struct Item {
                /// The offset, in bytes, from the beginning of this structure to the beginning of a subsequent 8-byte aligned network interface.
                let next: UInt32
                /// specifies the network interface index.
                let ifIndex: UInt32
                let capability: IOCtlCapabilities
                private let reserved: UInt32
                /// Speed of the network interface in bits per second
                let linkSpeed: UInt64
                private let sockaddrStorage:   (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
                var family: sa_family_t {
                    return sockaddrStorage.1
                }
                
                static let ipv4: sa_family_t = 0x02
                static let ipv6: sa_family_t = 0x17
                
                var sockaddr: sockaddr_in {
                    var sockaddrStorage = self.sockaddrStorage
                    let data = NSData(bytes: &sockaddrStorage, length: 16)
                    return decode(data)
                }
                
                var sockaddr6: sockaddr_in6 {
                    var sockaddrStorage = self.sockaddrStorage
                    let data = NSData(bytes: &sockaddrStorage, length: 28)
                    return decode(data)
                }
            }
        }
        
        struct ValidateNegotiateInfo: IOCtlResponseProtocol {
            let capabilities: IOCtlCapabilities
            let guid: uuid_t
            let securityMode: UInt16
            private let _dialect: UInt16
            var dialect: (major: Int, minor: Int) {
                return (major: Int(_dialect & 0xFF), minor: Int(_dialect >> 8))
            }
            
            init?(data: NSData) {
                self = decode(data)
            }
        }
    }
    
    struct IOCtlCapabilities: OptionSetType {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static let RSS_CAPABLE  = IOCtlCapabilities(rawValue: 0x00000001)
        static let RDMA_CAPABLE = IOCtlCapabilities(rawValue: 0x00000002)
    }
    
    enum IOCtlHashType: UInt32 {
        case PEER_DIST = 0x00000001
    }
    
    enum IOCtlHashVersion: UInt32 {
        case VER_1 = 0x00000001
        case VER_2 = 0x00000002
    }
    
    enum IOCtlHashRetrievalType: UInt32 {
        case HASH_BASED = 0x00000001
        case FILE_BASED = 0x00000002
    }
    
    // MARK: SMB2 Cancel
    
    struct CancelRequest: SMBRequest {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
    
    // MARK: SMB2 Echo
    
    struct Echo: SMBRequest, SMBResponse {
        let size: UInt16
        let reserved: UInt16
        
        init() {
            self.size = 4
            self.reserved = 0
        }
        
        init? (data: NSData) {
            self = decode(data)
        }
        
        func data() -> NSData {
            return encode(self)
        }
    }
    
    // MARK: SMB2 Query Directory
    
    // MARK: SMB2 Change Notify
    
    // MARK: SMB2 Query Info
    
    // MARK: SMB2 Set Info
    
    // MARK: SMB2 Oplock Break
    
}
