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
        init(fileId: FileId, infoClass: FileInformationEnum, flags: Flags, bufferLength: UInt32 = 65535, searchPattern: String? = nil, fileIndex: UInt32 = 0) {
            assert(FileInformationEnum.queryDirectory.contains(infoClass), "Invalid FileInformationClass used for QueryDirectoryRequest")
            let searchPatternOffset = searchPattern != nil ? MemoryLayout<SMB2.Header>.size + MemoryLayout<QueryDirectoryRequest.Header>.size : 0
            let nflags = flags.intersection(fileIndex > 0 ? [.INDEX_SPECIFIED] : [])
            let searchPatternLength = searchPattern?.data(using: String.Encoding.utf16)?.count ?? 0
            self.header = Header(size: 53, infoClass: infoClass, flags: nflags, fileIndex: fileIndex, fileId: fileId, searchPatternOffset: UInt8(searchPatternOffset), searchPatternLength: UInt8(searchPatternLength), bufferLength: bufferLength)
            self.searchPattern = searchPattern
        }
        
        func data() -> Data {
            var result = encode(header)
            if let patternData = searchPattern?.data(using: String.Encoding.utf16) {
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
    
    struct QueryDirectoryResponse: SMBResponse {
        let buffer: Data
        
        func parseAs(type: FileInformationEnum) -> [(header: SMB2FilesInformationHeader, fileName: String)] {
            var offset = 0
            var result = [(header: SMB2FilesInformationHeader, fileName: String)]()
            while true {
                let header: SMB2FilesInformationHeader
                let headersize: Int
                switch type {
                case .fileDirectoryInformation:
                    headersize = MemoryLayout<FileDirectoryInformationHeader>.size
                    let headerData = buffer.subdata(in: offset..<(offset + headersize))
                    let h: FileDirectoryInformationHeader = decode(headerData)
                    header = h
                case .fileFullDirectoryInformation:
                    headersize = MemoryLayout<FileFullDirectoryInformationHeader>.size
                    let headerData = buffer.subdata(in: offset..<(offset + headersize))
                    let h: FileFullDirectoryInformationHeader = decode(headerData)
                    header = h
                case .fileIdFullDirectoryInformation:
                    headersize = MemoryLayout<FileIdFullDirectoryInformationHeader>.size
                    let headerData = buffer.subdata(in: offset..<(offset + headersize))
                    let h: FileIdFullDirectoryInformationHeader = decode(headerData)
                    header = h
                case .fileBothDirectoryInformation:
                    headersize = MemoryLayout<FileBothDirectoryInformationHeader>.size
                    let headerData = buffer.subdata(in: offset..<(offset + headersize))
                    let h: FileBothDirectoryInformationHeader = decode(headerData)
                    header = h
                case .fileIdBothDirectoryInformation:
                    headersize = MemoryLayout<FileIdBothDirectoryInformationHeader>.size
                    let headerData = buffer.subdata(in: offset..<(offset + headersize))
                    let h: FileIdBothDirectoryInformationHeader = decode(headerData)
                    header = h
                case .fileNamesInformation:
                    headersize = MemoryLayout<FileNamesInformationHeader>.size
                    let headerData = buffer.subdata(in: offset..<(offset + headersize))
                    let h: FileNamesInformationHeader = decode(headerData)
                    header = h
                default:
                    return []
                }
                let fnData = buffer.subdata(in: (offset + headersize)..<(offset + headersize + Int(header.fileNameLength)))
                let fileName = String(data: fnData, encoding: String.Encoding.utf16) ?? ""
                result.append((header: header, fileName: fileName))
                if header.nextEntryOffset == 0 {
                    break
                }
                offset += Int(header.nextEntryOffset)
            }
            return result
        }
        
        init? (data: Data) {
            let offset = Int(decode(data.subdata(in: 2..<4)) as UInt16)
            let length = Int(decode(data.subdata(in: 4..<8)) as UInt32)
            guard data.count > offset + length else {
                return nil
            }
            self.buffer = data.subdata(in: offset..<(offset + length))
        }
    }
    
    // MARK: SMB2 Query Info
    
    struct QueryInfoRequest: SMBRequest {
        let header: Header
        let buffer: Data?
        
        init(fileId: FileId, infoClass: FileInformationEnum, outputBufferLength: UInt32 = 65535) {
            self.header = Header(size: 41, infoType: 1, infoClass: infoClass.rawValue, outputBufferLength: outputBufferLength, inputBufferOffset: 0, reserved: 0, inputBufferLength: 0, additionalInformation: [], flags: [], fileId: fileId)
            self.buffer = nil
        }
        
        init(fileId: FileId, extendedAttributes: [String], flags: Flags = [], outputBufferLength: UInt32 = 65535) {
            var buffer = Data()
            for ea in extendedAttributes {
                guard let strData = ea.data(using: String.Encoding.ascii) else {
                    continue
                }
                let strLength = UInt8(strData.count)
                let nextOffset = UInt32(4 + 1 + strData.count)
                var data = encode(nextOffset)
                data.append(encode(strLength))
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
            let headerData = encode(header)
            var result = headerData
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
    
    struct QueryInfoResponse: SMBResponse {
        let buffer: Data
        
        init?(data: Data) {
            let structSizeData = data.subdata(in: 0..<2)
            let structSize: UInt16 = decode(structSizeData)
            guard structSize == 9 else {
                return nil
            }
            
            /*let offsetData = data.subdataWithRange(NSRange(location: 2, length: 2))
            let offset: UInt16 = decode(offsetData)*/
            
            let lengthData = data.subdata(in: 4..<8)
            let length = Int(decode(lengthData) as UInt32)
            
            guard data.count >= 8 + Int(length) else {
                return nil
            }
            
            self.buffer = data.subdata(in: 8..<(8 + length))
        }
        
        var asAccessInformation: FileAccessInformation {
            return decode(buffer)
        }
        
        var asAlignmentInformation: FileAlignmentInformation {
            return decode(buffer)
        }
        
        var asAllInformation: (header: FileAllInformationHeader, name: String) {
            let header: FileAllInformationHeader = decode(buffer)
            let headersize = MemoryLayout<FileAllInformationHeader>.size
            let nameData = buffer.subdata(in: headersize..<(headersize + Int(header.nameLength)))
            let name = String(data: nameData, encoding: String.Encoding.utf16) ?? ""
            return (header, name)
        }
        
        var asAlternateNameInformation: String {
            let b = (buffer as NSData).bytes.bindMemory(to: CChar.self, capacity: buffer.count)
            return String(cString: b, encoding: String.Encoding.utf16) ?? ""
        }
        
        var asAttributeTagInformation: FileAttributeTagInformation {
            return decode(buffer)
        }
        
        var asBasicInformation: FileBasicInformation {
            return decode(buffer)
        }
        
        var asCompressionInformation: FileCompressionInformation {
            return decode(buffer)
        }
        
        var asEaInformation: FileEaInformation {
            return decode(buffer)
        }
        
        var asFullEaInformation: FileFullEaInformation {
            // TODO:
            return FileFullEaInformation()
        }
        
        var asInternalInformation: FileInternalInformation {
            return decode(buffer)
        }
        
        var asModeInformation: FileModeInformation {
            return decode(buffer)
        }
        
        var asNetworkOpenInformation: FileNetworkOpenInformation {
            return decode(buffer)
        }
        
        var asPipeInformation: FilePipeInformation {
            return decode(buffer)
        }
        
        var asPipeLocalInformation: FilePipeLocalInformation {
            return decode(buffer)
        }
        
        var asPipeRemoteInformation: FilePipeRemoteInformation {
            return decode(buffer)
        }
        
        var asPositionInformation: FilePositionInformation {
            return decode(buffer)
        }
        
        var asStandardInformation: FileStandardInformation {
            return decode(buffer)
        }
        
        var asStreamInformation: (header: FileStreamInformationHeader, name: String) {
            let header: FileStreamInformationHeader = decode(buffer)
            let headersize = MemoryLayout<FileStreamInformationHeader>.size
            let nameData = buffer.subdata(in: headersize..<(headersize + Int(header.streamNameLength)))
            let name = String(data: nameData, encoding: String.Encoding.utf16) ?? ""
            return (header, name)
        }
        
        var asFsVolumeInformation: (header: FileFsVolumeInformationHeader, name: String) {
            let header: FileFsVolumeInformationHeader = decode(buffer)
            let headersize = MemoryLayout<FileFsVolumeInformationHeader>.size
            let nameData = buffer.subdata(in: headersize..<(headersize + Int(header.labelLength)))
            let name = String(data: nameData, encoding: String.Encoding.utf16) ?? ""
            return (header, name)
        }
        
        var asFsSizeInformation: FileFsSizeInformation {
            return decode(buffer)
        }
        
        var asFsDeviceInformation: FileFsDeviceInformation {
            return decode(buffer)
        }
        
        var asFsAttributeInformation: (header: FileFsAttributeInformationHeader, name: String) {
            let header: FileFsAttributeInformationHeader = decode(buffer)
            let headersize = MemoryLayout<FileFsAttributeInformationHeader>.size
            let nameData = buffer.subdata(in: headersize..<(headersize + Int(header.nameLength)))
            let name = String(data: nameData, encoding: String.Encoding.utf16) ?? ""
            return (header, name)
        }
        
        var asFsControlInformation: FileFsControlInformation {
            return decode(buffer)
        }
        
        var asFsFullSizeInformation: FileFsFullSizeInformation {
            return decode(buffer)
        }
        
        var asFsObjectIdInformation: FileFsObjectIdInformation {
            return decode(buffer)
        }
        
        var asFsSectorSizeInformation: FileFsSectorSizeInformation {
            return decode(buffer)
        }
    }
}
