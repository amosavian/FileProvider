//
//  FileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/// Containts path and attributes of a file or resource.
open class FileObject {
    open internal(set) var allValues: [String: Any]
    
    internal init(allValues: [String: Any]) {
        self.allValues = allValues
    }
    
    internal init(absoluteURL: URL? = nil, name: String, path: String) {
        self.allValues = [String: Any]()
        self.absoluteURL = absoluteURL
        self.name = name
        self.path = path
    }
    
    /// url to access the resource, not supported by Dropbox provider
    open internal(set) var absoluteURL: URL? {
        get {
            return allValues["NSURLAbsoluteURLKey"] as? URL
        }
        set {
            allValues["NSURLAbsoluteURLKey"] = newValue
        }
    }
    
    /// Name of the file, usually equals with the last path component
    open internal(set) var name: String {
        get {
            return allValues[URLResourceKey.nameKey.rawValue] as! String
        }
        set {
            allValues[URLResourceKey.nameKey.rawValue] = newValue
        }
    }
    
    /// Relative path of file object
    open internal(set) var path: String {
        get {
            return allValues[URLResourceKey.pathKey.rawValue] as! String
        }
        set {
            allValues[URLResourceKey.pathKey.rawValue] = newValue
        }
    }
    
    /// Size of file on disk, return -1 for directories.
    open internal(set) var size: Int64 {
        get {
            return (allValues[URLResourceKey.fileSizeKey.rawValue] as? NSNumber)?.int64Value ?? -1
        }
        set {
            allValues[URLResourceKey.fileSizeKey.rawValue] = Int(exactly: newValue) ?? Int.max
        }
    }
    
    /// The time contents of file has been created, returns nil if not set
    open internal(set) var creationDate: Date? {
        get {
            return allValues[URLResourceKey.creationDateKey.rawValue] as? Date
        }
        set {
            allValues[URLResourceKey.creationDateKey.rawValue] = newValue
        }
    }
    
    /// The time contents of file has been modified, returns nil if not set
    open internal(set) var modifiedDate: Date? {
        get {
            return allValues[URLResourceKey.contentModificationDateKey.rawValue] as? Date
        }
        set {
            allValues[URLResourceKey.contentModificationDateKey.rawValue] = newValue
        }
    }
    
    /// return resource type of file, usually directory, regular or symLink
    open internal(set) var type: URLFileResourceType? {
        get {
            return allValues[URLResourceKey.fileResourceTypeKey.rawValue] as? URLFileResourceType
        }
        set {
            allValues[URLResourceKey.fileResourceTypeKey.rawValue] = newValue
        }
    }
    
    @available(*, deprecated, message: "Use FileObject.type property instead.")
    open var fileType: URLFileResourceType? {
        return self.type
    }
    
    /// File is hidden either because begining with dot or filesystem flags
    /// Setting this value on a file begining with dot has no effect
    open internal(set) var isHidden: Bool {
        get {
            return allValues[URLResourceKey.isHiddenKey.rawValue] as? Bool ?? false
        }
        set {
            allValues[URLResourceKey.isHiddenKey.rawValue] = newValue
        }
    }
    
    /// File can not be written
    open internal(set) var isReadOnly: Bool {
        get {
            return !(allValues[URLResourceKey.isWritableKey.rawValue] as? Bool ?? true)
        }
        set {
            allValues[URLResourceKey.isWritableKey.rawValue] = !newValue
        }
    }
    
    /// File is a Directory
    open var isDirectory: Bool {
        return self.type == .directory
    }
    
    /// File is a normal file
    open var isRegularFile: Bool {
        return self.type == .regular
    }
    
    /// File is a Symbolic link
    open var isSymLink: Bool {
        return self.type == .symbolicLink
    }
}

/// Sorting FileObject array by given criteria, not thread-safe
public struct FileObjectSorting {
    
    /// Determines sort kind by which item of File object
    public enum SortType {
        /// Sorting by default Finder (case-insensitive) behavior
        case name
        /// Sorting by case-sensitive form of file name
        case nameCaseSensitive
        /// Sorting by case-in sensitive form of file name
        case nameCaseInsensitive
        /// Sorting by file type
        case `extension`
        /// Sorting by file modified date
        case modifiedDate
        /// Sorting by file creation date
        case creationDate
        /// Sorting by file modified date
        case size
        
        /// all sort types
        static var allItems: [SortType] {
            return [.name, .nameCaseSensitive, .nameCaseInsensitive, .extension,
                    .modifiedDate,.creationDate, .size]
        }
    }
    
    public let sortType: SortType
    /// puts A before Z, default is true
    public let ascending: Bool
    /// puts directories on top, regardless of other attributes, default is false
    public let isDirectoriesFirst: Bool
    
    public static let nameAscending = FileObjectSorting(type: .name, ascending: true)
    public static let nameDesceding = FileObjectSorting(type: .name, ascending: false)
    public static let sizeAscending = FileObjectSorting(type: .size, ascending: true)
    public static let sizeDesceding = FileObjectSorting(type: .size, ascending: false)
    public static let extensionAscending = FileObjectSorting(type: .extension, ascending: true)
    public static let extensionDesceding = FileObjectSorting(type: .extension, ascending: false)
    public static let modifiedAscending = FileObjectSorting(type: .modifiedDate, ascending: true)
    public static let modifiedDesceding = FileObjectSorting(type: .modifiedDate, ascending: false)
    public static let createdAscending = FileObjectSorting(type: .creationDate, ascending: true)
    public static let createdDesceding = FileObjectSorting(type: .creationDate, ascending: false)
    
    public init (type: SortType, ascending: Bool = true, isDirectoriesFirst: Bool = false) {
        self.sortType = type
        self.ascending = ascending
        self.isDirectoriesFirst = isDirectoriesFirst
    }
    
    /// Sorts array of FileObjects by criterias set in properties
    public func sort(_ files: [FileObject]) -> [FileObject] {
        return files.sorted {
            if isDirectoriesFirst {
                if ($0.isDirectory) && !($1.isDirectory) {
                    return true
                }
                if !($0.isDirectory) && ($1.isDirectory) {
                    return false
                }
            }
            switch sortType {
            case .name:
                return ($0.name).localizedStandardCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
            case .nameCaseSensitive:
                return ($0.name).localizedCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
            case .nameCaseInsensitive:
                return ($0.name).localizedCaseInsensitiveCompare($1.name) == (ascending ? .orderedAscending : .orderedDescending)
            case .extension:
                let kind1 = $0.isDirectory ? "folder" : ($0.path as NSString).pathExtension
                let kind2 = $1.isDirectory ? "folder" : ($1.path as NSString).pathExtension
                return kind1.localizedCaseInsensitiveCompare(kind2) == (ascending ? .orderedAscending : .orderedDescending)
            case .modifiedDate:
                let fileMod1 = $0.modifiedDate ?? Date.distantPast
                let fileMod2 = $1.modifiedDate ?? Date.distantPast
                return ascending ? fileMod1 < fileMod2 : fileMod1 > fileMod2
            case .creationDate:
                let fileCreation1 = $0.creationDate ?? Date.distantPast
                let fileCreation2 = $1.creationDate ?? Date.distantPast
                return ascending ? fileCreation1 < fileCreation2 : fileCreation1 > fileCreation2
            case .size:
                return ascending ? $0.size < $1.size : $0.size > $1.size
            }
        }
    }
}

extension URLFileResourceType {
    public init(fileTypeValue: FileAttributeType) {
        switch fileTypeValue {
        case FileAttributeType.typeCharacterSpecial: self = .characterSpecial
        case FileAttributeType.typeDirectory: self = .directory
        case FileAttributeType.typeBlockSpecial: self = .blockSpecial
        case FileAttributeType.typeRegular: self = .regular
        case FileAttributeType.typeSymbolicLink: self = .symbolicLink
        case FileAttributeType.typeSocket: self = .socket
        case FileAttributeType.typeUnknown: self = .unknown
        default: self = .unknown
        }
    }
}

internal extension URL {
    var uw_scheme: String {
        return self.scheme ?? ""
    }
}

internal func jsonToDictionary(_ jsonString: String) -> [String: AnyObject]? {
    guard let data = jsonString.data(using: .utf8) else {
        return nil
    }
    if let dic = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] {
        return dic
    }
    return nil
}

internal func dictionaryToJSON(_ dictionary: [String: AnyObject]) -> String? {
    if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: JSONSerialization.WritingOptions()) {
        return String(data: data, encoding: .utf8)
    }
    return nil
}
