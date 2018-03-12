//
//  FilesProviderTests.swift
//  FilesProviderTests
//
//  Created by Amir Abbas on 8/11/1396 AP.
//

import XCTest
import FilesProvider

class FilesProviderTests: XCTestCase, FileProviderDelegate {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        try? FileManager.default.removeItem(at: dummyFile())
    }
    
    func testLocal() {
        let provider = LocalFileProvider()
        addTeardownBlock {
            self.testRemoveFile(provider, filePath: self.testFolderName)
        }
        testBasic(provider)
        testOperations(provider)
    }
    
    func testWebDav() {
        guard let urlStr = ProcessInfo.processInfo.environment["webdav_url"] else { return }
        let url = URL(string: urlStr)!
        let cred: URLCredential?
        if let user = ProcessInfo.processInfo.environment["webdav_user"], let pass = ProcessInfo.processInfo.environment["webdav_password"] {
            cred = URLCredential(user: user, password: pass, persistence: .forSession)
        } else {
            cred = nil
        }
        let provider = WebDAVFileProvider(baseURL: url, credential: cred)!
        provider.delegate = self
        addTeardownBlock {
            self.testRemoveFile(provider, filePath: self.testFolderName)
        }
        testOperations(provider)
    }
    
    func testDropbox() {
        guard let pass = ProcessInfo.processInfo.environment["dropbox_token"] else {
            return
        }
        let cred = URLCredential(user: "testuser", password: pass, persistence: .forSession)
        let provider = DropboxFileProvider(credential: cred)
        provider.delegate = self
        addTeardownBlock {
            self.testRemoveFile(provider, filePath: self.testFolderName)
        }
        testBasic(provider)
        testOperations(provider)
    }
    
    func testFTPPassive() {
        guard let urlStr = ProcessInfo.processInfo.environment["ftp_url"] else { return }
        let url = URL(string: urlStr)!
        let cred: URLCredential?
        if let user = ProcessInfo.processInfo.environment["ftp_user"], let pass = ProcessInfo.processInfo.environment["ftp_password"] {
            cred = URLCredential(user: user, password: pass, persistence: .forSession)
        } else {
            cred = nil
        }
        let provider = FTPFileProvider(baseURL: url, mode: .extendedPassive, credential: cred)!
        provider.delegate = self
        addTeardownBlock {
            self.testRemoveFile(provider, filePath: self.testFolderName)
        }
        testOperations(provider)
    }
    
    func testOneDrive() {
        guard let pass = ProcessInfo.processInfo.environment["onedrive_token"] else {
            return
        }
        let cred = URLCredential(user: "testuser", password: pass, persistence: .forSession)
        let provider = OneDriveFileProvider(credential: cred)
        provider.delegate = self
        addTeardownBlock {
            self.testRemoveFile(provider, filePath: self.testFolderName)
        }
        testBasic(provider)
        testOperations(provider)
    }
    
    /*
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    */
    
    let timeout: Double = 60.0
    let testFolderName = "Test"
    let textFilePath = "/Test/file.txt"
    let renamedFilePath = "/Test/renamed.txt"
    let uploadFilePath = "/Test/uploaded.dat"
    let sampleText = "Hello world!"
    
    fileprivate func testCreateFolder(_ provider: FileProvider, folderName: String) {
        let desc = "Creating folder at root in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.create(folder: folderName, at: "/") { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testContentsOfDirectory(_ provider: FileProvider) {
        let desc = "Enumerating files list in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.contentsOfDirectory(path: "/") { (files, error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertGreaterThan(files.count, 0, "list is empty")
            let testFolder = files.filter({ $0.name == self.testFolderName }).first
            XCTAssertNotNil(testFolder, "Test folder didn't listed")
            guard testFolder != nil else { return }
            XCTAssertTrue(testFolder!.isDirectory, "Test entry is not a folder")
            XCTAssertLessThanOrEqual(testFolder!.size, 0, "folder size is not -1")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testAttributesOfFile(_ provider: FileProvider, filePath: String) {
        let desc = "Attrubutes of file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.attributesOfItem(path: filePath) { (fileObject, error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertNotNil(fileObject, "file '\(filePath)' didn't exist")
            guard fileObject != nil else { return }
            XCTAssertEqual(fileObject!.path, filePath, "file path is different from '\(filePath)'")
            XCTAssertEqual(fileObject!.type, URLFileResourceType.regular, "file '\(filePath)' is not a regular file")
            XCTAssertGreaterThan(fileObject!.size, 0, "file '\(filePath)' is empty")
            XCTAssertNotNil(fileObject!.modifiedDate, "file '\(filePath)' has no modification date")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testCreateFile(_ provider: FileProvider, filePath: String) {
        let desc = "Creating file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        let data = sampleText.data(using: .ascii)
        provider.writeContents(path: filePath, contents: data, overwrite: true) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout * 3)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testContentsFile(_ provider: FileProvider, filePath: String, hasSampleText: Bool = true) {
        let desc = "Reading file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.contents(path: filePath) { (data, error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertNotNil(data, "no data for test file")
            if data != nil && hasSampleText {
                let str = String(data: data!, encoding: .ascii)
                XCTAssertNotNil(str, "test file data not readable")
                XCTAssertEqual(str, self.sampleText, "test file data didn't matched")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout * 3)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testRenameFile(_ provider: FileProvider, filePath: String, to toPath: String) {
        let desc = "Renaming file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.moveItem(path: filePath, to: toPath, overwrite: true) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testCopyFile(_ provider: FileProvider, filePath: String, to toPath: String) {
        let desc = "Copying file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.copyItem(path: filePath, to: toPath, overwrite: true) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testRemoveFile(_ provider: FileProvider, filePath: String) {
        let desc = "Deleting file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.removeItem(path: filePath) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    private func randomData(size: Int = 262144) -> Data {
        var keyData = Data(count: size)
        let result = keyData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, keyData.count, $0)
        }
        if result == errSecSuccess {
            return keyData
        } else {
            fatalError("Problem generating random bytes")
        }
    }
    
    fileprivate func dummyFile() -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("dummyfile.dat")
        
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = randomData()
            try! data.write(to: url)
        }
        return url
    }
    
    fileprivate func testUploadFile(_ provider: FileProvider, filePath: String) {
        // test Upload/Download
        let url = dummyFile()
        let desc = "Uploading file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        let dummy = dummyFile()
        provider.copyItem(localFile: dummy, to: filePath) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout * 3)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testDownloadFile(_ provider: FileProvider, filePath: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("downloadedfile.dat")
        let desc = "Downloading file in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.copyItem(path: filePath, toLocalURL: url) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "downloaded file doesn't exist")
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.size] as? Int64
            XCTAssertEqual(size, 262144, "downloaded file size is unexpected")
            XCTAssert(FileManager.default.contentsEqual(atPath: self.dummyFile().path, andPath: url.path), "downloaded data is corrupted")
            try? FileManager.default.removeItem(at: url)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout * 3)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testStorageProperties(_ provider: FileProvider, isExpected: Bool) {
        let desc = "Querying volume in \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.storageProperties { (volume) in
            if !isExpected {
                XCTAssertNotNil(volume, "volume information is nil")
                guard volume != nil else { return }
                XCTAssertGreaterThan(volume!.totalCapacity, 0, "capacity must be greater than 0")
                XCTAssertGreaterThan(volume!.availableCapacity, 0, "available capacity must be greater than 0")
                XCTAssertEqual(volume!.totalCapacity, volume!.availableCapacity + volume!.usage, "total capacity is not equal to usage + available")
            } else {
                XCTAssertNil(volume, "volume information must be nil")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testReachability(_ provider: FileProvider) {
        let desc = "Reachability of \(provider.type)"
        print("Test started: \(desc).")
        let expectation = XCTestExpectation(description: desc)
        provider.isReachable { (status, error) in
            XCTAssertTrue(status, "\(provider.type) not reachable: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        print("Test fulfilled: \(desc).")
    }
    
    fileprivate func testBasic(_ provider: FileProvider) {
        let filepath = "/test/file.txt"
        let fileurl = provider.url(of: filepath)
        let composedfilepath = provider.relativePathOf(url: fileurl)
        XCTAssertEqual(composedfilepath, "test/file.txt", "file url synthesis error")
        
        let dirpath = "/test/"
        let dirurl = provider.url(of: dirpath)
        let composeddirpath = provider.relativePathOf(url: dirurl)
        XCTAssertEqual(composeddirpath, "test", "directory url synthesis error")
        
        let rooturl1 = provider.url(of: "")
        let rooturl2 = provider.url(of: "/")
        XCTAssertEqual(rooturl1, rooturl2, "root url synthesis error")
    }
    
    fileprivate func testOperations(_ provider: FileProvider) {
        // Test file operations
        testReachability(provider)
        testCreateFolder(provider, folderName: testFolderName)
        testContentsOfDirectory(provider)
        testCreateFile(provider, filePath: textFilePath)
        testAttributesOfFile(provider, filePath: textFilePath)
        testContentsFile(provider, filePath: textFilePath)
        testRenameFile(provider, filePath: textFilePath, to: renamedFilePath)
        testCopyFile(provider, filePath: renamedFilePath, to: textFilePath)
        testRemoveFile(provider, filePath: textFilePath)
        
        // TODO: Test search
        // TODO: Test provider delegate
        
        // Test upload/download
        testUploadFile(provider, filePath: uploadFilePath)
        testDownloadFile(provider, filePath: uploadFilePath)
    }
    
    func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType) {
        return
    }
    
    func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType, error: Error) {
        return
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
        return
    }
}
