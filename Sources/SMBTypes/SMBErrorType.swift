//
//  SMBErrorType.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

/// Error Types and Description

struct NTStatus: Option, Error, CustomStringConvertible {
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    var rawValue: UInt32
    
    public static let SUCCESS                        = NTStatus(rawValue: 0x00000000)
    public static let NOT_IMPLEMENTED                = NTStatus(rawValue: 0xC0000002)
    public static let INVALID_DEVICE_REQUEST         = NTStatus(rawValue: 0xC0000010)
    public static let ILLEGAL_FUNCTION               = NTStatus(rawValue: 0xC00000AF)
    public static let NO_SUCH_FILE                   = NTStatus(rawValue: 0xC000000F)
    public static let NO_SUCH_DEVICE                 = NTStatus(rawValue: 0xC000000E)
    public static let OBJECT_NAME_NOT_FOUND          = NTStatus(rawValue: 0xC0000034)
    public static let OBJECT_PATH_INVALID            = NTStatus(rawValue: 0xC0000039)
    public static let OBJECT_PATH_NOT_FOUND          = NTStatus(rawValue: 0xC000003A)
    public static let OBJECT_PATH_SYNTAX_BAD         = NTStatus(rawValue: 0xC000003B)
    public static let DFS_EXIT_PATH_FOUND            = NTStatus(rawValue: 0xC000009B)
    public static let REDIRECTOR_NOT_STARTED         = NTStatus(rawValue: 0xC00000FB)
    public static let TOO_MANY_OPENED_FILES          = NTStatus(rawValue: 0xC000011F)
    public static let ACCESS_DENIED                  = NTStatus(rawValue: 0xC0000022)
    public static let INVALID_LOCK_SEQUENCE          = NTStatus(rawValue: 0xC000001E)
    public static let INVALID_VIEW_SIZE              = NTStatus(rawValue: 0xC000001F)
    public static let ALREADY_COMMITTED              = NTStatus(rawValue: 0xC0000021)
    public static let PORT_CONNECTION_REFUSED        = NTStatus(rawValue: 0xC0000041)
    public static let THREAD_IS_TERMINATING          = NTStatus(rawValue: 0xC000004B)
    public static let DELETE_PENDING                 = NTStatus(rawValue: 0xC0000056)
    public static let PRIVILEGE_NOT_HELD             = NTStatus(rawValue: 0xC0000061)
    public static let LOGON_FAILURE                  = NTStatus(rawValue: 0xC000006D)
    public static let FILE_IS_A_DIRECTORY            = NTStatus(rawValue: 0xC00000BA)
    public static let FILE_RENAMED                   = NTStatus(rawValue: 0xC00000D5)
    public static let PROCESS_IS_TERMINATING         = NTStatus(rawValue: 0xC000010A)
    public static let DIRECTORY_NOT_EMPTY            = NTStatus(rawValue: 0xC0000101)
    public static let CANNOT_DELETE                  = NTStatus(rawValue: 0xC0000121)
    public static let FILE_NOT_AVAILABLE             = NTStatus(rawValue: 0xC0000467)
    public static let FILE_DELETED                   = NTStatus(rawValue: 0xC0000123)
    public static let SMB_BAD_FID                    = NTStatus(rawValue: 0x00060001)
    public static let INVALID_HANDLE                 = NTStatus(rawValue: 0xC0000008)
    public static let OBJECT_TYPE_MISMATCH           = NTStatus(rawValue: 0xC0000024)
    public static let PORT_DISCONNECTED              = NTStatus(rawValue: 0xC0000037)
    public static let INVALID_PORT_HANDLE            = NTStatus(rawValue: 0xC0000042)
    public static let FILE_CLOSED                    = NTStatus(rawValue: 0xC0000128)
    public static let HANDLE_NOT_CLOSABLE            = NTStatus(rawValue: 0xC0000235)
    public static let SECTION_TOO_BIG                = NTStatus(rawValue: 0xC0000040)
    public static let TOO_MANY_PAGING_FILES          = NTStatus(rawValue: 0xC0000097)
    public static let INSUFF_SERVER_RESOURCES        = NTStatus(rawValue: 0xC0000205)
    public static let OS2_INVALID_ACCESS             = NTStatus(rawValue: 0x000C0001)
    public static let ACCESS_DENIED_2                = NTStatus(rawValue: 0xC00000CA)
    public static let DATA_ERROR                     = NTStatus(rawValue: 0xC000009C)
    public static let NOT_SAME_DEVICE                = NTStatus(rawValue: 0xC00000D4)
    public static let NO_MORE_FILES                  = NTStatus(rawValue: 0x80000006)
    public static let NO_MORE_ENTRIES                = NTStatus(rawValue: 0x8000001A)
    public static let UNSUCCESSFUL                   = NTStatus(rawValue: 0xC0000001)
    public static let SHARING_VIOLATION              = NTStatus(rawValue: 0xC0000043)
    public static let FILE_LOCK_CONFLICT             = NTStatus(rawValue: 0xC0000054)
    public static let LOCK_NOT_GRANTED               = NTStatus(rawValue: 0xC0000055)
    public static let END_OF_FILE                    = NTStatus(rawValue: 0xC0000011)
    public static let NOT_SUPPORTED                  = NTStatus(rawValue: 0xC00000BB)
    public static let OBJECT_NAME_COLLISION          = NTStatus(rawValue: 0xC0000035)
    public static let INVALID_PARAMETER              = NTStatus(rawValue: 0xC000000D)
    public static let OS2_INVALID_LEVEL              = NTStatus(rawValue: 0x007C0001)
    public static let OS2_NEGATIVE_SEEK              = NTStatus(rawValue: 0x00830001)
    public static let RANGE_NOT_LOCKED               = NTStatus(rawValue: 0xC000007E)
    public static let OS2_NO_MORE_SIDS               = NTStatus(rawValue: 0x00710001)
    public static let OS2_CANCEL_VIOLATION           = NTStatus(rawValue: 0x00AD0001)
    public static let OS2_ATOMIC_LOCKS_NOT_SUPPORTED = NTStatus(rawValue: 0x00AE0001)
    public static let INVALID_INFO_CLASS             = NTStatus(rawValue: 0xC0000003)
    public static let INVALID_PIPE_STATE             = NTStatus(rawValue: 0xC00000AD)
    public static let INVALID_READ_MODE              = NTStatus(rawValue: 0xC00000B4)
    public static let OS2_CANNOT_COPY                = NTStatus(rawValue: 0x010A0001)
    public static let STOPPED_ON_SYMLINK             = NTStatus(rawValue: 0x8000002D)
    public static let INSTANCE_NOT_AVAILABLE         = NTStatus(rawValue: 0xC00000AB)
    public static let PIPE_NOT_AVAILABLE             = NTStatus(rawValue: 0xC00000AC)
    public static let PIPE_BUSY                      = NTStatus(rawValue: 0xC00000AE)
    public static let PIPE_CLOSING                   = NTStatus(rawValue: 0xC00000B1)
    public static let PIPE_EMPTY                     = NTStatus(rawValue: 0xC00000D9)
    public static let PIPE_DISCONNECTED              = NTStatus(rawValue: 0xC00000B0)
    public static let BUFFER_OVERFLOW                = NTStatus(rawValue: 0x80000005)
    public static let MORE_PROCESSING_REQUIRED       = NTStatus(rawValue: 0xC0000016)
    public static let EA_TOO_LARGE                   = NTStatus(rawValue: 0xC0000050)
    public static let OS2_EAS_DIDNT_FIT              = NTStatus(rawValue: 0x01130001)
    public static let EAS_NOT_SUPPORTED              = NTStatus(rawValue: 0xC000004F)
    public static let EA_LIST_INCONSISTENT           = NTStatus(rawValue: 0x80000014)
    public static let OS2_EA_ACCESS_DENIED           = NTStatus(rawValue: 0x03E20001)
    public static let NOTIFY_ENUM_DIR                = NTStatus(rawValue: 0x0000010C)
    public static let INVALID_SMB                    = NTStatus(rawValue: 0x00010002)
    public static let WRONG_PASSWORD                 = NTStatus(rawValue: 0xC000006A)
    public static let PATH_NOT_COVERED               = NTStatus(rawValue: 0xC0000257)
    public static let NETWORK_NAME_DELETED           = NTStatus(rawValue: 0xC00000C9)
    public static let SMB_BAD_TID                    = NTStatus(rawValue: 0x00050002)
    public static let BAD_NETWORK_NAME               = NTStatus(rawValue: 0xC00000CC)
    public static let BAD_DEVICE_TYPE                = NTStatus(rawValue: 0xC00000CB)
    public static let SMB_BAD_COMMAND                = NTStatus(rawValue: 0x00160002)
    public static let PRINT_QUEUE_FULL               = NTStatus(rawValue: 0xC00000C6)
    public static let NO_SPOOL_SPACE                 = NTStatus(rawValue: 0xC00000C7)
    public static let PRINT_CANCELLED                = NTStatus(rawValue: 0xC00000C8)
    public static let UNEXPECTED_NETWORK_ERROR       = NTStatus(rawValue: 0xC00000C4)
    public static let IO_TIMEOUT                     = NTStatus(rawValue: 0xC00000B5)
    public static let REQUEST_NOT_ACCEPTED           = NTStatus(rawValue: 0xC00000D0)
    public static let TOO_MANY_SESSIONS              = NTStatus(rawValue: 0xC00000CE)
    public static let SMB_BAD_UID                    = NTStatus(rawValue: 0x005B0002)
    public static let SMB_USE_MPX                    = NTStatus(rawValue: 0x00FA0002)
    public static let SMB_USE_STANDARD               = NTStatus(rawValue: 0x00FB0002)
    public static let SMB_CONTINUE_MPX               = NTStatus(rawValue: 0x00FC0002)
    public static let ACCOUNT_DISABLED               = NTStatus(rawValue: 0xC0000072)
    public static let ACCOUNT_EXPIRED                = NTStatus(rawValue: 0xC0000193)
    public static let INVALID_WORKSTATION            = NTStatus(rawValue: 0xC0000070)
    public static let INVALID_LOGON_HOURS            = NTStatus(rawValue: 0xC000006F)
    public static let PASSWORD_EXPIRED               = NTStatus(rawValue: 0xC0000071)
    public static let PASSWORD_MUST_CHANGE           = NTStatus(rawValue: 0xC0000224)
    public static let SMB_NO_SUPPORT                 = NTStatus(rawValue: 0xFFFF0002)
    public static let MEDIA_WRITE_PROTECTED          = NTStatus(rawValue: 0xC00000A2)
    public static let NO_MEDIA_IN_DEVICE             = NTStatus(rawValue: 0xC0000013)
    public static let INVALID_DEVICE_STATE           = NTStatus(rawValue: 0xC0000184)
    public static let DATA_ERROR_2                   = NTStatus(rawValue: 0xC000003E)
    public static let CRC_ERROR                      = NTStatus(rawValue: 0xC000003F)
    public static let DISK_CORRUPT_ERROR             = NTStatus(rawValue: 0xC0000032)
    public static let NONEXISTENT_SECTOR             = NTStatus(rawValue: 0xC0000015)
    public static let DEVICE_PAPER_EMPTY             = NTStatus(rawValue: 0x8000000E)
    public static let WRONG_VOLUME                   = NTStatus(rawValue: 0xC0000012)
    public static let DISK_FULL                      = NTStatus(rawValue: 0xC000007F)
    public static let BUFFER_TOO_SMALL               = NTStatus(rawValue: 0xC0000023)
    public static let BAD_IMPERSONATION_LEVEL        = NTStatus(rawValue: 0xC00000A5)
    public static let USER_SESSION_DELETED           = NTStatus(rawValue: 0xC0000203)
    public static let NETWORK_SESSION_EXPIRED        = NTStatus(rawValue: 0xC000035C)
    public static let SMB_TOO_MANY_UIDS              = NTStatus(rawValue: 0xC000205A)
    
    public var description: String {
        switch self {
        case .NOT_IMPLEMENTED, .INVALID_DEVICE_REQUEST, .ILLEGAL_FUNCTION:
            return "Invalid Function."
        case .NO_SUCH_FILE, .NO_SUCH_DEVICE, .OBJECT_NAME_NOT_FOUND:
            return "File not found."
        case .OBJECT_PATH_INVALID, .OBJECT_PATH_NOT_FOUND, .OBJECT_PATH_SYNTAX_BAD, .DFS_EXIT_PATH_FOUND, .REDIRECTOR_NOT_STARTED:
            return "A component in the path prefix is not a directory."
        case .TOO_MANY_OPENED_FILES:
            return "Too many open files. No FIDs are available."
        case .ACCESS_DENIED, .INVALID_LOCK_SEQUENCE, .INVALID_VIEW_SIZE, .ALREADY_COMMITTED, .PORT_CONNECTION_REFUSED, .THREAD_IS_TERMINATING, .DELETE_PENDING, .PRIVILEGE_NOT_HELD, .LOGON_FAILURE, .FILE_IS_A_DIRECTORY, .FILE_RENAMED, .PROCESS_IS_TERMINATING, .CANNOT_DELETE, .FILE_DELETED:
            return "Access denied."
        case .SMB_BAD_FID, .INVALID_HANDLE, .OBJECT_TYPE_MISMATCH, .PORT_DISCONNECTED, .INVALID_PORT_HANDLE, .FILE_CLOSED, .HANDLE_NOT_CLOSABLE:
            return "Invalid FID."
        case .SECTION_TOO_BIG, .TOO_MANY_PAGING_FILES, .INSUFF_SERVER_RESOURCES:
            return "Insufficient server memory to perform the requested operation."
        case .OS2_INVALID_ACCESS:
            return "Invalid open mode."
        case .DATA_ERROR:
            return "Bad data. (May be generated by IOCTL calls on the server.)"
        case .DIRECTORY_NOT_EMPTY:
            return "Remove of directory failed because it was not empty."
        case .NOT_SAME_DEVICE:
            return "A file system operation (such as a rename) across two devices was attempted."
        case .NO_MORE_FILES:
            return "No (more) files found following a file search command."
        case .UNSUCCESSFUL:
            return "General error."
        case .SHARING_VIOLATION:
            return "Sharing violation. A requested open mode conflicts with the sharing mode of an existing file handle."
        case .FILE_LOCK_CONFLICT, .LOCK_NOT_GRANTED:
            return "A lock request specified an invalid locking mode, or conflicted with an existing file lock."
        case .END_OF_FILE:
            return "Attempted to read beyond the end of the file."
        case .NOT_SUPPORTED:
            return "This command is not supported by the server."
        case .OBJECT_NAME_COLLISION:
            return "An attempt to create a file or directory failed because an object with the same pathname already exists."
        case .INVALID_PARAMETER:
            return "A parameter supplied with the message is invalid."
        case .OS2_INVALID_LEVEL:
            return "Invalid information level."
        case .OS2_NEGATIVE_SEEK:
            return "An attempt was made to seek to a negative absolute offset within a file."
        case .RANGE_NOT_LOCKED:
            return "The byte range specified in an unlock request was not locked."
        case .OS2_NO_MORE_SIDS:
            return "Maximum number of searches has been exhausted."
        case .OS2_CANCEL_VIOLATION:
            return "No lock request was outstanding for the supplied cancel region."
        case .OS2_ATOMIC_LOCKS_NOT_SUPPORTED:
            return "The file system does not support atomic changes to the lock type."
        case .INVALID_INFO_CLASS, .INVALID_PIPE_STATE, .INVALID_READ_MODE:
            return "Invalid named pipe."
        case .OS2_CANNOT_COPY:
            return "The copy functions cannot be used."
        case .INSTANCE_NOT_AVAILABLE, .PIPE_NOT_AVAILABLE, .PIPE_BUSY:
            return "All instances of the designated named pipe are busy."
        case .PIPE_CLOSING, .PIPE_EMPTY:
            return "The designated named pipe is in the process of being closed."
        case .PIPE_DISCONNECTED:
            return "The designated named pipe exists, but there is no server process listening on the server side."
        case .BUFFER_OVERFLOW, .MORE_PROCESSING_REQUIRED:
            return "There is more data available to read on the designated named pipe."
        case .EA_TOO_LARGE, .OS2_EAS_DIDNT_FIT:
            return "Either there are no extended attributes, or the available extended attributes did not fit into the response."
        case .EAS_NOT_SUPPORTED:
            return "The server file system does not support Extended Attributes."
        case .OS2_EA_ACCESS_DENIED:
            return "Access to the extended attribute was denied."
        default:
            return ""
        }
    }
}
