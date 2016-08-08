//
//  SMB2Query.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/31/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

extension SMB2 {
    // MARK: SMB2 Query Directory
    
    struct QueryDirectoryRequest: SMBRequest {
        let header: QueryDirectoryRequest.Header
        let searchPattern: String?
        
        /// - **bufferLength:** maximum number of bytes the server is allowed to return which is the same as maxTransactSize returned by negotiation.
        /// - **searchPattern:** can hold wildcards or be nil if all entries should be returned.
        /// - **fileIndex:** The byte offset within the directory, indicating the position at which to resume the enumeration.
        init(fileId: FileId, infoClass: FileInformationClass, flags: Flags, bufferLength: UInt32 = 65535, searchPattern: String? = nil, fileIndex: UInt32 = 0) {
            assert(FileInformationClass.queryDirectory.contains(infoClass), "Invalid FileInformationClass used for QueryDirectoryRequest")
            let searchPatternOffset = searchPattern != nil ? sizeof(SMB2.Header.self) + sizeof(QueryDirectoryRequest.Header.self) : 0
            let nflags = flags.intersect(fileIndex > 0 ? [.INDEX_SPECIFIED] : [])
            let searchPatternLength = searchPattern?.dataUsingEncoding(NSUTF16StringEncoding)?.length ?? 0
            self.header = Header(size: 53, infoClass: infoClass, flags: nflags, fileIndex: fileIndex, fileId: fileId, searchPatternOffset: UInt8(searchPatternOffset), searchPatternLength: UInt8(searchPatternLength), bufferLength: bufferLength)
            self.searchPattern = searchPattern
        }
        
        func data() -> NSData {
            let result = NSMutableData(data: encode(header))
            if let patternData = searchPattern?.dataUsingEncoding(NSUTF16StringEncoding) {
                result.appendData(patternData)
            }
            return result
        }
        
        struct Header {
            let size: UInt8
            let infoClass: FileInformationClass
            let flags: QueryDirectoryRequest.Flags
            let fileIndex: UInt32
            let fileId: FileId
            let searchPatternOffset: UInt8
            let searchPatternLength: UInt8
            let bufferLength: UInt32
        }
        
        struct Flags: OptionSetType {
            let rawValue: UInt8
            
            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            static let RESTART_SCANS = Flags(rawValue: 0x01)
            static let RETURN_SINGLE_ENTRY = Flags(rawValue: 0x02)
            static let INDEX_SPECIFIED = Flags(rawValue: 0x04)
            static let REOPEN = Flags(rawValue: 0x10)
        }
    }
    
    struct QueryDirectoryResponse: SMBResponse {
        let buffer: NSData
        
        func parseAs(type type: FileInformationClass) -> [(header: SMB2FilesInformationHeader, fileName: String)] {
            var offset = 0
            var result = [(header: SMB2FilesInformationHeader, fileName: String)]()
            while true {
                let header: SMB2FilesInformationHeader
                switch type {
                case .FileDirectoryInformation:
                    let headerData = buffer.subdataWithRange(NSRange(location: offset, length: sizeof(FileDirectoryInformationHeader)))
                    let h: FileDirectoryInformationHeader = decode(headerData)
                    header = h
                case .FileFullDirectoryInformation:
                    let headerData = buffer.subdataWithRange(NSRange(location: offset, length: sizeof(FileFullDirectoryInformationHeader)))
                    let h: FileFullDirectoryInformationHeader = decode(headerData)
                    header = h
                case .FileIdFullDirectoryInformation:
                    let headerData = buffer.subdataWithRange(NSRange(location: offset, length: sizeof(FileIdFullDirectoryInformationHeader)))
                    let h: FileIdFullDirectoryInformationHeader = decode(headerData)
                    header = h
                case .FileBothDirectoryInformation:
                    let headerData = buffer.subdataWithRange(NSRange(location: offset, length: sizeof(FileBothDirectoryInformationHeader)))
                    let h: FileBothDirectoryInformationHeader = decode(headerData)
                    header = h
                case .FileIdBothDirectoryInformation:
                    let headerData = buffer.subdataWithRange(NSRange(location: offset, length: sizeof(FileIdBothDirectoryInformationHeader)))
                    let h: FileIdBothDirectoryInformationHeader = decode(headerData)
                    header = h
                case .FileNamesInformation:
                    let headerData = buffer.subdataWithRange(NSRange(location: offset, length: sizeof(FileNamesInformationHeader)))
                    let h: FileNamesInformationHeader = decode(headerData)
                    header = h
                default:
                    return []
                }
                let fnData = buffer.subdataWithRange(NSRange(location: offset + sizeofValue(header), length: Int(header.fileNameLength)))
                let fileName = String(data: fnData, usingEncoding: NSUTF16StringEncoding)
                result.append((header: header, fileName: fileName))
                if header.nextEntryOffset == 0 {
                    break
                }
                offset += Int(header.nextEntryOffset)
            }
            return result
        }
        
        init? (data: NSData) {
            let offset: UInt16 = decode(data.subdataWithRange(NSRange(location: 2, length: 2)))
            let length: UInt32 = decode(data.subdataWithRange(NSRange(location: 4, length: 4)))
            guard data.length > Int(offset) + Int(length) else {
                return nil
            }
            self.buffer = data.subdataWithRange(NSRange(location: Int(offset), length: Int(length)))
        }
    }
    
    enum FileInformationClass: UInt8 {
        /// For security queries & quota queries
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
        
        static let  queryDirectory: [FileInformationClass] = [.FileDirectoryInformation, .FileFullDirectoryInformation, .FileIdFullDirectoryInformation, .FileBothDirectoryInformation, .FileIdBothDirectoryInformation, .FileNamesInformation]
        
        static let queryInfoFile: [FileInformationClass] = [.FileAccessInformation, .FileAlignmentInformation, .FileAllInformation, .FileAlternateNameInformation, .FileAttributeTagInformation, .FileBasicInformation, .FileCompressionInformation, FileEaInformation, .FileFullEaInformation, .FileInternalInformation, .FileModeInformation, .FileNetworkOpenInformation, .FilePipeInformation, .FilePipeLocalInformation, .FilePipeRemoteInformation, .FilePositionInformation, .FileStandardInformation, .FileStreamInformation]
        
        //static let queryInfoFile: [FileInformationClass] = [.FileFsAttributeInformation, .FileFsControlInformation, .FileFsDeviceInformation, .FileFsFullSizeInformation, .FileFsObjectIdInformation, .FileFsSectorSizeInformation, .FileFsSizeInformation, .FileFsVolumeInformation]
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
    
    // MARK: SMB2 Change Notify
    
    // MARK: SMB2 Query Info
    
}