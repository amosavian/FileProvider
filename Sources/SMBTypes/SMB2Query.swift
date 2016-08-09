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
            let infoClass: FileInformationEnum
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
            
            static let RESTART_SCANS        = Flags(rawValue: 0x01)
            static let RETURN_SINGLE_ENTRY  = Flags(rawValue: 0x02)
            static let INDEX_SPECIFIED      = Flags(rawValue: 0x04)
            static let REOPEN               = Flags(rawValue: 0x10)
        }
    }
    
    struct QueryDirectoryResponse: SMBResponse {
        let buffer: NSData
        
        func parseAs(type type: FileInformationEnum) -> [(header: SMB2FilesInformationHeader, fileName: String)] {
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
    
    // MARK: SMB2 Query Info
    
    struct QueryInfoRequest: SMBRequest {
        let header: Header
        let buffer: NSData?
        
        init(fileId: FileId, infoClass: FileInformationEnum, outputBufferLength: UInt32 = 65535) {
            self.header = Header(size: 41, infoType: 1, infoClass: infoClass.rawValue, outputBufferLength: outputBufferLength, inputBufferOffset: 0, reserved: 0, inputBufferLength: 0, additionalInformation: [], flags: [], fileId: fileId)
            self.buffer = nil
        }
        
        init(fileId: FileId, extendedAttributes: [String], flags: Flags = [], outputBufferLength: UInt32 = 65535) {
            let buffer = NSMutableData()
            for ea in extendedAttributes {
                let strData = ea.dataUsingEncoding(NSASCIIStringEncoding)!
                let strLength = UInt8(strData.length)
                let nextOffset = UInt32(4 + 1 + strData.length)
                let data = encode(nextOffset).mutableCopy() as! NSMutableData
                data.appendData(encode(strLength))
                data.appendData(strData)
                data.length += 1
                let padSize = (data.length) % 4
                data.length += padSize
                buffer.appendData(data)
            }
            
            let bufferOffset = UInt16(sizeof(SMB2.Header.self) + sizeof(QueryInfoRequest.Header.self))
            self.header = Header(size: 41, infoType: 1, infoClass: FileInformationEnum.FileFullEaInformation.rawValue, outputBufferLength: outputBufferLength, inputBufferOffset: bufferOffset, reserved: 0, inputBufferLength: UInt32(buffer.length), additionalInformation: [], flags: flags, fileId: fileId)
            self.buffer = buffer
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
        
        func data() -> NSData {
            let headerData = encode(header)
            let result = NSMutableData(data: headerData)
            if let buffer = buffer {
                result.appendData(buffer)
            }
            return result
        }
        
        struct Header {
            let size: UInt16
            let infoType: UInt8
            let infoClass: UInt8
            let outputBufferLength: UInt32
            let inputBufferOffset: UInt16
            private let reserved: UInt16
            let inputBufferLength: UInt32
            let additionalInformation: FileSecurityInfo
            let flags: QueryInfoRequest.Flags
            let fileId: FileId
        }
        
        struct Flags: OptionSetType {
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
        let buffer: NSData
        
        init?(data: NSData) {
            let structSizeData = data.subdataWithRange(NSRange(location: 0, length: 2))
            let structSize: UInt16 = decode(structSizeData)
            guard structSize == 9 else {
                return nil
            }
            
            /*let offsetData = data.subdataWithRange(NSRange(location: 2, length: 2))
            let offset: UInt16 = decode(offsetData)*/
            
            let lengthData = data.subdataWithRange(NSRange(location: 4, length: 4))
            let length: UInt32 = decode(lengthData)
            
            guard data.length >= 8 + Int(length) else {
                return nil
            }
            
            self.buffer = data.subdataWithRange(NSRange(location: 8, length: Int(length)))
        }
        
        var asAccessInformation: FileAccessInformation {
            return decode(buffer)
        }
        
        var asAlignmentInformation: FileAlignmentInformation {
            return decode(buffer)
        }
        
        var asAllInformation: (header: FileAllInformationHeader, name: String) {
            let header: FileAllInformationHeader = decode(buffer)
            let nameData = buffer.subdataWithRange(NSRange(location: sizeof(FileAllInformationHeader), length: Int(header.nameLength)))
            let name = String(data: nameData, encoding: NSUTF16StringEncoding) ?? ""
            return (header, name)
        }
        
        var asAlternateNameInformation: String {
            let b = UnsafePointer<CChar>(buffer.bytes)
            return String(CString: b, encoding: NSUTF16StringEncoding) ?? ""
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
            let nameData = buffer.subdataWithRange(NSRange(location: sizeof(FileStreamInformationHeader), length: Int(header.streamNameLength)))
            let name = String(data: nameData, encoding: NSUTF16StringEncoding) ?? ""
            return (header, name)
        }
        
        var asFsVolumeInformation: (header: FileFsVolumeInformationHeader, name: String) {
            let header: FileFsVolumeInformationHeader = decode(buffer)
            let nameData = buffer.subdataWithRange(NSRange(location: sizeof(FileFsVolumeInformationHeader), length: Int(header.labelLength)))
            let name = String(data: nameData, encoding: NSUTF16StringEncoding) ?? ""
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
            let nameData = buffer.subdataWithRange(NSRange(location: sizeof(FileFsAttributeInformationHeader), length: Int(header.nameLength)))
            let name = String(data: nameData, encoding: NSUTF16StringEncoding) ?? ""
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