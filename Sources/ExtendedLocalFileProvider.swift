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
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif

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
                let scaledImage = dimension != nil ? LocalFileProvider.scaleDown(image: image, toSize: dimension!) : image
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

public struct LocalFileInformationGenerator {
    static public var imageThumbnailExtensions: [String] = ["jpg", "jpeg", "gif", "bmp", "png", "tif", "tiff", "ico"]
    static public var audioThumbnailExtensions: [String] = ["mp3", "aac", "m4a"]
    static public var videoThumbnailExtensions: [String] = ["mov", "mp4", "m4v", "mpg", "mpeg"]
    static public var pdfThumbnailExtensions: [String] = ["pdf"]
    static public var officeThumbnailExtensions: [String] = []
    static public var customThumbnailExtensions: [String] = []
    
    static public var imagePropertiesExtensions: [String] = ["jpg", "jpeg", "bmp", "gif", "png", "tif", "tiff"]
    static public var audioPropertiesExtensions: [String] = ["mp3", "aac", "m4a", "caf"]
    static public var videoPropertiesExtensions: [String] = ["mp4", "mpg", "3gp", "mov", "avi"]
    static public var pdfPropertiesExtensions: [String] = ["pdf"]
    static public var archivePropertiesExtensions: [String] = []
    static public var officePropertiesExtensions: [String] = []
    static public var customPropertiesExtensions: [String] = []
    
    static public var imageThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        return ImageClass(contentsOfFile: fileURL.path)
    }
    
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
    
    static public var videoThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        let asset = AVAsset(url: fileURL)
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        let time = CMTimeMake(asset.duration.value / 3, asset.duration.timescale)
        if let cgImage = try? assetImgGenerate.copyCGImage(at: time, actualTime: nil) {
            #if os(macOS)
            return ImageClass(cgImage: cgImage, size: NSSize.zero)
            #else
            return ImageClass(cgImage: cgImage)
            #endif
        }
        return nil
    }
    
    static public var pdfThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return LocalFileProvider.convertToImage(pdfData: data)
    }
    
    static public var officeThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        return nil
    }
    
    static public var customThumbnail: (_ fileURL: URL) -> ImageClass? = { fileURL in
        return nil
    }
    
    static public var imageProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
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
        
        var dic = [String: Any]()
        var keys = [String]()
        guard let cgDataRef = CGImageSourceCreateWithURL(fileURL as CFURL, nil), let cfImageDict = CGImageSourceCopyPropertiesAtIndex(cgDataRef, 0, nil) else {
            return (dic, keys)
        }
        let imageDict = cfImageDict as NSDictionary
        let tiffDict = imageDict[kCGImagePropertyTIFFDictionary as String] as? [String : AnyObject] ?? [:]
        let exifDict = imageDict[kCGImagePropertyExifDictionary as String] as? [String : AnyObject] ?? [:]
        if let pixelWidth: AnyObject = imageDict.object(forKey: kCGImagePropertyPixelWidth) as? NSNumber, let pixelHeight: AnyObject = imageDict.object(forKey: kCGImagePropertyPixelHeight) as? NSNumber {
            keys.append("Dimensions")
            dic["Dimensions"] = "\(pixelWidth)x\(pixelHeight)"
        }
        if let dpi = imageDict[kCGImagePropertyDPIWidth as String] {
            keys.append("DPI")
            dic["DPI"] = dpi
        }
        if let devicemake = tiffDict[kCGImagePropertyTIFFMake as String] {
            keys.append("Device make")
            dic["Device make"] = devicemake
        }
        if let devicemodel = tiffDict[kCGImagePropertyTIFFModel as String] {
            keys.append("Device model")
            dic["Device model"] = devicemodel
        }
        if let lensmodel = exifDict[kCGImagePropertyExifLensModel as String] {
            keys.append("Lens model")
            dic["Lens model"] = lensmodel
        }
        if let artist = tiffDict[kCGImagePropertyTIFFArtist as String] as? String , !artist.isEmpty {
            keys.append("Artist")
            dic["Artist"] = artist
        }
        if let cr = tiffDict[kCGImagePropertyTIFFCopyright as String] as? String , !cr.isEmpty {
            keys.append("Copyright")
            dic["Copyright"] = cr
        }
        if let date = tiffDict[kCGImagePropertyTIFFDateTime as String] as? String , !date.isEmpty {
            keys.append("Date taken")
            dic["Date taken"] = date
        }
        if let latitude = tiffDict[kCGImagePropertyGPSLatitude as String]?.doubleValue, let longitude = tiffDict[kCGImagePropertyGPSLongitude as String]?.doubleValue {
            keys.append("Location")
            dic["Location"] = "\(latitude), \(longitude)"
        }
        if let colorspace = imageDict[kCGImagePropertyColorModel as String] {
            keys.append("Color space")
            dic["Color space"] = colorspace
        }
        if let focallen = exifDict[kCGImagePropertyExifFocalLength as String] {
            keys.append("Focal length")
            dic["Focal length"] = focallen
        }
        if let fnum = exifDict[kCGImagePropertyExifFNumber as String] {
            keys.append("F number")
            dic["F number"] = fnum
        }
        if let expprog = exifDict[kCGImagePropertyExifExposureProgram as String] {
            keys.append("Exposure program")
            dic["Exposure program"] = expprog
        }
        if let exp = exifDict[kCGImagePropertyExifExposureTime as String]?.doubleValue {
            let expfrac = simplify(Int64(exp * 10_000_000_000_000), 10_000_000_000_000)
            keys.append("Exposure time")
            dic["Exposure time"] = "\(expfrac.newTop)/\(expfrac.newBottom)"
        }
        if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? NSArray , iso.count > 0 {
            keys.append("ISO speed")
            dic["ISO speed"] = iso[0]
        }
        return (dic, keys)
    }
    
    static var audioProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
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
        
        var dic = [String: Any]()
        var keys = [String]()
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
                keys.append("Duration")
                dic["Duration"] = LocalFileProvider.formatshort(interval: ap.duration)
                if let bitRate = ap.settings[AVSampleRateKey] as? Int {
                    keys.append("Bitrate")
                    dic["Bitrate"] = bitRate
                }
            }
        }
        return (dic, keys)
    }
    
    static public var videoProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
        var dic = [String: Any]()
        var keys = [String]()
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
            keys.append("Dimensions")
            dic["Dimensions"] = "\(width)x\(height)"
            var duration: Int64 = 0
            for track in videoTracks {
                duration += track.timeRange.duration.timescale > 0 ? track.timeRange.duration.value / Int64(track.timeRange.duration.timescale) : 0
                bitrate += track.estimatedDataRate
            }
            keys.append("Duration")
            dic["Duration"] = LocalFileProvider.formatshort(interval: TimeInterval(duration))
            keys.append("Video Bitrate")
            dic["Video Bitrate"] = "\(Int(ceil(bitrate / 1000))) kbps"
        }
        let audioTracks = asset.tracks(withMediaType: AVMediaTypeAudio)
        // dic["Audio channels"] = audioTracks.count
        var bitrate: Float = 0
        for track in audioTracks {
            bitrate += track.estimatedDataRate
        }
        keys.append("Audio Bitrate")
        dic["Audio Bitrate"] = "\(Int(ceil(bitrate / 1000))) kbps"
        return (dic, keys)
    }
    
    static public var pdfProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = { fileURL in
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
        
        var dic = [String: Any]()
        var keys = [String]()
        if let data = try? Data(contentsOf: fileURL), let provider = CGDataProvider(data: data as CFData), let reference = CGPDFDocument(provider), let dict = reference.info {
            if let title = getKey("Title", from: dict), !title.isEmpty {
                keys.append("Title")
                dic["Title"] = title
            }
            if let author = getKey("Author", from: dict), !author.isEmpty {
                keys.append("Author")
                dic["Author"] = author
            }
            if let subject = getKey("Subject", from: dict), !subject.isEmpty {
                keys.append("Subject")
                dic["Subject"] = subject
            }
            var majorVersion: Int32 = 0
            var minorVersion: Int32 = 0
            reference.getVersion(majorVersion: &majorVersion, minorVersion: &minorVersion)
            if majorVersion > 0 {
                keys.append("Version")
                dic["Version"] = String(majorVersion) + "." + String(minorVersion)
            }
            if reference.numberOfPages > 0 {
                keys.append("Pages")
                dic["Pages"] = reference.numberOfPages
            }
            
            if reference.numberOfPages > 0, let pageRef = reference.page(at: 1) {
                let size = pageRef.getBoxRect(CGPDFBox.mediaBox).size
                keys.append("Resolution")
                dic["Resolution"] = "\(Int(size.width))x\(Int(size.height))"
            }
            if let creator = getKey("Creator", from: dict), !creator.isEmpty {
                keys.append("Content creator")
                dic["Content creator"] = creator
            }
            if let creationDateString = getKey("CreationDate", from: dict), let creationDate = convertDate(creationDateString) {
                keys.append("Creation date")
                dic["Creation date"] = creationDate
            }
            if let modifiedDateString = getKey("ModDate", from: dict), let modDate = convertDate(modifiedDateString) {
                keys.append("Modified date")
                dic["Modified date"] = modDate
            }
            keys.append("Security")
            dic["Security"] = reference.isEncrypted ? "Present" : "None"
            keys.append("Allows printing")
            dic["Allows printing"] = reference.allowsPrinting ? "Yes" : "No"
            keys.append("Allows copying")
            dic["Allows copying"] = reference.allowsCopying ? "Yes" : "No"
        }
        return (dic, keys)
    }
    
    static public var archiveProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = nil
    
    static public var officeProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = nil
    
    static public var customProperties: ((_ fileURL: URL) -> (prop: [String: Any], keys: [String]))? = nil
}

func ~=<T : Equatable>(array: [T], value: T) -> Bool {
    return array.contains(value)
}
