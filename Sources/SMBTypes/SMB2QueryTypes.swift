//
//  SMB2QueryTypes.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian on 5/19/95.
//
//

import Foundation

protocol SMB2FilesInformationHeader: SMBResponse {
    var nextEntryOffset: UInt32 { get }
    var fileIndex: UInt32 { get }
    var fileNameLength : UInt32 { get }
}

extension SMB2 {
    enum FileInformationEnum: UInt8 {
        case Nil = 0x00
        case FileDirectoryInformation = 0x01
        case FileFullDirectoryInformation = 0x02
        case FileBothDirectoryInformation = 0x03
        case FileBasicInformation = 0x04
        case FileStandardInformation = 0x05
        case FileInternalInformation = 0x06
        case FileEaInformation = 0x07
        case FileAccessInformation = 0x08
        case FileNameInformation = 0x09
        case FileRenameInformation = 0x0A
        case FileLinkInformation = 0x0B
        case FileNamesInformation = 0x0C
        case FileDispositionInformation = 0x0D
        case FilePositionInformation = 0x0E
        case FileFullEaInformation = 0x0F
        case FileModeInformation = 0x10
        case FileAlignmentInformation = 0x11
        case FileAllInformation = 0x12
        case FileAllocationInformation = 0x13
        case FileEndOfFileInformation = 0x14
        case FileAlternateNameInformation = 0x15
        case FileStreamInformation = 0x16
        case FilePipeInformation = 0x17
        case FilePipeLocalInformation = 0x18
        case FilePipeRemoteInformation = 0x19
        case FileMailslotQueryInformation = 0x1A
        case FileMailslotSetInformation = 0x1B
        case FileCompressionInformation = 0x1C
        case FileObjectIdInformation = 0x1D
        case FileCompletionInformation = 0x1E
        case FileMoveClusterInformation = 0x1F
        case FileQuotaInformation = 0x20
        case FileReparsePointInformation = 0x21
        case FileNetworkOpenInformation = 0x22
        case FileAttributeTagInformation = 0x23
        case FileTrackingInformation = 0x24
        case FileIdBothDirectoryInformation = 0x25
        case FileIdFullDirectoryInformation = 0x26
        case FileValidDataLengthInformation = 0x27
        case FileShortNameInformation = 0x28
        case FileIoCompletionNotificationInformation = 0x29
        case FileIoStatusBlockRangeInformation = 0x2A
        case FileIoPriorityHintInformation = 0x2B
        case FileSfioReserveInformation = 0x2C
        case FileSfioVolumeInformation = 0x2D
        case FileHardLinkInformation = 0x2E
        case FileProcessIdsUsingFileInformation = 0x2F
        case FileNormalizedNameInformation = 0x30
        case FileNetworkPhysicalNameInformation = 0x31
        case FileIdGlobalTxDirectoryInformation = 0x32
        case FileIsRemoteDeviceInformation = 0x33
        case FileUnusedInformation = 0x34
        case FileNumaNodeInformation = 0x35
        case FileStandardLinkInformation = 0x36
        case FileRemoteProtocolInformation = 0x37
        case FileRenameInformationBypassAccessCheck = 0x38
        case FileLinkInformationBypassAccessCheck = 0x39
        case FileVolumeNameInformation = 0x3A
        case FileIdInformation = 0x3B
        case FileIdExtdDirectoryInformation = 0x3C
        case FileReplaceCompletionInformation = 0x3D
        case FileHardLinkFullIdInformation = 0x3E
        case FileIdExtdBothDirectoryInformation = 0x3F
        case FileMaximumInformation = 0x40
        
        static let  queryDirectory: [FileInformationEnum] = [.FileDirectoryInformation, .FileFullDirectoryInformation, .FileIdFullDirectoryInformation, .FileBothDirectoryInformation, .FileIdBothDirectoryInformation, .FileNamesInformation]
        
        static let queryInfoFile: [FileInformationEnum] = [.FileAccessInformation, .FileAlignmentInformation, .FileAllInformation, .FileAlternateNameInformation, .FileAttributeTagInformation, .FileBasicInformation, .FileCompressionInformation, FileEaInformation, .FileFullEaInformation, .FileInternalInformation, .FileModeInformation, .FileNetworkOpenInformation, .FilePipeInformation, .FilePipeLocalInformation, .FilePipeRemoteInformation, .FilePositionInformation, .FileStandardInformation, .FileStreamInformation]
    }
    
    enum FileSystemInformationEnum: UInt8 {
        case Nil = 0
        case FileFsAttributeInformation
        case FileFsControlInformation
        case FileFsDeviceInformation
        case FileFsFullSizeInformation
        case FileFsObjectIdInformation
        case FileFsSectorSizeInformation
        case FileFsSizeInformation
        case FileFsVolumeInformation
    }
    
    struct FileDirectoryInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileSize: UInt64
        let allocationSize: UInt64
        let fileAttributes: FileAttributes
        let fileNameLength : UInt32
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    struct FileFullDirectoryInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileSize: UInt64
        let allocationSize: UInt64
        let fileAttributes: FileAttributes
        let fileNameLength : UInt32
        let extendedAttributesSize: UInt32
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    struct FileIdFullDirectoryInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileSize: UInt64
        let allocationSize: UInt64
        let fileAttributes: FileAttributes
        let fileNameLength : UInt32
        let extendedAttributesSize: UInt32
        private let reserved: UInt32
        let fileId: FileId
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    struct FileBothDirectoryInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileSize: UInt64
        let allocationSize: UInt64
        let fileAttributes: FileAttributes
        let fileNameLength : UInt32
        let extendedAttributesSize: UInt32
        private let shortNameLen: UInt8
        private let reserved: UInt8
        private let _shortName: FileShortNameType
        var shortName: String? {
            let s = encode(_shortName)
            let d = NSMutableData(data: s)
            d.length = Int(shortNameLen)
            return String(data: d, encoding: NSUTF16StringEncoding)
        }
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    struct FileIdBothDirectoryInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileSize: Int64
        let allocationSize: Int64
        let fileAttributes: FileAttributes
        let fileNameLength : UInt32
        let extendedAttributesSize: UInt32
        private let shortNameLen: UInt8
        private let reserved: UInt8
        private let _shortName: FileShortNameType
        var shortName: String? {
            let s = encode(_shortName)
            let d = NSMutableData(data: s)
            d.length = Int(shortNameLen)
            return String(data: d, encoding: NSUTF16StringEncoding)
        }
        private let reserved2: UInt16
        let fileId : FileId
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    struct FileNamesInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let fileNameLength : UInt32
        
        init?(data: NSData) {
            self = decode(data)
        }
    }
    
    typealias FileShortNameType = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    
    struct FileAccessInformation {
        let accessMask: FileAccessMask
    }
    
    struct FileAlignmentInformation {
        private let _alignment: UInt32
        var alignmentLength: UInt32 {
            return _alignment + 1
        }
    }
    
    struct FileAllInformationHeader {
        let basic: FileBasicInformation
        let standard: FileStandardInformation
        let `internal`: FileInternalInformation
        let ea: FileEaInformation
        let access: FileAccessInformation
        let position: FilePositionInformation
        let mode: FileModeInformation
        let alignment: FileAlignmentInformation
        let nameLength: UInt32
    }
        
    struct FileAttributeTagInformation {
        let fileAttributes: FileAttributes
        let reparseTag: UInt32
    }
    
    struct FileBasicInformation {
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileAttributes: FileAttributes
        private let reserved: UInt32 = 0
    }
    
    struct FileCompressionInformation {
        let compressedFileSize: Int64
        let compressionFormat: UInt16
        static let COMPRESSION_FORMAT_LZNT1 = 0x0002
        let compressionUnitShift: UInt8
        let chunkShift: UInt8
        let clusterShift: UInt8
        private let reserved: (UInt8, UInt16)
    }
    
    struct FileEaInformation {
        let eaSize: UInt32
    }
    
    struct FileFullEaInformation {
        // TODO
    }
    
    struct FileInternalInformation {
        let indexNumber: UInt64
    }
    
    struct FileModeInformation {
        let mode: Mode
        
        struct Mode: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let FILE_WRITE_THROUGH               = Mode(rawValue: 0x00000002)
            static let FILE_SEQUENTIAL_ONLY             = Mode(rawValue: 0x00000004)
            static let FILE_NO_INTERMEDIATE_BUFFERING   = Mode(rawValue: 0x00000008)
            static let FILE_SYNCHRONOUS_IO_ALERT        = Mode(rawValue: 0x00000010)
            static let FILE_SYNCHRONOUS_IO_NONALERT     = Mode(rawValue: 0x00000020)
            static let FILE_DELETE_ON_CLOSE             = Mode(rawValue: 0x00001000)
        }
    }
    
    struct FileNetworkOpenInformation {
        let creationTime: SMBTime
        let lastAccesTime: SMBTime
        let lastWriteTime: SMBTime
        let changeTime: SMBTime
        let fileAttributes: FileAttributes
        private let reserved: UInt32
    }
    
    struct FilePipeInformation {
        private let _readMode: UInt32
        var readMode: ReadMode {
            return ReadMode(rawValue: _readMode) ?? .BYTE_STREAM_MODE
        }
        private let _completionMode: UInt32
        var completionMode: CompletionMode {
            return CompletionMode(rawValue: _completionMode) ?? .QUEUE_OPERATION
        }
        
        enum ReadMode: UInt32 {
            case BYTE_STREAM_MODE   = 0x00000000
            case MESSAGE_MODE       = 0x00000001
        }
        
        enum CompletionMode: UInt32 {
            case QUEUE_OPERATION    = 0x00000000
            case COMPLETE_OPERATION = 0x00000001
        }
    }
    
    struct FilePipeLocalInformation {
        private let _namedPipeType: UInt32
        var namedPipeType: Type {
            return Type(rawValue: _namedPipeType) ?? .BYTE_STREAM_TYPE
        }
        private let _namedPipeConfiguration: UInt32
        var namedPipeConfiguration: Configuration {
            return Configuration(rawValue: _namedPipeConfiguration) ?? .INBOUND
        }
        let maximumInstances: UInt32
        let currentInstances: UInt32
        let inboundQuota: UInt32
        let readDataAvailable: UInt32
        let outboundQuota: UInt32
        let writeQuotaAvailable: UInt32
        private let _namedPipeState: UInt32
        var namedPipeState: State {
            return State(rawValue: _namedPipeState) ?? .DISCONNECTED_STATE
        }
        private let _namedPipeEnd: UInt32
        var namedPipeEnd: End {
            return End(rawValue: _namedPipeEnd) ?? .CLIENT_END
        }
        
        enum Type: UInt32 {
            case BYTE_STREAM_TYPE   = 0x00000000
            case MESSAGE_TYPE       = 0x00000001
        }
        
        enum Configuration: UInt32 {
            case INBOUND        = 0x00000000
            case OUTBOUND       = 0x00000001
            case FULL_DUPLEX    = 0x00000002
        }
        
        enum State: UInt32 {
            case DISCONNECTED_STATE = 0x00000001
            case LISTENING_STATE    = 0x00000002
            case CONNECTED_STATE    = 0x00000003
            case CLOSING_STATE      = 0x00000004
        }
        
        enum End: UInt32 {
            case CLIENT_END = 0x00000000
            case SERVER_END = 0x00000001
        }
    }
    
    struct FilePipeRemoteInformation {
        let collectDataTime: SMBTime
        let maximumCollectionCount: UInt32
    }
    
    struct FilePositionInformation {
        let currentByteOffset: Int64
    }
    
    struct FileStandardInformation {
        let allocationSize: Int64
        let fileSize: Int64
        let numberOfLinks: UInt32
        let deletePending: Bool
        let directory: Bool
        private let reserved: UInt16
    }
    
    struct FileStreamInformationHeader {
        let nextEntryOffset: UInt32
        let streamNameLength: UInt32
        let streamSize: Int64
        let streamAllocationSize: Int64
    }
    
    struct FileFsVolumeInformationHeader {
        let creationTime: SMBTime
        let serial: UInt32
        let labelLength: UInt32
        let supportObjects: Bool
        let reserved: UInt8
    }
    
    struct FileFsSizeInformation {
        let totalAllocationUnits: Int64
        let availableAllocationUnits: Int64
        let sectorsPerAllocationUnit: UInt32
        let bytesPerSector: UInt32
    }
    
    struct FileFsDeviceInformation {
        private let _deviceType: UInt32
        var deviceType: DeviceType {
            return DeviceType(rawValue: _deviceType) ?? .DISK
        }
        let charactristics: Charactristics
        
        enum DeviceType: UInt32 {
            case CD_ROM = 0x00000002
            case DISK = 0x00000007
        }
        
        struct Charactristics: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            /// Storage device supports removable media. For example, drivers for JAZ drive devices specify this characteristic, but drivers for PCMCIA flash disks do not.
            static let REMOVABLE_MEDIA  = Charactristics(rawValue: 0x00000001)
            /// Indicates that the device cannot be written to.
            static let READ_ONLY_DEVICE = Charactristics(rawValue: 0x00000002)
            /// Indicates that the device is a floppy disk device.
            static let FLOPPY_DISKETTE = Charactristics(rawValue: 0x00000004)
            /// Indicates that the device supports write-once media.
            static let WRITE_ONCE_MEDIA = Charactristics(rawValue: 0x00000008)
            /// ndicates that the volume is for a remote file system like SMB or CIFS.
            static let REMOTE_DEVICE  = Charactristics(rawValue: 0x00000010)
            /// Indicates that a file system is mounted on the device.
            static let DEVICE_IS_MOUNTED = Charactristics(rawValue: 0x00000020)
            /// Indicates that the volume does not directly reside on storage media, but resides on some other type of media (memory for example).
            static let VIRTUAL_VOLUME = Charactristics(rawValue: 0x00000040)
            /// By default, volumes do not check the ACL associated with the volume, but instead use the ACLs associated with individual files on the volume. When this flag is set the volume ACL is also checked.
            static let DEVICE_SECURE_OPEN = Charactristics(rawValue: 0x00000100)
            /// Indicates that the device object is part of a Terminal Services device stack.
            static let TS_DEVICE = Charactristics(rawValue: 0x00001000)
            /// ndicates that a web-based Distributed Authoring and Versioning (WebDAV) file system is mounted on the device.
            static let WEBDAV_DEVICE = Charactristics(rawValue: 0x00002000)
            /// The IO Manager normally performs a full security check for traverse access on every file open when the client is an appcontainer.  Setting of this flag bypasses this enforced traverse access check if the client token already has traverse privileges.
            static let PORTABLE_DEVICE = Charactristics(rawValue: 0x0004000)
            /// Indicates that the given device resides on a portable bus like USB or Firewire and that the entire device (not just the media) can be removed from the system.
            static let DEVICE_ALLOW_APPCONTAINER_TRAVERSAL = Charactristics(rawValue: 0x00020000)
        }
    }
    
    struct FileFsAttributeInformationHeader {
        let attributes: Attributes
        let maximumFileNameLength: Int32
        let nameLength: UInt32
        
        struct Attributes: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            /// The file system supports case-sensitive file names when looking up (searching for) file names in a directory.
            static let CASE_SENSITIVE_SEARCH = Attributes(rawValue: 0x00000001)
            /// The file system preserves the case of file names when it places a name on disk.
            static let CASE_PRESERVED_NAMES = Attributes(rawValue: 0x00000002)
            /// The file system supports Unicode in file and directory names. This flag applies only to file and directory names; the file system neither restricts nor interprets the bytes of data within a file.
            static let UNICODE_ON_DISK = Attributes(rawValue: 0x00000004)
            /// The file system preserves and enforces access control lists (ACLs).
            static let PERSISTENT_ACLS = Attributes(rawValue: 0x00000008)
            /// The file volume supports file-based compression. This flag is incompatible with the FILE_VOLUME_IS_COMPRESSED flag.
            static let FILE_COMPRESSION = Attributes(rawValue: 0x00000010)
            /// The file system supports per-user quotas.
            static let VOLUME_QUOTAS = Attributes(rawValue: 0x00000020)
            /// The file system supports sparse files.
            static let SUPPORTS_SPARSE_FILES = Attributes(rawValue: 0x00000040)
            /// The file system supports reparse points.
            static let SUPPORTS_REPARSE_POINTS = Attributes(rawValue: 0x00000080)
            /// The file system supports remote storage.
            static let REMOTE_STORAGE = Attributes(rawValue: 0x00000100)
            /// The specified volume is a compressed volume. This flag is incompatible with the FILE_FILE_COMPRESSION flag.
            static let IS_COMPRESSED = Attributes(rawValue: 0x00008000)
            /// The file system supports object identifiers.
            static let OBJECT_IDS = Attributes(rawValue: 0x00010000)
            /// The file system supports the Encrypted File System (EFS).
            static let ENCRYPTION = Attributes(rawValue: 0x00020000)
            /// The file system supports named streams. (aka. Resource Fork on MacOS)
            static let NAMED_STREAMS = Attributes(rawValue: 0x00040000)
            /// If set, the volume has been mounted in read-only mode.
            static let READ_ONLY_VOLUME = Attributes(rawValue: 0x00080000)
            /// The underlying volume is write once. (aka tapes)
            static let SEQUENTIAL_WRITE_ONCE = Attributes(rawValue: 0x00100000)
            /// The volume supports transactions.
            static let SUPPORTS_TRANSACTIONS = Attributes(rawValue: 0x00200000)
            /// The file system supports hard linking files.
            static let SUPPORTS_HARD_LINKS = Attributes(rawValue: 0x00400000)
            /// The file system persistently stores Extended Attribute information per file.
            static let SUPPORTS_EXTENDED_ATTRIBUTES = Attributes(rawValue: 0x00800000)
            /// The file system supports opening a file by FileID or ObjectID.
            static let SUPPORTS_OPEN_BY_FILE_ID = Attributes(rawValue: 0x01000000)
            /// The file system implements a USN change journal.
            static let USN_JOURNAL = Attributes(rawValue: 0x02000000)
            /// The file system supports integrity streams.
            static let SUPPORT_INTEGRITY_STREAMS = Attributes(rawValue: 0x04000000)
            /// The file system supports sharing logical clusters between files on the same volume. The file system reallocates on writes to shared clusters. Indicates that FSCTL_DUPLICATE_EXTENTS_TO_FILE is a supported operation.
            static let SUPPORTS_BLOCK_REFCOUNTING = Attributes(rawValue: 0x08000000)
            /// The file system tracks whether each cluster of a file contains valid data (either from explicit file writes or automatic zeros) or invalid data (has not yet been written to or zeroed).
            static let SUPPORTS_SPARSE_VDL = Attributes(rawValue: 0x10000000)
        }
    }
    
    struct FileFsControlInformation {
        let freeSpaceStartFiltering: Int64
        let freeSpaceThreshold: Int64
        let freeSpaceStopFiltering: Int64
        let defaultQuotaThreshold: UInt64
        let defaultQuotaLimit: UInt64
        let flags: Flags
        private let padding: UInt32 = 0
        
        struct Flags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            /// Quotas are tracked on the volume, but they are not enforced. Tracked quotas enable reporting on the file system space used by system users. If both this flag and FILE_VC_QUOTA_ENFORCE are specified, FILE_VC_QUOTA_ENFORCE is ignored.
            static let QUOTA_TRACK = Flags(rawValue: 0x00000001)
            /// Quotas are tracked and enforced on the volume.
            static let QUOTA_ENFORCE = Flags(rawValue: 0x00000002)
            /// Content indexing is disabled.
            static let CONTENT_INDEX_DISABLED = Flags(rawValue: 0x00000008)
            /// An event log entry will be created when the user exceeds his or her assigned quota warning threshold.
            static let LOG_QUOTA_THRESHOLD = Flags(rawValue: 0x00000010)
            /// An event log entry will be created when the user exceeds the assigned disk quota limit.
            static let LOG_QUOTA_LIMIT = Flags(rawValue: 0x00000020)
            /// An event log entry will be created when the volume's free space threshold is exceeded.
            static let LOG_VOLUME_THRESHOLD = Flags(rawValue: 0x00000040)
            /// An event log entry will be created when the volume's free space limit is exceeded.
            static let LOG_VOLUME_LIMIT = Flags(rawValue: 0x00000080)
            /// The quota information for the volume is incomplete because it is corrupt, or the system is in the process of rebuilding the quota information.
            static let QUOTAS_INCOMPLETE = Flags(rawValue: 0x00000100)
            /// The file system is rebuilding the quota information for the volume.
            static let QUOTAS_REBUILDING = Flags(rawValue: 0x00000200)
        }
    }
    
    struct FileFsFullSizeInformation {
        let totalAllocationUnits: Int64
        let callerAvailableAllocationUnits: Int64
        let actualAvailableAllocationUnits: Int64
        let sectorsPerAllocationUnit: UInt32
        let bytesPerSector: UInt32
    }
    
    struct FileFsObjectIdInformation {
        let objectId: uuid_t
        let extendedInfo: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)
    }
    
    struct FileFsSectorSizeInformation {
        let logicalBytesPerSector: UInt32
        let physicalBytesPerSectorForAtomicity: UInt32
        let physicalBytesPerSectorForPerformance: UInt32
        let effectivePhysicalBytesPerSectorForAtomicity: UInt32
        let flags: Flags
        let byteOffsetForSectorAlignment: UInt32
        let byteOffsetForPartitionAlignment: UInt32
        
        struct Flags: OptionSetType {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            /// When set, this flag indicates that the first physical sector of the device is aligned with the first logical sector. When not set, the first physical sector of the device is misaligned with the first logical sector.
            static let ALIGNED_DEVICE = Flags(rawValue: 0x00000001)
            /// When set, this flag indicates that the partition is aligned to physical sector boundaries on the storage device.
            static let PARTITION_ALIGNED_ON_DEVICE = Flags(rawValue: 0x00000002)
            /// When set, the device reports that it does not incur a seek penalty (this typically indicates that the device does not have rotating media, such as flash-based disks).
            static let NO_SEEK_PENALTY = Flags(rawValue: 0x00000008)
            /// When set, the device supports TRIM operations, either T13 (ATA) TRIM or T10 (SCSI/SAS) UNMAP.
            static let TRIM_ENABLED = Flags(rawValue: 0x00000010)
        }
    }
}