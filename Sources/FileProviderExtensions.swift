//
//  FileProviderExtensions.swift
//  FileProvider
//
//  Created by Amir Abbas on 12/27/1395 AP.
//
//

import Foundation

extension Array where Element: FileObject {
    /// Returns a sorted array of `FileObject`s by criterias set in attributes.
    public func sort(by type: FileObjectSorting.SortType, ascending: Bool = true, isDirectoriesFirst: Bool = false) -> [Element] {
        let sorting = FileObjectSorting(type: type, ascending: ascending, isDirectoriesFirst: isDirectoriesFirst)
        return sorting.sort(self) as! [Element]
    }
    
    /// Sorts array of `FileObject`s by criterias set in attributes.
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
    static let fileURLKey = URLResourceKey(rawValue: "NSURLFileURLKey")
    static let serverDateKey = URLResourceKey(rawValue: "NSURLServerDateKey")
    static let entryTagKey = URLResourceKey(rawValue: "NSURLEntryTagKey")
    static let mimeTypeKey = URLResourceKey(rawValue: "NSURLMIMETypeIdentifierKey")
    
    @available(*, deprecated, renamed: "fileURLKey")
    static let fileURL = fileURLKey
    @available(*, deprecated, renamed: "serverDateKey")
    static let serverDate = serverDateKey
    @available(*, deprecated, renamed: "entryTagKey")
    static let entryTag = entryTagKey
    @available(*, deprecated, renamed: "mimeTypeKey")
    static let mimeType = mimeTypeKey
}

internal extension URL {
    var uw_scheme: String {
        return self.scheme ?? ""
    }
    
    var fileIsDirectory: Bool {
        return (try? self.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
    
    var fileSize: Int64 {
        return Int64((try? self.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1)
    }
    
    var fileExists: Bool {
        return self.isFileURL && FileManager.default.fileExists(atPath: self.path)
    }
}

internal extension Data {
    internal var isPDF: Bool {
        return self.count > 4 && self.scanString(length: 4, using: .ascii) == "%PDF"
    }
    
    init? (jsonDictionary dictionary: [String: AnyObject]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return nil
        }
        self = data
    }
    
    func deserializeJSON() -> [String: AnyObject]? {
        if let dic = try? JSONSerialization.jsonObject(with: self, options: []) as? [String: AnyObject] {
            return dic
        }
        return nil
    }
    
    init<T>(value: T) {
        var value = value
        self = Data(buffer: UnsafeBufferPointer(start: &value, count: 1))
    }
    
    func scanValue<T>() -> T? {
        guard MemoryLayout<T>.size <= self.count else { return nil }
        return self.withUnsafeBytes { $0.pointee }
    }
    
    func scanValue<T>(start: Int) -> T? {
        let length = MemoryLayout<T>.size
        guard self.count >= start + length else { return nil }
        return self.subdata(in: start..<start+length).withUnsafeBytes { $0.pointee }
    }
    
    func scanString(start: Int = 0, length: Int, using encoding: String.Encoding = .utf8) -> String? {
        guard self.count >= start + length else { return nil }
        return String(data: self.subdata(in: start..<start+length), encoding: encoding)
    }
    
    static func mapMemory<T, U>(from: T) -> U? {
        guard MemoryLayout<T>.size >= MemoryLayout<U>.size else { return nil }
        let data = Data(value: from)
        return data.scanValue()
    }
}

internal extension String {
    init? (jsonDictionary: [String: AnyObject]) {
        guard let data = Data(jsonDictionary: jsonDictionary) else {
            return nil
        }
        self.init(data: data, encoding: .utf8)
    }
    
    func deserializeJSON(using encoding: String.Encoding = .utf8) -> [String: AnyObject]? {
        guard let data = self.data(using: encoding) else {
            return nil
        }
        return data.deserializeJSON()
    }
}

internal extension TimeInterval {
    internal var formatshort: String {
        var result = "0:00"
        if self < TimeInterval(Int32.max) {
            result = ""
            var time = DateComponents()
            time.hour   = Int(self / 3600)
            time.minute = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
            time.second = Int(self.truncatingRemainder(dividingBy: 60))
            let formatter = NumberFormatter()
            formatter.paddingCharacter = "0"
            formatter.minimumIntegerDigits = 2
            formatter.maximumFractionDigits = 0
            let formatterFirst = NumberFormatter()
            formatterFirst.maximumFractionDigits = 0
            if time.hour! > 0 {
                result = "\(formatterFirst.string(from: NSNumber(value: time.hour!))!):\(formatter.string(from: NSNumber(value: time.minute!))!):\(formatter.string(from: NSNumber(value: time.second!))!)"
            } else {
                result = "\(formatterFirst.string(from: NSNumber(value: time.minute!))!):\(formatter.string(from: NSNumber(value: time.second!))!)"
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        return result
    }
}

extension Date {
   init?(rfcString: String) {
        let dateFor: DateFormatter = DateFormatter()
        dateFor.locale = Locale(identifier: "en_US")
        dateFor.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"
        if let rfc3339 = dateFor.date(from: rfcString) {
            self = rfc3339
            return
        }
        dateFor.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss z"
        if let rfc1123 = dateFor.date(from: rfcString) {
            self = rfc1123
             return
        }
        dateFor.dateFormat = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
        if let rfc850 = dateFor.date(from: rfcString) {
            self = rfc850
             return
        }
        dateFor.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"
        if let asctime = dateFor.date(from: rfcString) {
            self = asctime
             return
        }
        
        return nil
    }
    
    internal func rfc3339utc() -> String {
        let fm = DateFormatter()
        fm.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
        fm.timeZone = TimeZone(identifier: "UTC")
        fm.locale = Locale(identifier: "en_US_POSIX")
        return fm.string(from: self)
    }
}

extension NSPredicate {
    func findValue(forKey key: String?, operator op: NSComparisonPredicate.Operator? = nil) -> Any? {
        let val = findAllValues(forKey: key).lazy.filter { (op == nil || $0.operator == op!) && !$0.not }
        return val.first?.value
    }
    
    func findAllValues(forKey key: String?) -> [(value: Any, operator: NSComparisonPredicate.Operator, not: Bool)] {
        if let cQuery = self as? NSCompoundPredicate {
            let find = cQuery.subpredicates.flatMap { ($0 as! NSPredicate).findAllValues(forKey: key) }
            if cQuery.compoundPredicateType == .not {
                return find.map { return ($0.value, $0.operator, !$0.not) }
            }
            return find
        } else if let cQuery = self as? NSComparisonPredicate {
            if cQuery.leftExpression.expressionType == .keyPath, key == nil || cQuery.leftExpression.keyPath == key!, let const = cQuery.rightExpression.constantValue {
                return [(value: const, operator: cQuery.predicateOperatorType, false)]
            }
            if cQuery.rightExpression.expressionType == .keyPath, key == nil || cQuery.rightExpression.keyPath == key!, let const = cQuery.leftExpression.constantValue {
                return [(value: const, operator: cQuery.predicateOperatorType, false)]
            }
            return []
        } else {
            return []
        }
    }
}

extension URLError.Code: FoundationErrorEnum {}
extension CocoaError.Code: FoundationErrorEnum {}
