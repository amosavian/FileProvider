//
//  FilesProviderTests.swift
//  FilesProviderTests
//
//  Created by Amir Abbas on 8/11/1396 AP.
//

import XCTest
import FilesProvider

class FilesProviderTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testLocal() {
        let localProvider = LocalFileProvider()
        testBasic(localProvider)
        testOperations(localProvider)
    }
    
    func testWebDav() {
        let webdavURL = URL(string: "https://dav.box.com/dav")!
        let webdavProvider = WebDAVFileProvider(baseURL: webdavURL, credential: nil)!
        testOperations(webdavProvider)
    }
    
    func testDropbox() {
        
    }
    
    func testOneDrive() {
        
    }
    
    /*
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    */
    
    let timeout: Double = 20.0
    let testFolderName = "Test"
    let textFilePath = "/Test/file.txt"
    let renamedFilePath = "/Test/renamed.txt"
    let uploadFilePath = "/Test/uploaded.dat"
    let sampleText = "Hello world!"
    
    fileprivate func testCreateFolder(_ provider: FileProvider, folderName: String) {
        let desc = "Creating folder at root in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.create(folder: folderName, at: "/") { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testContentsOfDirectory(_ provider: FileProvider) {
        let desc = "Enumerating files list in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.contentsOfDirectory(path: "/") { (files, error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertGreaterThan(files.count, 0, "list is empty")
            let testFolder = files.filter({ $0.name == self.testFolderName }).first
            XCTAssertNotNil(testFolder, "Test folder didn't listed")
            XCTAssertTrue(testFolder!.isDirectory, "Test entry is not a folder")
            XCTAssertLessThanOrEqual(testFolder!.size, 0, "folder size is not -1")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testAttributesOfFile(_ provider: FileProvider, filePath: String) {
        let desc = "Attrubutes of file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.attributesOfItem(path: filePath) { (fileObject, error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertNotNil(fileObject, "file '\(filePath)' didn't exist")
            XCTAssertEqual(fileObject!.path, filePath, "file path is different from '\(filePath)'")
            XCTAssertEqual(fileObject!.type, URLFileResourceType.regular, "file '\(filePath)' is not a regular file")
            XCTAssertGreaterThan(fileObject!.size, 0, "file '\(filePath)' is empty")
            XCTAssertNotNil(fileObject!.modifiedDate, "file '\(filePath)' has no modification date")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testCreateFile(_ provider: FileProvider, filePath: String) {
        let desc = "Creating file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        let data = sampleText.data(using: .ascii)
        provider.writeContents(path: filePath, contents: data, overwrite: true) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testContentsFile(_ provider: FileProvider, filePath: String, hasSampleText: Bool = true) {
        let desc = "Reading file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.contents(path: filePath) { (data, error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertNotNil(data, "no data for test file")
            if hasSampleText {
                let str = String(data: data!, encoding: .ascii)
                XCTAssertNotNil(str, "test file data not readable")
                XCTAssertEqual(str, self.sampleText, "test file data didn't matched")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testRenameFile(_ provider: FileProvider, filePath: String, to toPath: String) {
        let desc = "Renaming file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.moveItem(path: filePath, to: toPath, overwrite: true) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testCopyFile(_ provider: FileProvider, filePath: String, to toPath: String) {
        let desc = "Copying file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.copyItem(path: filePath, to: toPath, overwrite: true) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testRemoveFile(_ provider: FileProvider, filePath: String) {
        let desc = "Deleting file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.removeItem(path: filePath) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
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
        let expectation = XCTestExpectation(description: desc)
        let dummy = dummyFile()
        provider.copyItem(localFile: dummy, to: filePath) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            // TODO: check file existance of server
            try? FileManager.default.removeItem(at: url)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout * 3)
    }
    
    fileprivate func testDownloadFile(_ provider: FileProvider, filePath: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("downloadedfile.dat")
        let desc = "Downloading file in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.copyItem(path: filePath, toLocalURL: url) { (error) in
            XCTAssertNil(error, "\(desc) failed: \(error?.localizedDescription ?? "no error desc")")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "downloaded file doesn't exist")
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.size] as? Int64
            XCTAssertEqual(size, 262144, "downloaded file size is unexpected")
            try? FileManager.default.removeItem(at: url)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout * 3)
    }
    
    fileprivate func testStorageProperties(_ provider: FileProvider, isExpected: Bool) {
        let desc = "Querying volume in \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.storageProperties { (volume) in
            if !isExpected {
                XCTAssertNotNil(volume, "volume information is nil")
                XCTAssertGreaterThan(volume!.totalCapacity, 0, "capacity must be greater than 0")
                XCTAssertGreaterThan(volume!.availableCapacity, 0, "available capacity must be greater than 0")
                XCTAssertEqual(volume!.totalCapacity, volume!.availableCapacity + volume!.usage, "total capacity is not equal to usage + available")
            } else {
                XCTAssertNil(volume, "volume information must be nil")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
    
    fileprivate func testReachability(_ provider: FileProvider) {
        // Test file operations
        let desc = "Reachability of \(provider.type)"
        let expectation = XCTestExpectation(description: desc)
        provider.isReachable { (status) in
            XCTAssertTrue(status, "\(provider.type) not reachable")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
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
        
        // Cleanup, Removing not emptied directory
        testRemoveFile(provider, filePath: "/\(testFolderName)")
    }
}
