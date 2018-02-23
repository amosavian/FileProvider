//
//  SMB2QueryTypes.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian on 5/19/95.
//
//

import Foundation

protocol SMB2FilesInformationHeader: SMBResponseBody {
    var nextEntryOffset: UInt32 { get }
    var fileIndex: UInt32 { get }
    var fileNameLength : UInt32 { get }
}

extension SMB2 {
    struct FileInformationEnum: Option {
        let rawValue: UInt8
        
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        public static let none = 0x00
        public static let fileDirectoryInformation = FileInformationEnum(rawValue: 0x01)
        public static let fileFullDirectoryInformation = FileInformationEnum(rawValue: 0x02)
        public static let fileBothDirectoryInformation = FileInformationEnum(rawValue: 0x03)
        public static let fileBasicInformation = FileInformationEnum(rawValue: 0x04)
        public static let fileStandardInformation = FileInformationEnum(rawValue: 0x05)
        public static let fileInternalInformation = FileInformationEnum(rawValue: 0x06)
        public static let fileEaInformation = FileInformationEnum(rawValue: 0x07)
        public static let fileAccessInformation = FileInformationEnum(rawValue: 0x08)
        public static let fileNameInformation = FileInformationEnum(rawValue: 0x09)
        public static let fileRenameInformation = FileInformationEnum(rawValue: 0x0A)
        public static let fileLinkInformation = FileInformationEnum(rawValue: 0x0B)
        public static let fileNamesInformation = FileInformationEnum(rawValue: 0x0C)
        public static let fileDispositionInformation = FileInformationEnum(rawValue: 0x0D)
        public static let filePositionInformation = FileInformationEnum(rawValue: 0x0E)
        public static let fileFullEaInformation = FileInformationEnum(rawValue: 0x0F)
        public static let fileModeInformation = FileInformationEnum(rawValue: 0x10)
        public static let fileAlignmentInformation = FileInformationEnum(rawValue: 0x11)
        public static let fileAllInformation = FileInformationEnum(rawValue: 0x12)
        public static let fileAllocationInformation = FileInformationEnum(rawValue: 0x13)
        public static let fileEndOfFileInformation = FileInformationEnum(rawValue: 0x14)
        public static let fileAlternateNameInformation = FileInformationEnum(rawValue: 0x15)
        public static let fileStreamInformation = FileInformationEnum(rawValue: 0x16)
        public static let filePipeInformation = FileInformationEnum(rawValue: 0x17)
        public static let filePipeLocalInformation = FileInformationEnum(rawValue: 0x18)
        public static let filePipeRemoteInformation = FileInformationEnum(rawValue: 0x19)
        public static let fileMailslotQueryInformation = FileInformationEnum(rawValue: 0x1A)
        public static let fileMailslotSetInformation = FileInformationEnum(rawValue: 0x1B)
        public static let fileCompressionInformation = FileInformationEnum(rawValue: 0x1C)
        public static let fileObjectIdInformation = FileInformationEnum(rawValue: 0x1D)
        public static let fileCompletionInformation = FileInformationEnum(rawValue: 0x1E)
        public static let fileMoveClusterInformation = FileInformationEnum(rawValue: 0x1F)
        public static let fileQuotaInformation = FileInformationEnum(rawValue: 0x20)
        public static let fileReparsePointInformation = FileInformationEnum(rawValue: 0x21)
        public static let fileNetworkOpenInformation = FileInformationEnum(rawValue: 0x22)
        public static let fileAttributeTagInformation = FileInformationEnum(rawValue: 0x23)
        public static let fileTrackingInformation = FileInformationEnum(rawValue: 0x24)
        public static let fileIdBothDirectoryInformation = FileInformationEnum(rawValue: 0x25)
        public static let fileIdFullDirectoryInformation = FileInformationEnum(rawValue: 0x26)
        public static let fileValidDataLengthInformation = FileInformationEnum(rawValue: 0x27)
        public static let fileShortNameInformation = FileInformationEnum(rawValue: 0x28)
        public static let fileIoCompletionNotificationInformation = FileInformationEnum(rawValue: 0x29)
        public static let fileIoStatusBlockRangeInformation = FileInformationEnum(rawValue: 0x2A)
        public static let fileIoPriorityHintInformation = FileInformationEnum(rawValue: 0x2B)
        public static let fileSfioReserveInformation = FileInformationEnum(rawValue: 0x2C)
        public static let fileSfioVolumeInformation = FileInformationEnum(rawValue: 0x2D)
        public static let fileHardLinkInformation = FileInformationEnum(rawValue: 0x2E)
        public static let fileProcessIdsUsingFileInformation = FileInformationEnum(rawValue: 0x2F)
        public static let fileNormalizedNameInformation = FileInformationEnum(rawValue: 0x30)
        public static let fileNetworkPhysicalNameInformation = FileInformationEnum(rawValue: 0x31)
        public static let fileIdGlobalTxDirectoryInformation = FileInformationEnum(rawValue: 0x32)
        public static let fileIsRemoteDeviceInformation = FileInformationEnum(rawValue: 0x33)
        public static let fileUnusedInformation = FileInformationEnum(rawValue: 0x34)
        public static let fileNumaNodeInformation = FileInformationEnum(rawValue: 0x35)
        public static let fileStandardLinkInformation = FileInformationEnum(rawValue: 0x36)
        public static let fileRemoteProtocolInformation = FileInformationEnum(rawValue: 0x37)
        public static let fileRenameInformationBypassAccessCheck = FileInformationEnum(rawValue: 0x38)
        public static let fileLinkInformationBypassAccessCheck = FileInformationEnum(rawValue: 0x39)
        public static let fileVolumeNameInformation = FileInformationEnum(rawValue: 0x3A)
        public static let fileIdInformation = FileInformationEnum(rawValue: 0x3B)
        public static let fileIdExtdDirectoryInformation = FileInformationEnum(rawValue: 0x3C)
        public static let fileReplaceCompletionInformation = FileInformationEnum(rawValue: 0x3D)
        public static let fileHardLinkFullIdInformation = FileInformationEnum(rawValue: 0x3E)
        public static let fileIdExtdBothDirectoryInformation = FileInformationEnum(rawValue: 0x3F)
        public static let fileMaximumInformation = FileInformationEnum(rawValue: 0x40)
        
        static let  queryDirectory: [FileInformationEnum] = [.fileDirectoryInformation, .fileFullDirectoryInformation, .fileIdFullDirectoryInformation, .fileBothDirectoryInformation, .fileIdBothDirectoryInformation, .fileNamesInformation]
        
        static let queryInfoFile: [FileInformationEnum] = [.fileAccessInformation, .fileAlignmentInformation, .fileAllInformation, .fileAlternateNameInformation, .fileAttributeTagInformation, .fileBasicInformation, .fileCompressionInformation, fileEaInformation, .fileFullEaInformation, .fileInternalInformation, .fileModeInformation, .fileNetworkOpenInformation, .filePipeInformation, .filePipeLocalInformation, .filePipeRemoteInformation, .filePositionInformation, .fileStandardInformation, .fileStreamInformation]
    }
    
    struct FileSystemInformationEnum: Option {
        let rawValue: UInt8
        
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        public static let none = FileSystemInformationEnum(rawValue: 0x00)
        public static let fileFsAttributeInformation = FileSystemInformationEnum(rawValue: 0x01)
        public static let fileFsControlInformation = FileSystemInformationEnum(rawValue: 0x02)
        public static let fileFsDeviceInformation = FileSystemInformationEnum(rawValue: 0x03)
        public static let fileFsFullSizeInformation = FileSystemInformationEnum(rawValue: 0x04)
        public static let fileFsObjectIdInformation = FileSystemInformationEnum(rawValue: 0x05)
        public static let fileFsSectorSizeInformation = FileSystemInformationEnum(rawValue: 0x06)
        public static let fileFsSizeInformation = FileSystemInformationEnum(rawValue: 0x07)
        public static let fileFsVolumeInformation = FileSystemInformationEnum(rawValue: 0x08)
    }
    
    struct FileSecurityInfo: OptionSet {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static let OWNER        = FileSecurityInfo(rawValue: 0x00000001)
        static let GROUP        = FileSecurityInfo(rawValue: 0x00000002)
        static let DACL         = FileSecurityInfo(rawValue: 0x00000004)
        static let SACL         = FileSecurityInfo(rawValue: 0x00000008)
        static let LABEL        = FileSecurityInfo(rawValue: 0x00000010)
        static let ATTRIBUTE    = FileSecurityInfo(rawValue: 0x00000020)
        static let SCOPE        = FileSecurityInfo(rawValue: 0x00000040)
        static let BACKUP       = FileSecurityInfo(rawValue: 0x00010000)
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
        fileprivate let reserved: UInt32
        let fileId: FileId
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
        fileprivate let shortNameLen: UInt8
        fileprivate let reserved: UInt8
        fileprivate let _shortName: FileShortNameType
        var shortName: String? {
            var data = Data(value: _shortName)
            data.count = Int(shortNameLen)
            return String(data: data, encoding: .utf16)
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
        fileprivate let shortNameLen: UInt8
        fileprivate let reserved: UInt8
        fileprivate let _shortName: FileShortNameType
        var shortName: String? {
            var data = Data(value: _shortName)
            data.count = Int(shortNameLen)
            return String(data: data, encoding: .utf16)
        }
        fileprivate let reserved2: UInt16
        let fileId : FileId
    }
    
    struct FileNamesInformationHeader: SMB2FilesInformationHeader {
        let nextEntryOffset: UInt32
        let fileIndex: UInt32
        let fileNameLength : UInt32
    }
    
    typealias FileShortNameType = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    
    struct FileAccessInformation {
        let accessMask: FileAccessMask
    }
    
    struct FileAlignmentInformation {
        fileprivate let _alignment: UInt32
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
        fileprivate let reserved: UInt32 = 0
    }
    
    struct FileCompressionInformation {
        let compressedFileSize: Int64
        let compressionFormat: UInt16
        static let COMPRESSION_FORMAT_LZNT1 = 0x0002
        let compressionUnitShift: UInt8
        let chunkShift: UInt8
        let clusterShift: UInt8
        fileprivate let reserved: (UInt8, UInt16)
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
        
        struct Mode: OptionSet {
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
        fileprivate let reserved: UInt32
    }
    
    struct FilePipeInformation {
        let readMode: ReadMode
        fileprivate let completionMode: CompletionMode
        
        struct ReadMode: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let BYTE_STREAM_MODE   = ReadMode(rawValue: 0x00000000)
            public static let MESSAGE_MODE       = ReadMode(rawValue: 0x00000001)
        }
        
        struct CompletionMode: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let QUEUE_OPERATION    = CompletionMode(rawValue: 0x00000000)
            public static let COMPLETE_OPERATION = CompletionMode(rawValue: 0x00000001)
        }
    }
    
    struct FilePipeLocalInformation {
        let namedPipeType: Type
        let namedPipeConfiguration: Configuration
        let maximumInstances: UInt32
        let currentInstances: UInt32
        let inboundQuota: UInt32
        let readDataAvailable: UInt32
        let outboundQuota: UInt32
        let writeQuotaAvailable: UInt32
        let namedPipeState: State
        let namedPipeEnd: End
        
        struct `Type`: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let BYTE_STREAM_TYPE   = `Type`(rawValue: 0x00000000)
            public static let MESSAGE_TYPE       = `Type`(rawValue: 0x00000001)
        }
        
        struct Configuration: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let INBOUND        = Configuration(rawValue: 0x00000000)
            public static let OUTBOUND       = Configuration(rawValue: 0x00000001)
            public static let FULL_DUPLEX    = Configuration(rawValue: 0x00000002)
        }
        
        struct State: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let DISCONNECTED_STATE = State(rawValue: 0x00000001)
            public static let LISTENING_STATE    = State(rawValue: 0x00000002)
            public static let CONNECTED_STATE    = State(rawValue: 0x00000003)
            public static let CLOSING_STATE      = State(rawValue: 0x00000004)
        }
        
        struct End: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let CLIENT_END = End(rawValue: 0x00000000)
            public static let SERVER_END = End(rawValue: 0x00000001)
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
        fileprivate let reserved: UInt16
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
        let deviceType: DeviceType
        let charactristics: Charactristics
        
        struct DeviceType: Option {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            public static let CD_ROM = DeviceType(rawValue: 0x00000002)
            public static let DISK   = DeviceType(rawValue: 0x00000007)
        }
        
        struct Charactristics: OptionSet {
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
        
        struct Attributes: OptionSet {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            /// The file system supports case-sensitive file names when looking up (searching for) file names in a directory.
            static let CASE_SENSITIVE_SEARCH = Attributes(rawValue: 0x00000001)
            /// The file system preserves the public static let of file names when it places a name on disk.
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
        fileprivate let padding: UInt32 = 0
        
        struct Flags: OptionSet {
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
        
        struct Flags: OptionSet {
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
