//
//  SMBErrorType.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 4/30/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

/// Error Types and Description

public enum NTStatus: UInt32, ErrorType, CustomStringConvertible {
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