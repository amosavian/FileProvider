//
//  Sample-iOS.swift
//  FileProvider
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2018 Mousavian. Distributed under MIT license.
//

import UIKit
import FilesProvider

class ViewController: UIViewController, FileProviderDelegate {
    
    let server: URL = URL(string: "https://server-webdav.com")!
    let username = "username"
    let password = "password"
    
    var webdav: WebDAVFileProvider?
    
    @IBOutlet weak var uploadProgressView: UIProgressView
    @IBOutlet weak var downloadProgressView: UIProgressView
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        let credential = URLCredential(user: username, password: password, persistence: .permanent)
        
        webdav = WebDAVFileProvider(baseURL: server, credential: credential)!
        webdav?.delegate = self as FileProviderDelegate
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func createFolder(_ sender: Any) {
        webdav?.create(folder: "new folder", at: "/", completionHandler: nil)
    }
    
    @IBAction func createFile(_ sender: Any) {
        let data = "Hello world from sample.txt!".data(encoding: .utf8)
        webdav?.writeContents(path: "sample.txt", content: data, atomically: true, completionHandler: nil)
    }
    
    @IBAction func getData(_ sender: Any) {
        webdav?.contents(path: "sample.txt", completionHandler: {
            contents, error in
            if let contents = contents {
                print(String(data: contents, encoding: .utf8))
            }
        })
    }
    
    @IBAction func remove(_ sender: Any) {
        webdav?.removeItem(path: "sample.txt", completionHandler: nil)
    }
    
    @IBAction func download(_ sender: Any) {
        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("fileprovider.png")
        let remotePath = "fileprovider.png"
        
        let progress = webdav?.copyItem(path: remotePath, toLocalURL: localURL, completionHandler: nil)
        downloadProgressView.observedProgress = progress
    }
    
    @IBAction func upload(_ sender: Any) {
        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("fileprovider.png")
        let remotePath = "/fileprovider.png"
        
        let progress = webdav?.copyItem(localFile: localURL, to: remotePath, completionHandler: nil)
        uploadProgressView.observedProgress = progress
    }
    
    func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType) {
        switch operation {
        case .copy(source: let source, destination: let dest):
            print("\(source) copied to \(dest).")
        case .remove(path: let path):
            print("\(path) has been deleted.")
        default:
            if let destination = operation.destination {
                print("\(operation.actionDescription) from \(operation.source) to \(destination) succeed.")
            } else {
                print("\(operation.actionDescription) on \(operation.source) succeed.")
            }
        }
    }
    
    func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType, error: Error) {
        switch operation {
        case .copy(source: let source, destination: let dest):
            print("copying \(source) to \(dest) has been failed.")
        case .remove:
            print("file can't be deleted.")
        default:
            if let destination = operation.destination {
                print("\(operation.actionDescription) from \(operation.source) to \(destination) failed.")
            } else {
                print("\(operation.actionDescription) on \(operation.source) failed.")
            }
        }
    }
    
    func fileproviderProgress(_ fileProvider: FileProviderOperations, operation: FileOperationType, progress: Float) {
        switch operation {
        case .copy(source: let source, destination: let dest) where dest.hasPrefix("file://"):
            print("Downloading \(source) to \((dest as NSString).lastPathComponent): \(progress * 100) completed.")
        case .copy(source: let source, destination: let dest) where source.hasPrefix("file://"):
            print("Uploading \((source as NSString).lastPathComponent) to \(dest): \(progress * 100) completed.")
        case .copy(source: let source, destination: let dest):
            print("Copy \(source) to \(dest): \(progress * 100) completed.")
        default:
            break
        }
    }
}
