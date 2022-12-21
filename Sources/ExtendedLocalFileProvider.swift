//
//  ExtendedLocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

#if os(macOS) || os(iOS) || os(tvOS)
import Foundation
import ImageIO
import CoreGraphics
import AVFoundation

extension LocalFileProvider: ExtendedFileProvider {
    public func thumbnailOfFileSupported(path: String) -> Bool {
        switch path.pathExtension.lowercased() {
        case LocalFileInformationGenerator.imageThumbnailExtensions.contains:
            return true
        case LocalFileInformationGenerator.audioThumbnailExtensions.contains:
            return true
        case LocalFileInformationGenerator.videoThumbnailExtensions.contains:
            return true
        case LocalFileInformationGenerator.pdfThumbnailExtensions.contains:
            return true
        case LocalFileInformationGenerator.officeThumbnailExtensions.contains:
            return true
        case LocalFileInformationGenerator.customThumbnailExtensions.contains:
            return true
        default:
            return false
        }
    }
    
    public func propertiesOfFileSupported(path: String) -> Bool {
        let fileExt = path.pathExtension.lowercased()
        switch fileExt {
        case LocalFileInformationGenerator.imagePropertiesExtensions.contains:
            return LocalFileInformationGenerator.imageProperties != nil
        case LocalFileInformationGenerator.audioPropertiesExtensions.contains:
            return LocalFileInformationGenerator.audioProperties != nil
        case LocalFileInformationGenerator.videoPropertiesExtensions.contains:
            return LocalFileInformationGenerator.videoProperties != nil
        case LocalFileInformationGenerator.pdfPropertiesExtensions.contains:
            return LocalFileInformationGenerator.pdfProperties != nil
        case LocalFileInformationGenerator.archivePropertiesExtensions.contains:
            return LocalFileInformationGenerator.archiveProperties != nil
        case LocalFileInformationGenerator.officePropertiesExtensions.contains:
            return LocalFileInformationGenerator.officeProperties != nil
        case LocalFileInformationGenerator.customPropertiesExtensions.contains:
            return LocalFileInformationGenerator.customProperties != nil

        default:
            return false
        }
    }
    
    @discardableResult
    public func thumbnailOfFile(path: String, dimension: CGSize? = nil, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) -> Progress? {
        let dimension = dimension ?? CGSize(width: 64, height: 64)
        (dispatch_queue).async {
            var thumbnailImage: ImageClass? = nil
            // Check cache
            let fileURL = self.url(of: path)
            // Create Thumbnail and cache
            switch fileURL.pathExtension.lowercased() {
            case LocalFileInformationGenerator.videoThumbnailExtensions.contains:
                thumbnailImage = LocalFileInformationGenerator.videoThumbnail(fileURL, dimension)
            case LocalFileInformationGenerator.audioThumbnailExtensions.contains:
                thumbnailImage = LocalFileInformationGenerator.audioThumbnail(fileURL, dimension)
            case LocalFileInformationGenerator.imageThumbnailExtensions.contains:
                thumbnailImage = LocalFileInformationGenerator.imageThumbnail(fileURL, dimension)
            case LocalFileInformationGenerator.pdfThumbnailExtensions.contains:
                thumbnailImage = LocalFileInformationGenerator.pdfThumbnail(fileURL, dimension)
            case LocalFileInformationGenerator.officeThumbnailExtensions.contains:
                thumbnailImage = LocalFileInformationGenerator.officeThumbnail(fileURL, dimension)
            case LocalFileInformationGenerator.customThumbnailExtensions.contains:
                thumbnailImage = LocalFileInformationGenerator.customThumbnail(fileURL, dimension)
            default:
                completionHandler(nil, nil)
                return
            }
            
            completionHandler(thumbnailImage, nil)
        }
        return nil
    }
    
    @discardableResult
    public func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String: Any], _ keys: [String], _ error: Error?) -> Void)) -> Progress? {
        (dispatch_queue).async {
            let fileExt = path.pathExtension.lowercased()
            var getter: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))?
            switch fileExt {
            case LocalFileInformationGenerator.imagePropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.imageProperties
             case LocalFileInformationGenerator.audioPropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.audioProperties
            case LocalFileInformationGenerator.videoPropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.videoProperties
            case LocalFileInformationGenerator.pdfPropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.pdfProperties
            case LocalFileInformationGenerator.archivePropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.archiveProperties
            case LocalFileInformationGenerator.officePropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.officeProperties
            case LocalFileInformationGenerator.customPropertiesExtensions.contains:
                getter = LocalFileInformationGenerator.customProperties
            default:
                break
            }
            
            var dic = [String: Any]()
            var keys = [String]()
            if let getterMethod = getter {
                (dic, keys) = getterMethod(self.url(of: path))
            }
            
            completionHandler(dic, keys, nil)
        }
        return nil
    }
}

/// Holds supported file types and thumbnail/properties generator for specefied type of file
public struct LocalFileInformationGenerator {
    /// Image extensions supportes for thumbnail.
    ///
    /// Default: `["jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff", "ico"]`
    static public var imageThumbnailExtensions: [String]  = ["heic", "jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff", "ico"]
    
    /// Audio and music extensions supportes for thumbnail.
    ///
    /// Default: `["mp1", "mp2", "mp3", "mpa", "mpga", "m1a", "m2a", "m4a", "m4b", "m4p", "m4r", "aac", "snd", "caf", "aa", "aax", "adts", "aif", "aifc", "aiff", "au", "flac", "amr", "wav", "wave", "bwf", "ac3", "eac3", "ec3", "cdda"]`
    static public var audioThumbnailExtensions: [String]  = ["mp1", "mp2", "mp3", "mpa", "mpga", "m1a", "m2a", "m4a", "m4b", "m4p", "m4r", "aac", "snd", "caf", "aa", "aax", "adts", "aif", "aifc", "aiff", "au", "flac", "amr", "wav", "wave", "bwf", "ac3", "eac3", "ec3", "cdda"]
    
    /// Video extensions supportes for thumbnail.
    ///
    /// Default: `["mov", "mp4", "mpg4", "m4v", "mqv", "mpg", "mpeg", "avi", "vfw", "3g2", "3gp", "3gp2", "3gpp", "qt"]`
    static public var videoThumbnailExtensions: [String]  = ["mov", "mp4", "mpg4", "m4v", "mqv", "mpg", "mpeg", "avi", "vfw", "3g2", "3gp", "3gp2", "3gpp", "qt"]

    /// Portable document file extensions supportes for thumbnail.
    ///
    /// Default: `["pdf"]`
    static public var pdfThumbnailExtensions: [String]    = ["pdf"]
    
    /// Office document extensions supportes for thumbnail.
    ///
    /// Default: `empty`
    static public var officeThumbnailExtensions: [String] = []
    
    /// Custom document extensions supportes for thumbnail.
    ///
    /// Default: `empty`
    static public var customThumbnailExtensions: [String] = []

    
    /// Image extensions supportes for properties.
    ///
    /// Default: `["jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff"]`
    static public var imagePropertiesExtensions: [String]   = ["heic", "jpg", "jpeg", "bmp", "gif", "png", "tif", "tiff"]
    
    /// Audio and music extensions supportes for properties.
    ///
    /// Default: `["mp1", "mp2", "mp3", "mpa", "mpga", "m1a", "m2a", "m4a", "m4b", "m4p", "m4r", "aac", "snd", "caf", "aa", "aax", "adts", "aif", "aifc", "aiff", "au", "flac", "amr", "wav", "wave", "bwf", "ac3", "eac3", "ec3", "cdda"]`
    static public var audioPropertiesExtensions: [String]   = ["mp1", "mp2", "mp3", "mpa", "mpga", "m1a", "m2a", "m4a", "m4b", "m4p", "m4r", "aac", "snd", "caf", "aa", "aax", "adts", "aif", "aifc", "aiff", "au", "flac", "amr", "wav", "wave", "bwf", "ac3", "eac3", "ec3", "cdda"]
    
    /// Video extensions supportes for properties.
    ///
    /// Default: `["mov", "mp4", "mpg4", "m4v", "mqv", "mpg", "mpeg", "avi", "vfw", "3g2", "3gp", "3gp2", "3gpp", "qt"]`
    static public var videoPropertiesExtensions: [String]   = ["mov", "mp4", "mpg4", "m4v", "mqv", "mpg", "mpeg", "avi", "vfw", "3g2", "3gp", "3gp2", "3gpp", "qt"]
    
    /// Portable document file extensions supportes for properties.
    ///
    /// Default: `["pdf"]`
    static public var pdfPropertiesExtensions: [String]     = ["pdf"]
    
    /// Archive extensions (like zip) supportes for properties.
    ///
    /// Default: `empty`
    static public var archivePropertiesExtensions: [String] = []
    
    /// Office document extensions supportes for properties.
    ///
    /// Default: `empty`
    static public var officePropertiesExtensions: [String]  = []
    
    /// Custom document extensions supportes for properties.
    ///
    /// Default: `empty`
    static public var customPropertiesExtensions: [String]  = []
    
    /// Thumbnail generator closure for image files.
    static public var imageThumbnail: (_ fileURL: URL, _ dimension: CGSize?) -> ImageClass? = { fileURL, dimension in
        return LocalFileProvider.scaleDown(fileURL: fileURL, toSize: dimension)
    }
    
    /// Thumbnail generator closure for audio and music files.
    static public var audioThumbnail: (_ fileURL: URL, _ dimension: CGSize?) -> ImageClass? = { fileURL, dimension in
        let playerItem = AVPlayerItem(url: fileURL)
        let metadataList = playerItem.asset.commonMetadata
        let commonKeyArtwork = AVMetadataKey.commonKeyArtwork
        for item in metadataList {
            if item.commonKey == commonKeyArtwork {
                if let data = item.dataValue {
                    return LocalFileProvider.scaleDown(data: data, toSize: dimension)
                }
            }
        }
        return nil
    }
    
    /// Thumbnail generator closure for video files.
    static public var videoThumbnail: (_ fileURL: URL, _ dimension: CGSize?) -> ImageClass? = { fileURL, dimension in
        let asset = AVAsset(url: fileURL)
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.maximumSize = dimension ?? .zero
        assetImgGenerate.appliesPreferredTrackTransform = true
        let time = CMTime(value: asset.duration.value / 3, timescale: asset.duration.timescale)
        if let cgImage = try? assetImgGenerate.copyCGImage(at: time, actualTime: nil) {
            #if os(macOS)
            return ImageClass(cgImage: cgImage, size: .zero)
            #else
            return ImageClass(cgImage: cgImage)
            #endif
        }
        return nil
    }
    
    /// Thumbnail generator closure for portable document files files.
    static public var pdfThumbnail: (_ fileURL: URL, _ dimension: CGSize?) -> ImageClass? = { fileURL, dimension in
        return LocalFileProvider.convertToImage(pdfURL: fileURL, maxSize: dimension)
    }
    
    /// Thumbnail generator closure for office document files.
    /// - Note: No default implementation is avaiable
    static public var officeThumbnail: (_ fileURL: URL, _ dimension: CGSize?) -> ImageClass? = { fileURL, dimension in
        return nil
    }
    
    /// Thumbnail generator closure for custom type of files.
    /// - Note: No default implementation is avaiable
    static public var customThumbnail: (_ fileURL: URL, _ dimension: CGSize?) -> ImageClass? = { fileURL, dimension in
        return nil
    }
    
    /// Properties generator closure for image files.
    static public var imageProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
        var dic = [String: Any]()
        var keys = [String]()
        
        func add(key: String, value: Any?) {
            if let value = value, !((value as? String)?.isEmpty ?? false) {
                keys.append(key)
                dic[key] = value
            }
        }
        
        func simplify(_ top:Int64, _ bottom:Int64) -> (newTop:Int, newBottom:Int) {
            var x = top
            var y = bottom
            while (y != 0) {
                let buffer = y
                y = x % y
                x = buffer
            }
            let hcfVal = x
            let newTopVal = top/hcfVal
            let newBottomVal = bottom/hcfVal
            return(Int(newTopVal), Int(newBottomVal))
        }
        
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else {
            return (dic, keys)
        }
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? NSDictionary ?? [:]
        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? NSDictionary ?? [:]
        let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? NSDictionary ?? [:]
        
        if let pixelWidth = properties.object(forKey: kCGImagePropertyPixelWidth) as? NSNumber, let pixelHeight = properties.object(forKey: kCGImagePropertyPixelHeight) as? NSNumber {
            add(key: "Dimensions", value: "\(pixelWidth)x\(pixelHeight)")
        }
        add(key: "DPI", value: properties[kCGImagePropertyDPIWidth as String])
        add(key: "Device maker", value: tiffDict[kCGImagePropertyTIFFMake as String])
        add(key: "Device model", value: tiffDict[kCGImagePropertyTIFFModel as String])
        add(key: "Lens model", value: exifDict[kCGImagePropertyExifLensModel as String])
        add(key: "Artist", value: tiffDict[kCGImagePropertyTIFFArtist as String] as? String)
        add(key: "Copyright", value: tiffDict[kCGImagePropertyTIFFCopyright as String] as? String)
        add(key: "Date taken", value: tiffDict[kCGImagePropertyTIFFDateTime as String] as? String)
        
        if let latitude = gpsDict[kCGImagePropertyGPSLatitude as String] as? NSNumber,
            let longitude = gpsDict[kCGImagePropertyGPSLongitude as String] as? NSNumber {
            let altitudeDesc = (gpsDict[kCGImagePropertyGPSAltitude as String] as? NSNumber).map({ " at \($0.format(precision: 0))m" }) ?? ""
            add(key: "Location", value: "\(latitude.format()), \(longitude.format())\(altitudeDesc)")
        }
        add(key: "Area", value: gpsDict[kCGImagePropertyGPSAreaInformation as String])
        
        add(key: "Color space", value: properties[kCGImagePropertyColorModel as String])
        add(key: "Color depth", value: (properties[kCGImagePropertyDepth as String] as? NSNumber).map({ "\($0) bits" }))
        add(key: "Color profile", value: properties[kCGImagePropertyProfileName as String])
        add(key: "Focal length", value: exifDict[kCGImagePropertyExifFocalLength as String])
        add(key: "White banance", value: exifDict[kCGImagePropertyExifWhiteBalance as String])
        add(key: "F number", value: exifDict[kCGImagePropertyExifFNumber as String])
        add(key: "Exposure program", value: exifDict[kCGImagePropertyExifExposureProgram as String])
        
        if let exp = exifDict[kCGImagePropertyExifExposureTime as String] as? NSNumber {
            let expfrac = simplify(Int64(exp.doubleValue * 1_163_962_800_000), 1_163_962_800_000)
            add(key: "Exposure time", value: "\(expfrac.newTop)/\(expfrac.newBottom)")
        }
        add(key: "ISO speed", value: (exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first)
        return (dic, keys)
    }
    
    /// Properties generator closure for audio and music files.
    static var audioProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
        var dic = [String: Any]()
        var keys = [String]()
        
        func add(key: String, value: Any?) {
            if let value = value {
                keys.append(key)
                dic[key] = value
            }
        }
        
        func makeKeyDescription(_ key: String?) -> String? {
            guard let key = key else {
                return nil
            }
            guard let regex = try? NSRegularExpression(pattern: "([a-z])([A-Z])" , options: []) else {
                return nil
            }
            let newKey = regex.stringByReplacingMatches(in: key, options: [], range: NSRange(location: 0, length: (key as NSString).length) , withTemplate: "$1 $2")
            return newKey.capitalized
        }
        
        func parseLocationData(_ value: String) -> (latitude: Double, longitude: Double, height: Double?)? {
            let scanner = Scanner.init(string: value)
            var latitude: Double = 0.0, longitude: Double = 0.0, height: Double = 0
            
            if scanner.scanDouble(&latitude), scanner.scanDouble(&longitude) {
                scanner.scanDouble(&height)
                return (latitude, longitude, height)
            } else {
                return nil
            }
        }
        
        guard fileURL.fileExists else {
            return (dic, keys)
        }
        let playerItem = AVPlayerItem(url: fileURL)
        let metadataList = playerItem.asset.commonMetadata
        for item in metadataList {
            let commonKey = item.commonKey?.rawValue
            if let key = makeKeyDescription(commonKey) {
                if commonKey == "location", let value = item.stringValue, let loc = parseLocationData(value) {
                    keys.append(key)
                    let heightStr: String = (loc.height as NSNumber?).map({ ", \($0.format(precision: 0))m" }) ?? ""
                    dic[key] = "\((loc.latitude as NSNumber).format())°, \((loc.longitude as NSNumber).format())°\(heightStr)"
                } else if let value = item.dateValue {
                    keys.append(key)
                    dic[key] = value
                } else if let value = item.numberValue {
                    keys.append(key)
                    dic[key] = value
                } else if let value = item.stringValue {
                    keys.append(key)
                    dic[key] = value
                }
            }
        }
        if let ap = try? AVAudioPlayer(contentsOf: fileURL) {
            add(key: "Duration", value: ap.duration.formatshort)
            add(key: "Bitrate", value: ap.settings[AVSampleRateKey] as? Int)
        }
        return (dic, keys)
    }
    
    /// Properties generator closure for video files.
    static public var videoProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
        var dic = [String: Any]()
        var keys = [String]()
        
        func add(key: String, value: Any?) {
            if let value = value {
                keys.append(key)
                dic[key] = value
            }
        }
        
        if let audioprops = LocalFileInformationGenerator.audioProperties?(fileURL) {
            dic = audioprops.prop
            keys = audioprops.keys
            dic.removeValue(forKey: "Duration")
            if let index = keys.firstIndex(of: "Duration") {
                keys.remove(at: index)
            }
        }
        let asset = AVURLAsset(url: fileURL, options: nil)
        let videoTracks = asset.tracks(withMediaType: AVMediaType.video)
        if let videoTrack = videoTracks.first {
            var bitrate: Float = 0
            let width = Int(videoTrack.naturalSize.width)
            let height = Int(videoTrack.naturalSize.height)
            add(key: "Dimensions", value: "\(width)x\(height)")
            var duration: Int64 = 0
            for track in videoTracks {
                duration += track.timeRange.duration.timescale > 0 ? track.timeRange.duration.value / Int64(track.timeRange.duration.timescale) : 0
                bitrate += track.estimatedDataRate
            }
            add(key: "Duration", value: TimeInterval(duration).formatshort)
            add(key: "Video Bitrate", value: "\(Int(ceil(bitrate / 1000))) kbps")
        }
        let audioTracks = asset.tracks(withMediaType: AVMediaType.audio)
        // dic["Audio channels"] = audioTracks.count
        var bitrate: Float = 0
        for track in audioTracks {
            bitrate += track.estimatedDataRate
        }
        add(key: "Audio Bitrate", value: "\(Int(ceil(bitrate / 1000))) kbps")
        return (dic, keys)
    }
    
    /// Properties generator closure for protable documents files.
    static public var pdfProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
        var dic = [String: Any]()
        var keys = [String]()
        
        func add(key: String, value: Any?) {
            if let value = value, !((value as? String)?.isEmpty ?? false) {
                keys.append(key)
                dic[key] = value
            }
        }
        
        func getKey(_ key: String, from dict: CGPDFDictionaryRef) -> String? {
            var cfStrValue: CGPDFStringRef?
            if (CGPDFDictionaryGetString(dict, key, &cfStrValue)), let value = cfStrValue.flatMap({ CGPDFStringCopyTextString($0) }) {
                return value as String
            }
            var cfArrayValue: CGPDFArrayRef?
            if (CGPDFDictionaryGetArray(dict, key, &cfArrayValue)), let cfArray = cfArrayValue {
                var array = [String]()
                for i in 0..<CGPDFArrayGetCount(cfArray) {
                    var cfItemValue: CGPDFStringRef?
                    if CGPDFArrayGetString(cfArray, i, &cfItemValue), let item = cfItemValue.flatMap({ CGPDFStringCopyTextString($0) }) {
                        array.append(item as String)
                    }
                }
                return array.joined(separator: ", ")
            }
            return nil
        }
        
        func convertDate(_ date: String?) -> Date? {
            guard let date = date else { return nil }
            let dateStr = date.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "D:", with: "", options: .anchored)
            let dateFormatter = DateFormatter()
            let formats: [String] = ["yyyyMMddHHmmssTZ", "yyyyMMddHHmmssZZZZZ", "yyyyMMddHHmmssZ", "yyyyMMddHHmmss"]
            for format in formats {
                dateFormatter.dateFormat = format
                if let result = dateFormatter.date(from: dateStr) {
                    return result
                }
            }
            return nil
        }
        
        guard let provider = CGDataProvider(url: fileURL as CFURL), let reference = CGPDFDocument(provider), let dict = reference.info else {
            return (dic, keys)
        }
        add(key: "Title", value: getKey("Title", from: dict))
        add(key: "Author", value: getKey("Author", from: dict))
        add(key: "Subject", value: getKey("Subject", from: dict))
        add(key: "Producer", value: getKey("Producer", from: dict))
        add(key: "Keywords", value: getKey("Keywords", from: dict))
        var majorVersion: Int32 = 0
        var minorVersion: Int32 = 0
        reference.getVersion(majorVersion: &majorVersion, minorVersion: &minorVersion)
        if majorVersion > 0 {
            add(key: "Version", value:  String(majorVersion) + "." + String(minorVersion))
        }
        add(key: "Pages", value: reference.numberOfPages)
        
        if reference.numberOfPages > 0, let pageRef = reference.page(at: 1) {
            let size = pageRef.getBoxRect(CGPDFBox.mediaBox).size
            add(key: "Resolution", value: "\(Int(size.width))x\(Int(size.height))")
        }
        add(key: "Content creator", value: getKey("Creator", from: dict))
        add(key: "Creation date", value: convertDate(getKey("CreationDate", from: dict)))
        add(key: "Modified date", value: convertDate(getKey("ModDate", from: dict)))
        add(key: "Security", value: reference.isEncrypted ? (reference.isUnlocked ? "Present" : "Password Protected") : "None")
        add(key: "Allows printing", value: reference.allowsPrinting)
        add(key: "Allows copying", value: reference.allowsCopying)
        return (dic, keys)
    }
    
    /// Properties generator closure for video files.
    /// - Note: No default implementation is avaiable
    static public var archiveProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = nil
    
    /// Properties generator closure for office doument files.
    /// - Note: No default implementation is avaiable
    static public var officeProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = nil
    
    /// Properties generator closure for custom type of files.
    /// - Note: No default implementation is avaiable
    static public var customProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = nil
}
#endif
