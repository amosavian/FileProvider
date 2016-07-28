//
//  SambaFileProvider.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2016 Mousavian. Distributed under MIT license.
//

import Foundation

public class SMBFileProvider: FileProvider, FileProviderMonitor {
    public var type: String = "Samba"
    public var isPathRelative: Bool = true
    public var baseURL: NSURL?
    public var currentPath: String = ""
    public var dispatch_queue: dispatch_queue_t
    public weak var delegate: FileProviderDelegate?
    public let credential: NSURLCredential?
    
    public typealias FileObjectClass = FileObject
    
    public init? (baseURL: NSURL, credential: NSURLCredential, afterInitialized: SimpleCompletionHandler) {
        guard baseURL.uw_scheme.lowercaseString == "smb" else {
            return nil
        }
        self.baseURL = baseURL
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        //let url = baseURL.uw_absoluteString
        self.credential = credential
    }
        
    public func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObjectClass], error: ErrorType?) -> Void)) {
        NotImplemented()
        dispatch_async(dispatch_queue) { 
            
        }
    }
    
    public func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObjectClass?, error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    public weak var fileOperationDelegate: FileOperationDelegate?
    
    public func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func createFile(fileAttribs: FileObject, atPath: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    public func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    public func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    public func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObjectClass) -> Void)?, completionHandler: ((files: [FileObjectClass], error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    public func registerNotifcation(path: String, eventHandler: (() -> Void)) {
        NotImplemented()
    }
    
    public func unregisterNotifcation(path: String) {
        NotImplemented()
    }
    
    public func isRegisteredForNotification(path: String) -> Bool {
        return false
    }
}

// MARK: basic CIFS interactivity
public enum SMBFileProviderError: Int, ErrorType, CustomStringConvertible {
    case BadHeader
    case IncompatibleHeader
    case IncorrectParamsLength
    case IncorrectMessageLength
    case InvalidCommand
    
    public var description: String {
        return "SMB message structure is invalid"
    }
}

private extension SMBFileProvider {
    private func getPID() -> UInt32 {
        return UInt32(NSProcessInfo.processInfo().processIdentifier)
    }
}


