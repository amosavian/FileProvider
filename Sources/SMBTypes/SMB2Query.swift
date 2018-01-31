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
    
    struct QueryDirectoryRequest: SMBRequestBody {
        static let command: SMB2.Command = .QUERY_DIRECTORY
        
        let header: QueryDirectoryRequest.Header
        let searchPattern: String?
        
        /// - **bufferLength:** maximum number of bytes the server is allowed to return which is the same as maxTransactSize returned by negotiation.
        /// - **searchPattern:** can hold wildcards or be nil if all entries should be returned.
        /// - **fileIndex:** The byte offset within the directory, indicating the position at which to resume the enumeration.
        init(fileId: FileId, infoClass: FileInformationEnum, flags: Flags, bufferLength: UInt32 = 65535, searchPattern: String? = nil, fileIndex: UInt32 = 0) {
            assert(FileInformationEnum.queryDirectory.contains(infoClass), "Invalid FileInformationClass used for QueryDirectoryRequest")
            let searchPatternOffset = searchPattern != nil ? MemoryLayout<SMB2.Header>.size + MemoryLayout<QueryDirectoryRequest.Header>.size : 0
            let nflags = flags.intersection(fileIndex > 0 ? [.INDEX_SPECIFIED] : [])
            let searchPatternLength = searchPattern?.data(using: .utf16)?.count ?? 0
            self.header = Header(size: 53, infoClass: infoClass, flags: nflags, fileIndex: fileIndex, fileId: fileId, searchPatternOffset: UInt8(searchPatternOffset), searchPatternLength: UInt8(searchPatternLength), bufferLength: bufferLength)
            self.searchPattern = searchPattern
        }
        
        func data() -> Data {
            var result = Data(value: header)
            if let patternData = searchPattern?.data(using: .utf16) {
                result.append(patternData)
            }
            return result
        }
        
        struct Header {
            let size: UInt8
            let infoClass: FileInformationEnum
            let flags: QueryDirectoryRequest.Flags
            let fileIndex: UInt32
            let fileId: FileId
            let searchPatternOffset: UInt8
            let searchPatternLength: UInt8
            let bufferLength: UInt32
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt8
            
            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
            
            static let RESTART_SCANS        = Flags(rawValue: 0x01)
            static let RETURN_SINGLE_ENTRY  = Flags(rawValue: 0x02)
            static let INDEX_SPECIFIED      = Flags(rawValue: 0x04)
            static let REOPEN               = Flags(rawValue: 0x10)
        }
    }
    
    struct QueryDirectoryResponse: SMBResponseBody {
        let buffer: Data
        
        func parseAs(type: FileInformationEnum) -> [(header: SMB2FilesInformationHeader, fileName: String)] {
            var offset = 0
            var result = [(header: SMB2FilesInformationHeader, fileName: String)]()
            while true {
                let header: SMB2FilesInformationHeader
                switch type {
                case .fileDirectoryInformation:
                    header = buffer.scanValue(start: offset) as FileDirectoryInformationHeader!
                case .fileFullDirectoryInformation:
                    header = buffer.scanValue(start: offset) as FileFullDirectoryInformationHeader!
                case .fileIdFullDirectoryInformation:
                    header = buffer.scanValue(start: offset) as FileIdFullDirectoryInformationHeader!
                case .fileBothDirectoryInformation:
                    header = buffer.scanValue(start: offset) as FileBothDirectoryInformationHeader!
                case .fileIdBothDirectoryInformation:
                    header = buffer.scanValue(start: offset) as FileIdBothDirectoryInformationHeader!
                case .fileNamesInformation:
                    header = buffer.scanValue(start: offset) as FileNamesInformationHeader!
                default:
                    return []
                }
                let headersize = MemoryLayout.size(ofValue: header)
                let fileName = buffer.scanString(start: headersize, length: Int(header.fileNameLength), using: .utf16) ?? ""
                result.append((header: header, fileName: fileName))
                if header.nextEntryOffset == 0 {
                    break
                }
                offset += Int(header.nextEntryOffset)
            }
            return result
        }
        
        init? (data: Data) {
            let offset = Int(data.scanValue(start: 2) as UInt16!)
            let length = Int(data.scanValue(start: 4) as UInt32!)
            guard data.count > offset + length else {
                return nil
            }
            self.buffer = data.subdata(in: offset..<(offset + length))
        }
    }
    
    // MARK: SMB2 Query Info
    
    struct QueryInfoRequest: SMBRequestBody {
        static var command: SMB2.Command = .QUERY_INFO
        
        let header: Header
        let buffer: Data?
        
        init(fileId: FileId, infoClass: FileInformationEnum, outputBufferLength: UInt32 = 65535) {
            self.header = Header(size: 41, infoType: 1, infoClass: infoClass.rawValue, outputBufferLength: outputBufferLength, inputBufferOffset: 0, reserved: 0, inputBufferLength: 0, additionalInformation: [], flags: [], fileId: fileId)
            self.buffer = nil
        }
        
        init(fileId: FileId, extendedAttributes: [String], flags: Flags = [], outputBufferLength: UInt32 = 65535) {
            var buffer = Data()
            for ea in extendedAttributes {
                guard let strData = ea.data(using: .ascii) else {
                    continue
                }
                let strLength = UInt8(strData.count)
                let nextOffset = UInt32(4 + 1 + strData.count)
                var data = Data(value: nextOffset)
                data.append(Data(value: strLength))
                data.append(strData)
                data.count += 1
                let padSize = (data.count) % 4
                data.count += padSize
                buffer.append(data as Data)
            }
            
            let bufferOffset = UInt16(MemoryLayout<SMB2.Header>.size + MemoryLayout<QueryInfoRequest.Header>.size)
            self.header = Header(size: 41, infoType: 1, infoClass: FileInformationEnum.fileFullEaInformation.rawValue, outputBufferLength: outputBufferLength, inputBufferOffset: bufferOffset, reserved: 0, inputBufferLength: UInt32(buffer.count), additionalInformation: [], flags: flags, fileId: fileId)
            self.buffer = buffer as Data
        }
        
        init(fileId: FileId, infoClass: FileSystemInformationEnum, outputBufferLength: UInt32 = 65535) {
            self.header = Header(size: 41, infoType: 2, infoClass: infoClass.rawValue, outputBufferLength: outputBufferLength, inputBufferOffset: 0, reserved: 0, inputBufferLength: 0, additionalInformation: [], flags: [], fileId: fileId)
            self.buffer = nil
        }
        
        init(fileId: FileId, securityInfo: FileSecurityInfo, outputBufferLength: UInt32 = 65535) {
            self.header = Header(size: 41, infoType: 3, infoClass: 0, outputBufferLength: outputBufferLength, inputBufferOffset: 0, reserved: 0, inputBufferLength: 0, additionalInformation: securityInfo, flags: [], fileId: fileId)
            self.buffer = nil
        }
        
        // TODO: Implement QUOTA_INFO init
        
        func data() -> Data {
            var result = Data(value: header)
            if let buffer = buffer {
                result.append(buffer)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            let infoType: UInt8
            let infoClass: UInt8
            let outputBufferLength: UInt32
            let inputBufferOffset: UInt16
            fileprivate let reserved: UInt16
            let inputBufferLength: UInt32
            let additionalInformation: FileSecurityInfo
            let flags: QueryInfoRequest.Flags
            let fileId: FileId
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            static let RESTART_SCAN         = Flags(rawValue: 0x00000001)
            static let RETURN_SINGLE_ENTRY  = Flags(rawValue: 0x00000002)
            static let INDEX_SPECIFIED      = Flags(rawValue: 0x00000004)
        }
    }
    
    struct QueryInfoResponse: SMBResponseBody {
        let buffer: Data
        
        init?(data: Data) {
            let structSize: UInt16 = data.scanValue()!
            guard structSize == 9 else {
                return nil
            }
            
            /*let offsetData = data.subdataWithRange(NSRange(location: 2, length: 2))
            let offset: UInt16 = decode(offsetData)*/
            
            let length = Int(data.scanValue(start: 4) as UInt32!)
            
            guard data.count >= 8 + length else {
                return nil
            }
            
            self.buffer = data.subdata(in: 8..<(8 + length))
        }
        
        var asAccessInformation: FileAccessInformation {
            return buffer.scanValue()!
        }
        
        var asAlignmentInformation: FileAlignmentInformation {
            return buffer.scanValue()!
        }
        
        var asAllInformation: (header: FileAllInformationHeader, name: String) {
            let header: FileAllInformationHeader = buffer.scanValue()!
            let headersize = MemoryLayout<FileAllInformationHeader>.size
            let name = buffer.scanString(start: headersize, length: Int(header.nameLength), using: .utf16) ?? ""
            return (header, name)
        }
        
        var asAlternateNameInformation: String {
            return buffer.scanString(start: 0, length: buffer.count, using: .utf16) ?? ""
        }
        
        var asAttributeTagInformation: FileAttributeTagInformation {
            return buffer.scanValue()!
        }
        
        var asBasicInformation: FileBasicInformation {
            return buffer.scanValue()!
        }
        
        var asCompressionInformation: FileCompressionInformation {
            return buffer.scanValue()!
        }
        
        var asEaInformation: FileEaInformation {
            return buffer.scanValue()!
        }
        
        var asFullEaInformation: FileFullEaInformation {
            // TODO:
            return FileFullEaInformation()
        }
        
        var asInternalInformation: FileInternalInformation {
            return buffer.scanValue()!
        }
        
        var asModeInformation: FileModeInformation {
            return buffer.scanValue()!
        }
        
        var asNetworkOpenInformation: FileNetworkOpenInformation {
            return buffer.scanValue()!
        }
        
        var asPipeInformation: FilePipeInformation {
            return buffer.scanValue()!
        }
        
        var asPipeLocalInformation: FilePipeLocalInformation {
            return buffer.scanValue()!
        }
        
        var asPipeRemoteInformation: FilePipeRemoteInformation {
            return buffer.scanValue()!
        }
        
        var asPositionInformation: FilePositionInformation {
            return buffer.scanValue()!
        }
        
        var asStandardInformation: FileStandardInformation {
            return buffer.scanValue()!
        }
        
        var asStreamInformation: (header: FileStreamInformationHeader, name: String) {
            let header: FileStreamInformationHeader = buffer.scanValue()!
            let headersize = MemoryLayout<FileStreamInformationHeader>.size
            let name = buffer.scanString(start: headersize, length: Int(header.streamNameLength), using: .utf16) ?? ""
            return (header, name)
        }
        
        var asFsVolumeInformation: (header: FileFsVolumeInformationHeader, name: String) {
            let header: FileFsVolumeInformationHeader = buffer.scanValue()!
            let headersize = MemoryLayout<FileFsVolumeInformationHeader>.size
            let name = buffer.scanString(start: headersize, length: Int(header.labelLength), using: .utf16) ?? ""
            return (header, name)
        }
        
        var asFsSizeInformation: FileFsSizeInformation {
            return buffer.scanValue()!
        }
        
        var asFsDeviceInformation: FileFsDeviceInformation {
            return buffer.scanValue()!
        }
        
        var asFsAttributeInformation: (header: FileFsAttributeInformationHeader, name: String) {
            let header: FileFsAttributeInformationHeader = buffer.scanValue()!
            let headersize = MemoryLayout<FileFsAttributeInformationHeader>.size
            let name = buffer.scanString(start: headersize, length: Int(header.nameLength), using: .utf16) ?? ""
            return (header, name)
        }
        
        var asFsControlInformation: FileFsControlInformation {
            return buffer.scanValue()!
        }
        
        var asFsFullSizeInformation: FileFsFullSizeInformation {
            return buffer.scanValue()!
        }
        
        var asFsObjectIdInformation: FileFsObjectIdInformation {
            return buffer.scanValue()!
        }
        
        var asFsSectorSizeInformation: FileFsSectorSizeInformation {
            return buffer.scanValue()!
        }
    }
}
