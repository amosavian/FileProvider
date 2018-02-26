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
    
    public init(allValues: [URLResourceKey: Any]) {
        self.allValues = allValues
    }
    
    internal init(url: URL?, name: String, path: String) {
        self.allValues = [URLResourceKey: Any]()
        if let url = url {
            self.url = url
        }
        self.name = name
        self.path = path
    }
    
    /// URL to access the resource, can be a relative URL against base URL.
    /// not supported by Dropbox provider.
    open internal(set) var url: URL {
        get {
            if let url = allValues[.fileURLKey] as? URL {
                return url
            } else {
                let path = self.path.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? self.path
                return URL(string: path) ?? URL(string: "/")!
            }
        }
        set {
            allValues[.fileURLKey] = newValue
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
    
    /// Count of children items of a driectory.
    open internal(set) var childrensCount: Int? {
        get {
            return allValues[.childrensCount] as? Int
        }
        set {
            allValues[.childrensCount] = newValue
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
    open internal(set) var type: URLFileResourceType {
        get {
            return allValues[.fileResourceTypeKey] as? URLFileResourceType ?? .unknown
        }
        set {
            allValues[.fileResourceTypeKey] = newValue
        }
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
        if rhs === lhs  {
            return true
        }
        #if swift(>=3.1)
        if Swift.type(of: lhs) != Swift.type(of: rhs) {
            return false
        }
        #else
        if type(of: lhs) != type(of: rhs) {
            return false
        }
        #endif
        
        if let rurl = rhs.allValues[.fileURLKey] as? URL, let lurl = lhs.allValues[.fileURLKey] as? URL {
            return rurl == lurl && rhs.size == lhs.size
        }
        return rhs.path == lhs.path && rhs.size == lhs.size && rhs.modifiedDate == lhs.modifiedDate
    }
    
    internal func mapPredicate() -> [String: Any] {
        let mapDict: [URLResourceKey: String] = [.fileURLKey: "url", .nameKey: "name", .pathKey: "path",
                                                 .fileSizeKey: "fileSize", .creationDateKey: "creationDate",
                                                 .contentModificationDateKey: "modifiedDate", .isHiddenKey: "isHidden",
                                                 .isWritableKey: "isWritable", .serverDateKey: "serverDate",
                                                 .entryTagKey: "entryTag", .mimeTypeKey: "mimeType"]
        let typeDict: [URLFileResourceType: String] = [.directory: "directory", .regular: "regular",
                                                       .symbolicLink: "symbolicLink", .unknown: "unknown"]
        var result = [String: Any]()
        for (key, value) in allValues {
            if let convertkey = mapDict[key] {
                result[convertkey] = value
            }
        }
        result["eTag"] = result["entryTag"]
        result["filesize"] = result["fileSize"]
        result["isReadOnly"] = self.isReadOnly
        result["isDirectory"] = self.isDirectory
        result["isRegularFile"] = self.isRegularFile
        result["isSymLink"] = self.isSymLink
        result["type"] = typeDict[self.type] ?? "unknown"
        return result
    }
    
    /// Converts macOS spotlight query for searching files to a query that can be used for `searchFiles()` method
    static public func convertPredicate(fromSpotlight query: NSPredicate) -> NSPredicate {
        let mapDict: [String: URLResourceKey] = [NSMetadataItemURLKey: .fileURLKey, NSMetadataItemFSNameKey: .nameKey,
                                                 NSMetadataItemPathKey: .pathKey, NSMetadataItemFSSizeKey: .fileSizeKey,
                                                 NSMetadataItemFSCreationDateKey: .creationDateKey, NSMetadataItemFSContentChangeDateKey: .contentModificationDateKey,
                                                 "kMDItemFSInvisible": .isHiddenKey, "kMDItemFSIsWriteable": .isWritableKey,
                                                 "kMDItemKind": .mimeTypeKey]
        
        if let cQuery = query as? NSCompoundPredicate {
            let newSub = cQuery.subpredicates.map { convertPredicate(fromSpotlight: $0 as! NSPredicate) }
            switch cQuery.compoundPredicateType {
            case .and: return NSCompoundPredicate(andPredicateWithSubpredicates: newSub)
            case .not: return NSCompoundPredicate(notPredicateWithSubpredicate: newSub[0])
            case .or:  return NSCompoundPredicate(orPredicateWithSubpredicates: newSub)
            }
        } else if let cQuery = query as? NSComparisonPredicate {
            var newLeft = cQuery.leftExpression
            var newRight = cQuery.rightExpression
            if newLeft.expressionType == .keyPath, let newKey = mapDict[newLeft.keyPath] {
                newLeft = NSExpression(forKeyPath: newKey.rawValue)
            }
            if newRight.expressionType == .keyPath, let newKey = mapDict[newRight.keyPath] {
                newRight = NSExpression(forKeyPath: newKey.rawValue)
            }
            return NSComparisonPredicate(leftExpression: newLeft, rightExpression: newRight, modifier: cQuery.comparisonPredicateModifier, type: cQuery.predicateOperatorType, options: cQuery.options)
        } else {
            return query
        }
    }
}

/// Containts attributes of a provider.
open class VolumeObject {
    /// A `Dictionary` contains volume information,  using `URLResourceKey` keys.
    open internal(set) var allValues: [URLResourceKey: Any]
    
    public init(allValues: [URLResourceKey: Any]) {
        self.allValues = allValues
    }
    
    /// The root directory of the resource’s volume, returned as an `URL` object.
    open internal(set) var url: URL? {
        get {
            return allValues[.volumeURLKey] as? URL
        }
        set {
            allValues[.volumeURLKey] = newValue
        }
    }
    
    /// The name of the volume.
    open internal(set) var name: String? {
        get {
            return allValues[.volumeNameKey] as? String
        }
        set {
            allValues[.volumeNameKey] = newValue
        }
    }
    
    /// The root directory of the resource’s volume, returned as an `URL` object.
    open internal(set) var uuid: String? {
        get {
            return allValues[.volumeUUIDStringKey] as? String
        }
        set {
            allValues[.volumeUUIDStringKey] = newValue
        }
    }
    
    /// the volume’s capacity in bytes, return -1 if is undetermined.
    open internal(set) var totalCapacity: Int64 {
        get {
            return allValues[.volumeTotalCapacityKey] as? Int64 ?? -1
        }
        set {
            allValues[.volumeTotalCapacityKey] = newValue
        }
    }
    
    /// The volume’s available capacity in bytes.
    open internal(set) var availableCapacity: Int64 {
        get {
            return allValues[.volumeAvailableCapacityKey] as? Int64 ?? 0
        }
        set {
            allValues[.volumeAvailableCapacityKey] = newValue
        }
    }
    
    open internal(set) var usage: Int64 {
        get {
            return totalCapacity >= 0 ? totalCapacity - availableCapacity : -availableCapacity
        }
        set {
            availableCapacity = totalCapacity >= 0 ? totalCapacity - newValue : -newValue
        }
    }
    
    ///  the volume’s creation date, returned as an `Date` object, or NULL if it cannot be determined
    open internal(set) var creationDate: Date? {
        get {
            return allValues[.volumeCreationDateKey] as? Date
        }
        set {
            allValues[.volumeCreationDateKey] = newValue
        }
    }
    
    /// Determining whether the volume is read-only
    open internal(set) var isReadOnly: Bool {
        get {
            return allValues[.volumeIsReadOnlyKey] as? Bool ?? false
        }
        set {
            allValues[.volumeIsReadOnlyKey] = newValue
        }
    }
    
    @available(iOS 10.0, macOS 10.12, tvOS 10.0, *)
    open internal(set) var isEncrypted: Bool {
        get {
            return allValues[.volumeIsEncryptedKey] as? Bool ?? false
        }
        set {
            allValues[.volumeIsEncryptedKey] = !newValue
        }
    }
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
    
    /// Sorts array of `FileObject`s by criterias set in attributes.
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
