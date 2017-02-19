//
//  ExtendedLocalFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2017 Mousavian. Distributed under MIT license.
//

import Foundation
import ImageIO
import CoreGraphics
import AVFoundation

extension LocalFileProvider: ExtendedFileProvider {
    public func thumbnailOfFileSupported(path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case LocalFileInformationGenerator.imageThumbnailExtensions:
            return true
        case LocalFileInformationGenerator.audioThumbnailExtensions:
            return true
        case LocalFileInformationGenerator.videoThumbnailExtensions:
            return true
        case LocalFileInformationGenerator.pdfThumbnailExtensions:
            return true
        case LocalFileInformationGenerator.officeThumbnailExtensions:
            return true
        case LocalFileInformationGenerator.customThumbnailExtensions:
            return true
        default:
            return false
        }
    }
    
    public func propertiesOfFileSupported(path: String) -> Bool {
        let fileExt = (path as NSString).pathExtension.lowercased()
        switch fileExt {
        case LocalFileInformationGenerator.imagePropertiesExtensions:
            return LocalFileInformationGenerator.imageProperties != nil
        case LocalFileInformationGenerator.audioPropertiesExtensions:
            return LocalFileInformationGenerator.audioProperties != nil
        case LocalFileInformationGenerator.videoPropertiesExtensions:
            return LocalFileInformationGenerator.videoProperties != nil
        case LocalFileInformationGenerator.pdfPropertiesExtensions:
            return LocalFileInformationGenerator.pdfProperties != nil
        case LocalFileInformationGenerator.archivePropertiesExtensions:
            return LocalFileInformationGenerator.archiveProperties != nil
        case LocalFileInformationGenerator.officePropertiesExtensions:
            return LocalFileInformationGenerator.officeProperties != nil
        case LocalFileInformationGenerator.customPropertiesExtensions:
            return LocalFileInformationGenerator.customProperties != nil

        default:
            return false
        }
    }
    
    public func thumbnailOfFile(path: String, dimension: CGSize? = nil, completionHandler: @escaping ((_ image: ImageClass?, _ error: Error?) -> Void)) {
        let dimension = dimension ?? CGSize(width: 64, height: 64)
        (dispatch_queue).async {
            var thumbnailImage: ImageClass? = nil
            // Check cache
            let fileURL = self.url(of: path)
            // Create Thumbnail and cache
            switch fileURL.pathExtension.lowercased() {
            case LocalFileInformationGenerator.videoThumbnailExtensions:
                thumbnailImage = LocalFileInformationGenerator.videoThumbnail(fileURL)
            case LocalFileInformationGenerator.audioThumbnailExtensions:
                thumbnailImage = LocalFileInformationGenerator.audioThumbnail(fileURL)
            case LocalFileInformationGenerator.imageThumbnailExtensions:
                thumbnailImage = LocalFileInformationGenerator.imageThumbnail(fileURL)
            case LocalFileInformationGenerator.pdfThumbnailExtensions:
                thumbnailImage = LocalFileInformationGenerator.pdfThumbnail(fileURL)
            case LocalFileInformationGenerator.officeThumbnailExtensions:
                thumbnailImage = LocalFileInformationGenerator.officeThumbnail(fileURL)
            case LocalFileInformationGenerator.customThumbnailExtensions:
                thumbnailImage = LocalFileInformationGenerator.customThumbnail(fileURL)
            default:
                completionHandler(nil, nil)
                return
            }
            
            if let image = thumbnailImage {
                let scaledImage = LocalFileProvider.scaleDown(image: image, toSize: dimension)
                completionHandler(scaledImage, nil)
            }
        }
    }
    
    public func propertiesOfFile(path: String, completionHandler: @escaping ((_ propertiesDictionary: [String: Any], _ keys: [String], _ error: Error?) -> Void)) {
        (dispatch_queue).async {
            let fileExt = (path as NSString).pathExtension.lowercased()
            var getter: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))?
            switch fileExt {
            case LocalFileInformationGenerator.imagePropertiesExtensions:
                getter = LocalFileInformationGenerator.imageProperties
             case LocalFileInformationGenerator.audioPropertiesExtensions:
                getter = LocalFileInformationGenerator.audioProperties
            case LocalFileInformationGenerator.videoPropertiesExtensions:
                getter = LocalFileInformationGenerator.videoProperties
            case LocalFileInformationGenerator.pdfPropertiesExtensions:
                getter = LocalFileInformationGenerator.pdfProperties
            case LocalFileInformationGenerator.archivePropertiesExtensions:
                getter = LocalFileInformationGenerator.archiveProperties
            case LocalFileInformationGenerator.officePropertiesExtensions:
                getter = LocalFileInformationGenerator.officeProperties
            case LocalFileInformationGenerator.customPropertiesExtensions:
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
    }
}

/// Holds supported file types and thumbnail/properties generator for specefied type of file
public struct LocalFileInformationGenerator {
    /// Image extensions supportes for thumbnail.
    ///
    /// Default: `["jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff", "ico"]`
    static public var imageThumbnailExtensions: [String]  = ["jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff", "ico"]
    
    /// Audio and music extensions supportes for thumbnail.
    ///
    /// Default: `["mp3", "aac", "m4a"]`
    static public var audioThumbnailExtensions: [String]  = ["mp3", "aac", "m4a"]
    
    /// Video extensions supportes for thumbnail.
    ///
    /// Default: `["mov", "mp4", "m4v", "mpg", "mpeg"]`
    static public var videoThumbnailExtensions: [String]  = ["mov", "mp4", "m4v", "mpg", "mpeg"]
    
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
    static public var imagePropertiesExtensions: [String]   = ["jpg", "jpeg", "bmp", "gif", "png", "tif", "tiff"]
    
    /// Audio and music extensions supportes for properties.
    ///
    /// Default: `["mp3", "aac", "m4a", "caf"]`
    static public var audioPropertiesExtensions: [String]   = ["mp3", "aac", "m4a", "caf"]
    
    /// Video extensions supportes for properties.
    ///
    /// Default: `["mp4", "mpg", "3gp", "mov", "avi"]`
    static public var videoPropertiesExtensions: [String]   = ["mp4", "mpg", "3gp", "mov", "avi"]
    
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
    static public var imageThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        return ImageClass(contentsOfFile: fileURL.path)
    }
    
    /// Thumbnail generator closure for audio and music files.
    static public var audioThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        let playerItem = AVPlayerItem(url: fileURL)
        let metadataList = playerItem.asset.commonMetadata
        for item in metadataList {
            if item.commonKey == AVMetadataCommonKeyArtwork {
                if let data = item.dataValue {
                    return ImageClass(data: data)
                }
            }
        }
        return nil
    }
    
    /// Thumbnail generator closure for video files.
    static public var videoThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        let asset = AVAsset(url: fileURL)
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        let time = CMTimeMake(asset.duration.value / 3, asset.duration.timescale)
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
    static public var pdfThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return LocalFileProvider.convertToImage(pdfData: data)
    }
    
    /// Thumbnail generator closure for office document files.
    /// - Note: No default implementation is avaiable
    static public var officeThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        return nil
    }
    
    /// Thumbnail generator closure for custom type of files.
    /// - Note: No default implementation is avaiable
    static public var customThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        return nil
    }
    
    /// Properties generator closure for image files.
    static public var imageProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
        var dic = [String: Any]()
        var keys = [String]()
        
        func add(key: String, value: Any?) {
            if let value = value {
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
        
        guard let cgDataRef = CGImageSourceCreateWithURL(fileURL as CFURL, nil), let cfImageDict = CGImageSourceCopyPropertiesAtIndex(cgDataRef, 0, nil) else {
            return (dic, keys)
        }
        let imageDict = cfImageDict as NSDictionary
        let tiffDict = imageDict[kCGImagePropertyTIFFDictionary as String] as? NSDictionary ?? [:]
        let exifDict = imageDict[kCGImagePropertyExifDictionary as String] as? NSDictionary ?? [:]
        if let pixelWidth = imageDict.object(forKey: kCGImagePropertyPixelWidth) as? NSNumber, let pixelHeight = imageDict.object(forKey: kCGImagePropertyPixelHeight) as? NSNumber {
            add(key: "Dimensions", value: "\(pixelWidth)x\(pixelHeight)")
        }
        
        add(key: "DPI", value: imageDict[kCGImagePropertyDPIWidth as String])
        add(key: "Device make", value: tiffDict[kCGImagePropertyTIFFMake as String])
        add(key: "Device model", value: tiffDict[kCGImagePropertyTIFFModel as String])
        add(key: "Lens model", value: exifDict[kCGImagePropertyExifLensModel as String])
        add(key: "Artist", value: tiffDict[kCGImagePropertyTIFFArtist as String] as? String)
        if let cr = tiffDict[kCGImagePropertyTIFFCopyright as String] as? String , !cr.isEmpty {
            add(key: "Copyright", value: cr)

        }
        if let date = tiffDict[kCGImagePropertyTIFFDateTime as String] as? String , !date.isEmpty {
            add(key: "Date taken", value: date)
        }
        if let latitude = tiffDict[kCGImagePropertyGPSLatitude as String] as? NSNumber, let longitude = tiffDict[kCGImagePropertyGPSLongitude as String] as? NSNumber {
            add(key: "Location", value: "\(latitude), \(longitude)")
        }
        add(key: "Color space", value: imageDict[kCGImagePropertyColorModel as String])
        add(key: "Focal length", value: exifDict[kCGImagePropertyExifFocalLength as String])
        add(key: "F number", value: exifDict[kCGImagePropertyExifFNumber as String])
        add(key: "Exposure program", value: exifDict[kCGImagePropertyExifExposureProgram as String])
        
        if let exp = exifDict[kCGImagePropertyExifExposureTime as String] as? NSNumber {
            let expfrac = simplify(Int64(exp.doubleValue * 10_000_000_000_000), 10_000_000_000_000)
            add(key: "Exposure time", value: "\(expfrac.newTop)/\(expfrac.newBottom)")
        }
        if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? NSArray , iso.count > 0 {
            add(key: "ISO speed", value: iso[0])
        }
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
        
        func makeDescription(_ key: String?) -> String? {
            guard let key = key else {
                return nil
            }
            guard let regex = try? NSRegularExpression(pattern: "([a-z])([A-Z])" , options: NSRegularExpression.Options()) else {
                return nil
            }
            let newKey = regex.stringByReplacingMatches(in: key, options: NSRegularExpression.MatchingOptions(), range: NSMakeRange(0, (key as NSString).length) , withTemplate: "$1 $2")
            return newKey.capitalized
        }
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let playerItem = AVPlayerItem(url: fileURL)
            let metadataList = playerItem.asset.commonMetadata
            for item in metadataList {
                if let description = makeDescription(item.commonKey) {
                    if let value = item.stringValue {
                        keys.append(description)
                        dic[description] = value
                    }
                }
            }
            if let ap = try? AVAudioPlayer(contentsOf: fileURL) {
                add(key: "Duration", value: LocalFileProvider.formatshort(interval: ap.duration))
                add(key: "Bitrate", value: ap.settings[AVSampleRateKey] as? Int)
            }
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
            if let index = keys.index(of: "Duration") {
                keys.remove(at: index)
            }
        }
        let asset = AVURLAsset(url: fileURL, options: nil)
        let videoTracks = asset.tracks(withMediaType: AVMediaTypeVideo)
        if videoTracks.count > 0 {
            var bitrate: Float = 0
            let width = Int(videoTracks[0].naturalSize.width)
            let height = Int(videoTracks[0].naturalSize.height)
            add(key: "Dimensions", value: "\(width)x\(height)")
            var duration: Int64 = 0
            for track in videoTracks {
                duration += track.timeRange.duration.timescale > 0 ? track.timeRange.duration.value / Int64(track.timeRange.duration.timescale) : 0
                bitrate += track.estimatedDataRate
            }
            add(key: "Duration", value: LocalFileProvider.formatshort(interval: TimeInterval(duration)))
            add(key: "Video Bitrate", value: "\(Int(ceil(bitrate / 1000))) kbps")
        }
        let audioTracks = asset.tracks(withMediaType: AVMediaTypeAudio)
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
            if let value = value {
                keys.append(key)
                dic[key] = value
            }
        }
        
        func getKey(_ key: String, from dict: CGPDFDictionaryRef) -> String? {
            var cfValue: CGPDFStringRef? = nil
            if (CGPDFDictionaryGetString(dict, key, &cfValue)), let value = CGPDFStringCopyTextString(cfValue!) {
                return value as String
            }
            return nil
        }
        
        func convertDate(_ date: String) -> Date? {
            var dateStr = date
            if dateStr.hasPrefix("D:") {
                dateStr = date.substring(from: date.characters.index(date.startIndex, offsetBy: 2))
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMddHHmmssTZD"
            if let result = dateFormatter.date(from: dateStr) {
                return result
            }
            dateFormatter.dateFormat = "yyyyMMddHHmmss"
            if let result = dateFormatter.date(from: dateStr) {
                return result
            }
            return nil
        }
        
        if let data = try? Data(contentsOf: fileURL), let provider = CGDataProvider(data: data as CFData), let reference = CGPDFDocument(provider), let dict = reference.info {
            if let title = getKey("Title", from: dict), !title.isEmpty {
                add(key: "Title", value: title)
            }
            if let author = getKey("Author", from: dict), !author.isEmpty {
                add(key: "Author", value: author)
            }
            if let subject = getKey("Subject", from: dict), !subject.isEmpty {
                add(key: "Subject", value: subject)
            }
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
            if let creator = getKey("Creator", from: dict), !creator.isEmpty {
                add(key: "Content creator", value: creator)
            }
            if let creationDateString = getKey("CreationDate", from: dict) {
                add(key: "Creation date", value: convertDate(creationDateString))
            }
            if let modifiedDateString = getKey("ModDate", from: dict) {
                add(key: "Modified date", value: convertDate(modifiedDateString))
            }
            add(key: "Security", value: reference.isEncrypted ? "Present" : "None")
            add(key: "Allows printing", value: reference.allowsPrinting ? "Yes" : "No")
            add(key: "Allows copying", value: reference.allowsCopying ? "Yes" : "No")
        }
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

fileprivate func ~=<T : Equatable>(array: [T], value: T) -> Bool {
    return array.contains(value)
}
