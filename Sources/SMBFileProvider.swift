//
//  SambaFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

class SMBFileProvider: FileProvider, FileProviderMonitor {

    open static var type: String = "Samba"
    open var isPathRelative: Bool = true
    open var baseURL: URL?
    open var currentPath: String = ""
    open var dispatch_queue: DispatchQueue
    open var operation_queue: OperationQueue
    open weak var delegate: FileProviderDelegate?
    open let credential: URLCredential?
    
    public typealias FileObjectClass = FileObject
    
    public init? (baseURL: URL, credential: URLCredential, afterInitialized: SimpleCompletionHandler) {
        guard baseURL.uw_scheme.lowercased() == "smb" else {
            return nil
        }
        self.baseURL = baseURL.appendingPathComponent("")
        dispatch_queue = DispatchQueue(label: "FileProvider.\(type(of: self).type)", attributes: DispatchQueue.Attributes.concurrent)
        operation_queue = OperationQueue()
        operation_queue.name = "FileProvider.\(type(of: self).type).Operation"
        
        self.credential = credential
    }
        
    open func contentsOfDirectory(path: String, completionHandler: @escaping ((_ contents: [FileObjectClass], _ error: Error?) -> Void)) {
        NotImplemented()
    }
    
    open func attributesOfItem(path: String, completionHandler: @escaping ((_ attributes: FileObjectClass?, _ error: Error?) -> Void)) {
        NotImplemented()
    }
    
    open func storageProperties(completionHandler: @escaping ((_ total: Int64, _ used: Int64) -> Void)) {
        NotImplemented()
    }
    
    open weak var fileOperationDelegate: FileOperationDelegate?
    
    open func create(folder folderName: String, at atPath: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func create(file fileName: String, at atPath: String, contents data: Data?, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func moveItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func copyItem(path: String, to toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func removeItem(path: String, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func copyItem(localFile: URL, to toPath: String, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func copyItem(path: String, toLocalURL: URL, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func contents(path: String, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func contents(path: String, offset: Int64, length: Int, completionHandler: @escaping ((_ contents: Data?, _ error: Error?) -> Void)) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func writeContents(path: String, contents data: Data, atomically: Bool, overwrite: Bool, completionHandler: SimpleCompletionHandler) -> OperationHandle? {
        NotImplemented()
        return nil
    }
    
    open func searchFiles(path: String, recursive: Bool, query: String, foundItemHandler:((FileObjectClass) -> Void)?, completionHandler: @escaping ((_ files: [FileObjectClass], _ error: Error?) -> Void)) {
        NotImplemented()
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
        let copy = SMBFileProvider(baseURL: self.baseURL!, credential: self.credential!, afterInitialized: { _ in })!
        copy.currentPath = self.currentPath
        copy.delegate = self.delegate
        copy.fileOperationDelegate = self.fileOperationDelegate
        return copy
    }
}

// MARK: basic CIFS interactivity
public enum SMBFileProviderError: Int, Error, CustomStringConvertible {
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


