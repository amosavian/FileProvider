//
//  SambaFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

class SMBFileProvider: FileProvider, FileProviderMonitor {
    open class var type: String { return "SMB" }
    open var baseURL: URL?
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue
    open weak var delegate: FileProviderDelegate?
    open var credential: URLCredential?
    
    public typealias FileObjectClass = FileObject
    
    public init? (baseURL: URL, credential: URLCredential?) {
        guard baseURL.uw_scheme.lowercased() == "smb" else {
            return nil
        }
        self.baseURL = baseURL.appendingPathComponent("")
        
        let queueLabel = "FileProvider.\(Swift.type(of: self).type)"
        dispatch_queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "\(queueLabel).Operation"
        
        self.credential = credential
    }
    
    public required convenience init?(coder aDecoder: NSCoder) {
        guard let baseURL = aDecoder.decodeObject(of: NSURL.self, forKey: "baseURL") as URL? else {
            if #available(macOS 10.11, iOS 9.0, tvOS 9.0, *) {
                aDecoder.failWithError(CocoaError(.coderValueNotFound,
                                                  userInfo: [NSLocalizedDescriptionKey: "Base URL is not set."]))
            }
            return nil
        }
        self.init(baseURL: baseURL,
                  credential: aDecoder.decodeObject(of: URLCredential.self, forKey: "credential"))
    }
    
    open func encode(with aCoder: NSCoder) {
        aCoder.encode(self.baseURL, forKey: "baseURL")
        aCoder.encode(self.credential, forKey: "credential")
    }
    
    public static var supportsSecureCoding: Bool {
        return true
    }
    
    open func contentsOfDirectory(path: String, completionHandler: @escaping (_ contents: [FileObjectClass], _ error: Error?) -> Void) {
        NotImplemented()
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping (_ attributes: FileObjectClass?, _ error: Error?) -> Void) {
        NotImplemented()
    }
    
    open func storageProperties(completionHandler: @escaping (_ volume: VolumeObject?) -> Void) {
        NotImplemented()
    }
    
    func isReachable(completionHandler: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        NotImplemented()
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
    
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func writeContents(path: String, contents data: Data?, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func searchFiles(path: String, recursive: Bool, query: NSPredicate, foundItemHandler:((FileObjectClass) -> Void)?, completionHandler: @escaping ((_ files: [FileObjectClass], _ error: Error?) -> Void)) -> Progress? {
        NotImplemented()
        return nil
    }
    
    open func registerNotifcation(path: String, eventHandler: @escaping (() -> Void)) {
        NotImplemented()
    }
    
    open func unregisterNotifcation(path: String) {
        NotImplemented()
    }
    
    open func isRegisteredForNotification(path: String) -> Bool {
        return false
    }
    
    open func copy(with zone: NSZone? = nil) -> Any {
        let copy = SMBFileProvider(baseURL: self.baseURL!, credential: self.credential!)!
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        return copy
    }
}

// MARK: basic CIFS interactivity
enum SMBFileProviderError: Int, Error, CustomStringConvertible {
    case badHeader
    case incompatibleHeader
    case incorrectParamsLength
    case incorrectMessageLength
    case invalidCommand
    
    public var description: String {
        return "SMB message structure is invalid"
    }
}

private extension SMBFileProvider {
    func getPID() -> UInt32 {
        return UInt32(ProcessInfo.processInfo.processIdentifier)
    }
}


