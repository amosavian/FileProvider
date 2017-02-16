//
//  FileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

/// Containts path, url and attributes of a file or resource.
open class FileObject: Equatable {
    /// A `Dictionary` contains file information,  using `URLResourceKey` keys.
    open internal(set) var allValues: [URLResourceKey: Any]
    
    internal init(allValues: [URLResourceKey: Any]) {
        self.allValues = allValues
    }
    
    internal init(url: URL, name: String, path: String) {
        self.allValues = [URLResourceKey: Any]()
        self.url = url
        self.name = name
        self.path = path
    }
    
    /// url to access the resource, not supported by Dropbox provider
    @available(*, deprecated, renamed: "url", message: "Use url.absoluteURL instead.")
    open var absoluteURL: URL? {
        return url?.absoluteURL
    }
    
    /// URL to access the resource, can be a relative URL against base URL.
    /// not supported by Dropbox provider.
    open internal(set) var url: URL? {
        get {
            return allValues[.fileURL] as? URL
        }
        set {
            allValues[.fileURL] = newValue
        }
    }
    
    /// Name of the file, usually equals with the last path component
    open internal(set) var name: String {
        get {
            return allValues[.nameKey] as! String
        }
        set {
            allValues[.nameKey] = newValue
        }
    }
    
    /// Relative path of file object
    open internal(set) var path: String {
        get {
            return allValues[.pathKey] as! String
        }
        set {
            allValues[.pathKey] = newValue
        }
    }
    
    /// Size of file on disk, return -1 for directories.
    open internal(set) var size: Int64 {
        get {
            return allValues[.fileSizeKey] as? Int64 ?? -1
        }
        set {
            allValues[.fileSizeKey] = newValue
        }
    }
    
    /// The time contents of file has been created, returns nil if not set
    open internal(set) var creationDate: Date? {
        get {
            return allValues[.creationDateKey] as? Date
        }
        set {
            allValues[.creationDateKey] = newValue
        }
    }
    
    /// The time contents of file has been modified, returns nil if not set
    open internal(set) var modifiedDate: Date? {
        get {
            return allValues[.contentModificationDateKey] as? Date
        }
        set {
            allValues[.contentModificationDateKey] = newValue
        }
    }
    
    /// return resource type of file, usually directory, regular or symLink
    open internal(set) var type: URLFileResourceType? {
        get {
            return allValues[.fileResourceTypeKey] as? URLFileResourceType
        }
        set {
            allValues[.fileResourceTypeKey] = newValue
        }
    }
    
    /// **OBSOLETED:** Use `type` property instead.
    @available(*, obsoleted: 1.0, renamed: "type", message: "Use type property instead.")
    open var fileType: URLFileResourceType? {
        return self.type
    }
    
    /// File is hidden either because begining with dot or filesystem flags
    /// Setting this value on a file begining with dot has no effect
    open internal(set) var isHidden: Bool {
        get {
            return allValues[.isHiddenKey] as? Bool ?? false
        }
        set {
            allValues[.isHiddenKey] = newValue
        }
    }
    
    /// File can not be written
    open internal(set) var isReadOnly: Bool {
        get {
            return !(allValues[.isWritableKey] as? Bool ?? true)
        }
        set {
            allValues[.isWritableKey] = !newValue
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
    
    /// Check `FileObject` equality
    public static func ==(lhs: FileObject, rhs: FileObject) -> Bool {
        if rhs === lhs {
            return true
        }
        if type(of: lhs) != type(of: rhs) {
            return false
        }
        if let rurl = rhs.url, let lurl = lhs.url {
            return rurl == lurl
        }
        return rhs.path == lhs.path && rhs.size == lhs.size && rhs.modifiedDate == lhs.modifiedDate
    }
}

internal func resolve(dateString: String) -> Date? {
    let dateFor: DateFormatter = DateFormatter()
    dateFor.locale = Locale(identifier: "en_US")
    dateFor.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"
    if let rfc3339 = dateFor.date(from: dateString) {
        return rfc3339
    }
    dateFor.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss z"
    if let rfc1123 = dateFor.date(from: dateString) {
        return rfc1123
    }
    dateFor.dateFormat = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
    if let rfc850 = dateFor.date(from: dateString) {
        return rfc850
    }
    dateFor.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
    if let asctime = dateFor.date(from: dateString) {
        return asctime
    }
    
    return nil
}

internal func rfc3339utc(of date:Date) -> String {
    let fm = DateFormatter()
    fm.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
    fm.timeZone = TimeZone(identifier:"UTC")
    fm.locale = Locale(identifier:"en_US_POSIX")
    return fm.string(from:date)
}

/// Sorting FileObject array by given criteria, **not thread-safe**
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
    
    /// Initializes a `FileObjectSorting` allows to sort an `Array` of `FileObject`.
    ///
    /// - Parameters:
    ///   - type: Determines to sort based on which file property.
    ///   - ascending: `true` of resulting `Array` is ascending
    ///   - isDirectoriesFirst: Puts directoris on the top of resulting `Array`.
    public init (type: SortType, ascending: Bool = true, isDirectoriesFirst: Bool = false) {
        self.sortType = type
        self.ascending = ascending
        self.isDirectoriesFirst = isDirectoriesFirst
    }
    
    /// Sorts array of `FileObject`s by criterias set in properties
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

extension Array where Element: FileObject {
    /// Returns a sorted array of `FileObject`s by criterias set in properties.
    public func sort(by type: FileObjectSorting.SortType, ascending: Bool = true, isDirectoriesFirst: Bool = false) -> [Element] {
        let sorting = FileObjectSorting(type: type, ascending: ascending, isDirectoriesFirst: isDirectoriesFirst)
        return sorting.sort(self) as! [Element]
    }
    
    /// Sorts array of `FileObject`s by criterias set in properties
    public mutating func sorted(by type: FileObjectSorting.SortType, ascending: Bool = true, isDirectoriesFirst: Bool = false) {
        self = self.sort(by: type, ascending: ascending, isDirectoriesFirst: isDirectoriesFirst)
    }
}

extension URLFileResourceType {
    /// Returns corresponding `URLFileResourceType` of a `FileAttributeType` value
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

internal extension URLResourceKey {
    static let fileURL = URLResourceKey(rawValue: "NSURLFileURLKey")
    static let serverDate = URLResourceKey(rawValue: "NSURLServerDateKey")
    static let entryTag = URLResourceKey(rawValue: "NSURLEntryTagKey")
    static let mimeType = URLResourceKey(rawValue: "NSURLMIMETypeIdentifierKey")
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
