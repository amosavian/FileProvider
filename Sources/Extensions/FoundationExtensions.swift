//
//  FileProviderExtensions.swift
//  FileProvider
//
//  Created by Amir Abbas on 12/27/1395 AP.
//
//

import Foundation

public extension Array where Element: FileObject {
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

public extension Sequence where Iterator.Element == UInt8 {
    func hexString() -> String {
        return self.map{String(format: "%02X", $0)}.joined()
    }
}

public extension URLFileResourceType {
    /// **FileProvider** returns corresponding `URLFileResourceType` of a `FileAttributeType` value
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

public extension URLResourceKey {
    /// **FileProvider** returns url of file object.
    public static let fileURLKey = URLResourceKey(rawValue: "NSURLFileURLKey")
    /// **FileProvider** returns modification date of file in server
    public static let serverDateKey = URLResourceKey(rawValue: "NSURLServerDateKey")
    /// **FileProvider** returns HTTP ETag string of remote resource
    public static let entryTagKey = URLResourceKey(rawValue: "NSURLEntryTagKey")
    /// **FileProvider** returns MIME type of file, if returned by server
    public static let mimeTypeKey = URLResourceKey(rawValue: "NSURLMIMETypeIdentifierKey")
    /// **FileProvider** returns either file is encrypted or not
    public static let isEncryptedKey = URLResourceKey(rawValue: "NSURLIsEncryptedKey")
}

public extension ProgressUserInfoKey {
    /// **FileProvider** returns associated `FileProviderOperationType`
    public static let fileProvderOperationTypeKey = ProgressUserInfoKey("FilesProviderOperationTypeKey")
    /// **FileProvider** returns start date/time of operation
    public static let startingTimeKey = ProgressUserInfoKey("NSProgressStartingTimeKey")
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

public extension URLRequest {
    /// Defines HTTP Authentication method required to access
    public enum AuthenticationType {
        /// Basic method for authentication
        case basic
        /// Digest method for authentication
        case digest
        /// OAuth 1.0 method for authentication (OAuth)
        case oAuth1
        /// OAuth 2.0 method for authentication (Bearer)
        case oAuth2
    }
}

struct Quality<T> {
    let value: T
    let quality: Float
    
    var stringifed: String {
        var representaion = String(describing: value)
        let quality = min(1, max(self.quality, 0))
        if let value = value as? Locale {
            representaion = "\(value.identifier.replacingOccurrences(of: "_", with: "-"))"
        }
        if let value = value as? String.Encoding {
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(value.rawValue)
            representaion = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? ?? "*"
        }
        let qualityDesc = String(format: "%.1f", quality)
        return "\(representaion); q=\(qualityDesc)"
    }
}

internal extension URLRequest {
    mutating func set(httpAuthentication credential: URLCredential?, with type: AuthenticationType) {
        func base64(_ str: String) -> String {
            let plainData = str.data(using: .utf8)
            let base64String = plainData!.base64EncodedString(options: [])
            return base64String
        }
        
        guard let credential = credential else { return }
        switch type {
        case .basic:
            let user = credential.user?.replacingOccurrences(of: ":", with: "") ?? ""
            let pass = credential.password ?? ""
            let authStr = "\(user):\(pass)"
            if let base64Auth = authStr.data(using: .utf8)?.base64EncodedString() {
                self.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        case .digest:
            // handled by RemoteSessionDelegate
            break
        case .oAuth1:
            if let oauth = credential.password {
                self.setValue("OAuth \(oauth)", forHTTPHeaderField: "Authorization")
            }
        case .oAuth2:
            if let bearer = credential.password {
                self.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            }
        }
    }
    
    mutating func set(httpAcceptCharset acceptCharset: String.Encoding) {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(acceptCharset.rawValue)
        if let charsetString = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? {
            self.addValue(charsetString, forHTTPHeaderField: "Accept-Charset")
        }
    }
    
    mutating func set(httpAcceptCharset acceptCharset: Quality<String.Encoding>) {
        self.addValue(acceptCharset.stringifed, forHTTPHeaderField: "Accept-Charset")
    }
    
    mutating func set(httpAcceptCharsets acceptCharsets: [String.Encoding]) {
        self.setValue(nil, forHTTPHeaderField: "Accept-Charset")
        for charset in acceptCharsets {
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(charset.rawValue)
            if let charsetString = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? {
                self.addValue(charsetString, forHTTPHeaderField: "Accept-Charset")
            }
        }
    }
    
    mutating func set(httpAcceptCharsets acceptCharsets: [Quality<String.Encoding>]) {
        self.setValue(nil, forHTTPHeaderField: "Accept-Charset")
        for charset in acceptCharsets.sorted(by: { $0.quality > $1.quality }) {
            self.addValue(charset.stringifed, forHTTPHeaderField: "Accept-Charset")
        }
    }
    
    enum Encoding: String {
        case all = "*"
        case identity
        case gzip
        case deflate
    }
    
    mutating func set(httpAcceptEncoding acceptEncoding: Encoding) {
        self.addValue(acceptEncoding.rawValue, forHTTPHeaderField: "Accept-Encoding")
    }
    
    mutating func set(httpAcceptEncoding acceptEncoding: Quality<Encoding>) {
        self.addValue(acceptEncoding.stringifed, forHTTPHeaderField: "Accept-Encoding")
    }
    
    mutating func set(httpAcceptEncodings acceptEncodings: [Encoding]) {
        self.setValue(nil, forHTTPHeaderField: "Accept-Encoding")
        for encoding in acceptEncodings {
            self.addValue(encoding.rawValue, forHTTPHeaderField: "Accept-Encoding")
        }
    }
    
    mutating func set(httpAcceptEncodings acceptEncodings: [Quality<Encoding>]) {
        self.setValue(nil, forHTTPHeaderField: "Accept-Encoding")
        for encoding in acceptEncodings.sorted(by: { $0.quality > $1.quality }) {
            self.addValue(encoding.stringifed, forHTTPHeaderField: "Accept-Encoding")
        }
    }
    
    mutating func set(httpAcceptLanguage acceptLanguage: Locale) {
        let langCode = acceptLanguage.identifier.replacingOccurrences(of: "_", with: "-")
        self.addValue(langCode, forHTTPHeaderField: "Accept-Language")
    }
    
    mutating func set(httpAcceptLanguage acceptLanguage: Quality<Locale>) {
        self.addValue(acceptLanguage.stringifed, forHTTPHeaderField: "Accept-Language")
    }
    
    mutating func set(httpAcceptLanguages acceptLanguages: [Locale]) {
        self.setValue(nil, forHTTPHeaderField: "Accept-Language")
        for lang in acceptLanguages {
            let langCode = lang.identifier.replacingOccurrences(of: "_", with: "-")
            self.addValue(langCode, forHTTPHeaderField: "Accept-Language")
        }
    }
    
    mutating func set(httpAcceptLanguages acceptLanguages: [Quality<Locale>]) {
        self.setValue(nil, forHTTPHeaderField: "Accept-Language")
        for lang in acceptLanguages.sorted(by: { $0.quality > $1.quality} ) {
            self.addValue(lang.stringifed, forHTTPHeaderField: "Accept-Language")
        }
    }
    
    mutating func set(httpRangeWithOffset offset: Int64, length: Int) {
        if length > 0 {
            self.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            self.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
    }
    
    mutating func set(httpRange range: Range<Int>) {
        let range = max(0, range.lowerBound)..<range.upperBound
        if range.upperBound < Int.max && range.count > 0 {
            self.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        } else if range.lowerBound > 0 {
            self.setValue("bytes=\(range.lowerBound)-", forHTTPHeaderField: "Range")
        }
    }
    
    struct ContentMIMEType: RawRepresentable {
        public var rawValue: String
        public typealias RawValue = String
        
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
        
        static let javascript = ContentMIMEType(rawValue: "application/javascript")
        static let json = ContentMIMEType(rawValue: "application/json")
        static let pdf = ContentMIMEType(rawValue: "application/pdf")
        static let stream = ContentMIMEType(rawValue: "application/octet-stream")
        static let zip = ContentMIMEType(rawValue: "application/zip")
        
        // Texts
        static let css = ContentMIMEType(rawValue: "text/css")
        static let html = ContentMIMEType(rawValue: "text/html")
        static let plainText = ContentMIMEType(rawValue: "text/plain")
        static let xml = ContentMIMEType(rawValue: "text/xml")
        
        // Images
        static let gif = ContentMIMEType(rawValue: "image/gif")
        static let jpeg = ContentMIMEType(rawValue: "image/jpeg")
        static let png = ContentMIMEType(rawValue: "image/png")
    }
    
    mutating func set(httpContentType contentType: ContentMIMEType, charset: String.Encoding? = nil) {
        var parameter = ""
        if let charset = charset {
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(charset.rawValue)
            if let charsetString = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? {
                parameter = ";charset=" + charsetString
            }
        }
        
        self.setValue(contentType.rawValue + parameter, forHTTPHeaderField: "Content-Type")
    }
    
    mutating func set(dropboxArgKey requestDictionary: [String: AnyObject]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestDictionary, options: []) else {
            return
        }
        guard var jsonString = String(data: jsonData, encoding: .utf8) else { return }
        jsonString = jsonString.asciiEscaped().replacingOccurrences(of: "\\/", with: "/")
        
        self.setValue(jsonString, forHTTPHeaderField: "Dropbox-API-Arg")
    }
}

internal extension CharacterSet {
    static let filePathAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ":"))
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
    
    func asciiEscaped() -> String {
        var res = ""
        for char in self.unicodeScalars {
            let substring = String(char)
            if substring.canBeConverted(to: .ascii) {
                res.append(substring)
            } else {
                res = res.appendingFormat("\\u%04x", char.value)
            }
        }
        return res
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

public extension Date {
    /// Date formats used commonly in internet messaging defined by various RFCs.
    public enum RFCStandards: String {
        /// Date format defined by usenet, commonly used in old implementations.
        case rfc850 = "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z"
        /// Date format defined by RFC 1132 for http.
        case rfc1123 = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss z"
        /// Date format defined by ISO 8601, also defined in RFC 3339. Used by Dropbox.
        case iso8601 = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"
        /// Date string returned by asctime() function.
        case asctime = "EEE MMM d HH':'mm':'ss yyyy"
        
        /// Equivalent to and defined by RFC 1123.
        public static let http = RFCStandards.rfc1123
        /// Equivalent to and defined by ISO 8610.
        public static let rfc3339 = RFCStandards.iso8601
        /// Equivalent to and defined by RFC 850.
        public static let usenet = RFCStandards.rfc850
        
        // Sorted by commonness
        fileprivate static let allValues: [RFCStandards] = [.rfc1123, .rfc850, .iso8601, .asctime]
    }
    
    /// Checks date string against various RFC standards and returns `Date`.
    public init?(rfcString: String) {
        let dateFor: DateFormatter = DateFormatter()
        dateFor.locale = Locale(identifier: "en_US")
        
        for standard in RFCStandards.allValues {
            dateFor.dateFormat = standard.rawValue
            if let date = dateFor.date(from: rfcString) {
                self = date
                return
            }
        }
        
        return nil
    }
    
    /// Formats date according to RFCs standard.
    public func format(with standard: RFCStandards, locale: Locale? = nil, timeZone: TimeZone? = nil) -> String {
        let fm = DateFormatter()
        fm.dateFormat = standard.rawValue
        fm.timeZone = timeZone ?? TimeZone(identifier: "UTC")
        fm.locale = locale ?? Locale(identifier: "en_US_POSIX")
        return fm.string(from: self)
    }
}

internal extension NSPredicate {
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
