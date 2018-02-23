//
//  SMB2Notification.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian on 5/18/95.
//
//

import Foundation

extension SMB2 {
    // MARK: SMB2 Change Notify
    
    struct ChangeNotifyRequest: SMBRequestBody {
        static var command: SMB2.Command = .CHANGE_NOTIFY
        
        let size: UInt16
        let flags: ChangeNotifyRequest.Flags
        let outputBufferLength: UInt32
        let fileId: FileId
        let completionFilters: CompletionFilter
        fileprivate let reserved: UInt32
        
        init(fileId: FileId, completionFilters: CompletionFilter, flags: ChangeNotifyRequest.Flags = [], outputBufferLength: UInt32 = 65535) {
            self.size = 32
            self.flags = flags
            self.outputBufferLength = outputBufferLength
            self.fileId = fileId
            self.completionFilters = completionFilters
            self.reserved = 0
        }
        
        struct Flags: OptionSet {
            let rawValue: UInt16
            
            init(rawValue: UInt16) {
                self.rawValue = rawValue
            }
            
            static let WATCH_TREE = Flags(rawValue: 0x0001)
        }
        
        struct CompletionFilter: OptionSet {
            let rawValue: UInt32
            
            init(rawValue: UInt32) {
                self.rawValue = rawValue
            }
            
            /// The client is notified if a file-name changes.
            static let FILE_NAME    = CompletionFilter(rawValue: 0x00000001)
            /// The client is notified if a directory name changes.
            static let DIR_NAME     = CompletionFilter(rawValue: 0x00000002)
            /// The client is notified if a file's attributes change.
            static let ATTRIBUTES   = CompletionFilter(rawValue: 0x00000004)
            /// The client is notified if a file's size changes.
            static let SIZE         = CompletionFilter(rawValue: 0x00000008)
            /// The client is notified if the last write time of a file changes.
            static let LAST_WRITE   = CompletionFilter(rawValue: 0x00000010)
            /// The client is notified if the last access time of a file changes.
            static let LAST_ACCESS  = CompletionFilter(rawValue: 0x00000020)
            /// The client is notified if the creation time of a file changes.
            static let CREATION     = CompletionFilter(rawValue: 0x00000040)
            /// The client is notified if a file's extended attributes (EAs) change.
            static let EA           = CompletionFilter(rawValue: 0x00000080)
            /// The client is notified of a file's access control list (ACL) settings change.
            static let SECURITY     = CompletionFilter(rawValue: 0x00000100)
            /// The client is notified if a named stream is added to a file.
            static let STREAM_NAME  = CompletionFilter(rawValue: 0x00000200)
            /// The client is notified if the size of a named stream is changed.
            static let STREAM_SIZE  = CompletionFilter(rawValue: 0x00000400)
            /// The client is notified if a named stream is modified.
            static let STREAM_WRITE = Flags(rawValue: 0x00000800)
            
            static let all = CompletionFilter(rawValue: 0x00000FFF)
            static let list: CompletionFilter = [.FILE_NAME, .DIR_NAME]
        }
    }
    
    struct ChangeNotifyResponse: SMBResponseBody {
        let notifications: [(action: FileNotifyAction, fileName: String)]
        
        init?(data: Data) {
            let maxLoop = 1000
            var i = 0
            var result = [(action: FileNotifyAction, fileName: String)]()
            
            var offset = 0
            while i < maxLoop {
                let nextOffset: UInt32 = data.scanValue(start: offset) ?? 0
                let actionValue: UInt32 = data.scanValue(start: offset + 4) ?? 0
                let action = FileNotifyAction(rawValue: actionValue)
                
                let fileNameLen = Int(data.scanValue(start: offset + 8) as UInt32? ?? 0)
                let fileName = data.scanString(start: offset + 12, length: fileNameLen, using: .utf16) ?? ""
                result.append((action: action, fileName: fileName))
                
                offset += Int(nextOffset)
                if nextOffset == 0 {
                    break
                }
                i += 1
            }
            
            self.notifications = result
        }
    }
    
    struct FileNotifyAction: Option {
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        init(_ rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        let rawValue: UInt32
        
        /// The file was added to the directory.
        public static let ADDED = FileNotifyAction(0x00000001)
        /// The file was removed from the directory.
        public static let REMOVED = FileNotifyAction(0x00000002)
        /// The file was modified. This can be a change to the data or attributes of the file.
        public static let MODIFIED = FileNotifyAction(0x00000003)
        /// The file was renamed, and this is the old name. If the new name resides outside of the directory being monitored, the client will not receive the FILE_ACTION_RENAMED_NEW_NAME bit value.
        public static let RENAMED_OLD_NAME = FileNotifyAction(0x00000004)
        /// The file was renamed, and this is the new name. If the old name resides outside of the directory being monitored, the client will not receive the FILE_ACTION_RENAME_OLD_NAME bit value.
        public static let RENAMED_NEW_NAME = FileNotifyAction(0x00000005)
        /// The file was added to a named stream.
        public static let ADDED_STREAM = FileNotifyAction(0x00000006)
        /// The file was removed from the named stream.
        public static let REMOVED_STREAM = FileNotifyAction(0x00000007)
        /// The file was modified. This can be a change to the data or attributes of the file.
        public static let MODIFIED_STREAM = FileNotifyAction(0x00000008)
        /// An object ID was removed because the file the object ID referred to was deleted. This notification is only sent when the directory being monitored is the special directory "\$Extend\$ObjId:$O:$INDEX_ALLOCATION".
        public static let REMOVED_BY_DELETE = FileNotifyAction(0x00000009)
        /// An attempt to tunnel object ID information to a file being created or renamed failed because the object ID is in use by another file on the same volume. This notification is only sent when the directory being monitored is the special directory "\$Extend\$ObjId:$O:$INDEX_ALLOCATION".
        public static let NOT_TUNNELLED = FileNotifyAction(0x0000000A)
        /// An attempt to tunnel object ID information to a file being renamed failed because the file already has an object ID. This notification is only sent when the directory being monitored is the special directory "\$Extend\$ObjId:$O:$INDEX_ALLOCATION".
        public static let TUNNELLED_ID_COLLISION = FileNotifyAction(0x0000000B)
    }
}
