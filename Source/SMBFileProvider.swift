//
//  SambaFileProvider.swift
//  ExtDownloader
//
//  Created by Amir Abbas Mousavian on 3/29/95.
//  Copyright © 1395 Mousavian. All rights reserved.
//

import Foundation

func encode<T>(inout value: T) -> NSData {
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}

func decode<T>(data: NSData) -> T {
    let pointer = UnsafeMutablePointer<T>.alloc(sizeof(T.Type))
    data.getBytes(pointer, length: sizeof(T.Type))
    
    return pointer.move()
}

class SMBFileProvider: FileProvider {
    var type: String = "Samba"
    var isPathRelative: Bool = true
    var baseURL: NSURL?
    var currentPath: String = ""
    var dispatch_queue: dispatch_queue_t
    var delegate: FileProviderDelegate?
    let credential: NSURLCredential?
    
    typealias FileObjectClass = FileObject
    
    init? (baseURL: NSURL, credential: NSURLCredential, afterInitialized: SimpleCompletionHandler) {
        guard baseURL.scheme.lowercaseString == "smb" else {
            return nil
        }
        self.baseURL = baseURL
        dispatch_queue = dispatch_queue_create("FileProvider.\(type)", DISPATCH_QUEUE_CONCURRENT)
        //let url = baseURL.absoluteString
        self.credential = credential
    }
        
    func contentsOfDirectoryAtPath(path: String, completionHandler: ((contents: [FileObjectClass], error: ErrorType?) -> Void)) {
        NotImplemented()
        dispatch_async(dispatch_queue) { 
            
        }
    }
    
    func attributesOfItemAtPath(path: String, completionHandler: ((attributes: FileObjectClass?, error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    func createFolder(folderName: String, atPath: String, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func createFile(fileAttribs: FileObject, atPath: String, contents data: NSData?, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func moveItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func copyItemAtPath(path: String, toPath: String, overwrite: Bool = false, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func removeItemAtPath(path: String, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func copyLocalFileToPath(localFile: NSURL, toPath: String, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func copyPathToLocalFile(path: String, toLocalURL: NSURL, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func contentsAtPath(path: String, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    func contentsAtPath(path: String, offset: Int64, length: Int, completionHandler: ((contents: NSData?, error: ErrorType?) -> Void)) {
        NotImplemented()
    }
    
    func writeContentsAtPath(path: String, contents data: NSData, atomically: Bool, completionHandler: SimpleCompletionHandler) {
        NotImplemented()
    }
    
    func searchFilesAtPath(path: String, recursive: Bool, query: String, foundItemHandler: ((FileObjectClass) -> Void)?, completionHandler: ((files: [FileObjectClass], error: ErrorType?) -> Void)) {
        NotImplemented()
    }
}

// MARK: basic CIFS interactivity
enum SMBFileProviderError: Int, ErrorType, CustomStringConvertible {
    case BadHeader
    case IncompatibleHeader
    case IncorrectParamsLength
    case IncorrectMessageLength
    case InvalidCommand
    
    var description: String {
        return "SMB message structure is invalid"
    }
}

extension SMBFileProvider {
    private func getPID() -> UInt32 {
        return UInt32(NSProcessInfo.processInfo().processIdentifier)
    }
    

}


