![File Provider](Docs/fileprovider.png)

> This Swift library provide a swifty way to deal with local and remote files and directories in a unified way.

<center>

[![Swift Version][swift-image]][swift-url]
[![Platform][platform-image]](#)
[![License][license-image]][license-url]
[![Build Status][travis-image]][travis-url]
[![Codebeat Badge][codebeat-image]][codebeat-url]

[![Release version][release-image]][release-url]
[![CocoaPods version](https://img.shields.io/cocoapods/v/FilesProvider.svg)][cocoapods]
[![Carthage compatible][carthage-image]](https://github.com/Carthage/Carthage)
[![Cocoapods Downloads][cocoapods-downloads]][cocoapods]
[![Cocoapods Apps][cocoapods-apps]][cocoapods]

</center>

<!--- 
[![Cocoapods Doc][docs-image]][docs-url]
[![codecov](https://codecov.io/gh/amosavian/FileProvider/branch/master/graph/badge.svg)](https://codecov.io/gh/amosavian/FileProvider) 
---> 

This library provides implementaion of WebDav, FTP, Dropbox, OneDrive and SMB2 (incomplete) and local files.

All functions do async calls and it wont block your main thread.

## Features

- [x] **LocalFileProvider** a wrapper around `FileManager` with some additions like builtin coordinating, searching and reading a portion of file.
- [x] **CloudFileProvider** A wrapper around app's ubiquitous container API of iCloud Drive.
- [x] **WebDAVFileProvider** WebDAV protocol is defacto file transmission standard, supported by some cloud services like `ownCloud`, `Box.com` and `Yandex.disk`.
- [x] **FTPFileProvider** While deprecated in 1990s due to serious security concerns, it's still in use on some Web hosts.
- [x] **DropboxFileProvider** A wrapper around Dropbox Web API.
    * For now it has limitation in uploading files up to 150MB.
- [x] **OneDriveFileProvider** A wrapper around OneDrive REST API, works with `onedrive.com` and compatible (business) servers.
- [ ] **AmazonS3FileProvider** Amazon storage backend. Used by many sites.
- [ ] **GoogleFileProvider** A wrapper around Goodle Drive REST API.
- [ ] **SMBFileProvider** SMB2/3 introduced in 2006, which is a file and printer sharing protocol originated from Microsoft Windows and now is replacing AFP protocol on macOS.
    * Data types and some basic functions are implemented but *main interface is not implemented yet!*.
    * SMBv1/CIFS is insecure, deprecated and kinda tricky to be implemented due to strict memory allignment in Swift.

## Requirements

- **Swift 4.0 or higher**
- iOS 8.0 , OSX 10.10
- XCode 9.0

Legacy version is available in swift-3 branch.

## Installation

### Important: this library has been renamed to avoid conflict in iOS 11, macOS 10.13 and Xcode 9.0. Please read issue [#53](https://github.com/amosavian/FileProvider/issues/53) to find more.


### Cocoapods / Carthage / Swift Package Manager

Add this line to your pods file:

```ruby
pod "FilesProvider"
```

Or add this to Cartfile:

```
github "amosavian/FileProvider"
```

Or to use in Swift Package Manager add this line in `Dependencies`:

```swift
.Package(url: "https://github.com/amosavian/FileProvider.git", majorVersion: 0)
```

### Manually

To have latest updates with ease, use this command on terminal to get a clone:

```bash
git clone https://github.com/amosavian/FileProvider
```

You can update your library using this command in FileProvider folder:

```bash
git pull
```

if you have a git based project, use this command in your projects directory to add this project as a submodule to your project:

```bash
git submodule add https://github.com/amosavian/FileProvider
```
Then you can do either:

* Copy Source folder to your project and Voila!

* Drop `FilesProvider.xcodeproj` to you Xcode workspace and add the framework to your Embeded Binaries in target.

## Design

To find design concepts and how to implement a custom provider, read [Concepts and Design document](Docs/DESIGN.md).

## Usage

Each provider has a specific class which conforms to FileProvider protocol and share same syntax.

Find a [sample code for iOS here](Docs/Sample-iOS.swift).

### Initialization

For LocalFileProvider if you want to deal with `Documents` folder:

```	swift
import FilesProvider

let documentsProvider = LocalFileProvider()

// Equals with:
let documentsProvider = LocalFileProvider(for: .documentDirectory, in: .userDomainMask)

// Equals with:
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let documentsProvider = LocalFileProvider(baseURL: documentsURL)
```

Also for using group shared container:

```swift
import FilesProvider

let documentsProvider = LocalFileProvider(sharedContainerId: "group.yourcompany.appContainer")
// Replace your group identifier
```

You can't change the base url later. and all paths are related to this base url by default.

To initialize an iCloud Container provider look at [here](https://medium.com/ios-os-x-development/icloud-drive-documents-1a46b5706fe1) to see how to update project settings then use below code, This will automatically manager creating Documents folder in container:

```swift
import FilesProvider

let documentsProvider = CloudFileProvider(containerId: nil)
```


For remote file providers authentication may be necessary:

```	swift
import FilesProvider

let credential = URLCredential(user: "user", password: "pass", persistence: .permanent)
let webdavProvider = WebDAVFileProvider(baseURL: URL(string: "http://www.example.com/dav")!, credential: credential)
```

* In case you want to connect non-secure servers for WebDAV (http) or FTP in iOS 9+ / macOS 10.11+ you should disable App Transport Security (ATS) according to [this guide.](https://gist.github.com/mlynch/284699d676fe9ed0abfa)

* For Dropbox & OneDrive, user is clientID and password is Token which both must be retrieved via OAuth2 API o. There are libraries like [p2/OAuth2](https://github.com/p2/OAuth2) or [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift) which can facilate the procedure to retrieve token. The latter is easier to use and prefered. Please see [OAuth example for Dropbox and OneDrive](Docs/OAuth.md) for detailed instruction.
	
For interaction with UI, set delegate property of `FileProvider` object.

You can use `url(of:)` method if provider to get direct access url (local or remote files) for some file systems which allows to do so (Dropbox doesn't support and returns path simply wrapped in URL).

### Delegates

For updating User interface please consider using delegate method instead of completion handlers. Delegate methods are guaranteed to run in main thread to avoid bugs.

There's simply three method which indicated whether the operation failed, succeed and how much of operation has been done (suitable for uploading and downloading operations).

Your class should conforms `FileProviderDelegate` class:

```swift
override func viewDidLoad() {
	documentsProvider.delegate = self as FileProviderDelegate
}
	
func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType) {
	switch operation {
	case .copy(source: let source, destination: let dest):
		print("\(source) copied to \(dest).")
	case .remove(path: let path):
		print("\(path) has been deleted.")
	default:
		print("\(operation.actionDescription) from \(operation.source!) to \(operation.destination) succeed")
	}
}

func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType) {
    switch operation {
	case .copy(source: let source, destination: let dest):
		print("copy of \(source) failed.")
	case .remove:
		print("file can't be deleted.")
	default:
		print("\(operation.actionDescription) from \(operation.source!) to \(operation.destination) failed")
	}
}
	
func fileproviderProgress(_ fileProvider: FileProviderOperations, operation: FileOperationType, progress: Float) {
	switch operation {
	case .copy(source: let source, destination: let dest):
		print("Copy\(source) to \(dest): \(progress * 100) completed.")
	default:
		break
	}
}
```

**Note:** `fileproviderProgress()` delegate method is not called by `LocalFileProvider` currently. 

It's recommended to use completion handlers for error handling or result processing.

#### Controlling file operations

You can also implement `FileOperationDelegate` protocol to control behaviour of file operation (copy, move/rename, remove and linking), and decide which files should be removed for example and which won't. 

`fileProvider(shouldDoOperation:)` method is called before doing a operation. You sould return `true` if you want to do operation or `false` if you want to stop that operation.

`fileProvider(shouldProceedAfterError:, operation:)` will be called if an error occured during file operations. Return `true` if you want to continue operation on next files or `false` if you want stop operation further. Default value is false if you don't implement delegate.

**Note: In `LocalFileProvider`, these methods will be called for files in a directory and its subfolders recursively.**

### Directory contents and file attributes

There is a `FileObject` class which holds file attributes like size and creation date. You can retrieve information of files inside a directory or get information of a file directly.

For a single file:

```swift
documentsProvider.attributesOfItem(path: "/file.txt", completionHandler: {
	attributes, error in
	if let attributes = attributes {
		print("File Size: \(attributes.size)")
		print("Creation Date: \(attributes.creationDate)")
		print("Modification Date: \(attributes.modifiedDate)")
		print("Is Read Only: \(attributes.isReadOnly)")
	}
})
```

To get list of files in a directory:

```swift
documentsProvider.contentsOfDirectory(path: "/", completionHandler: {
	contents, error in
	for file in contents {
		print("Name: \(file.name)")
		print("Size: \(file.size)")
		print("Creation Date: \(file.creationDate)")
		print("Modification Date: \(file.modifiedDate)")
	}
})
```

To get size of strage and used/free space:

```swift
func storageProperties(completionHandler: { total, used in
	print("Total Storage Space: \(total)")
	print("Used Space: \(used)")
	print("Free Space: \(total - used)")
})
```
	
* if this function is unavailable on provider or an error has been occurred, total space will be reported `-1` and used space `0`

### Creating File and Folders

Creating new directory:

```swift
documentsProvider.create(folder: "new folder", at: "/", completionHandler: { error in
    if let error = error {
        // Error handling here
    } else {
        // The operation succeed
    }
})
```

To create a file, use `writeContents(path:, content:, atomically:, completionHandler:)` method.

### Copy and Move/Rename Files

Copy file old.txt to new.txt in current path:

```swift
documentsProvider.copyItem(path: "new folder/old.txt", to: "new.txt", overwrite: false, completionHandler: nil)
```

Move file old.txt to new.txt in current path:

```swift
documentsProvider.moveItem(path: "new folder/old.txt", to: "new.txt", overwrite: false, completionHandler: nil)
```

**Note:** To have a consistent behavior, create intermediate directories first if necessary.

### Delete Files

```swift
documentsProvider.removeItem(path: "new.txt", completionHandler: nil)
```

### Fetching Contents of File

There is two method for this purpose, one of them loads entire file into `Data` and another can load a portion of file.

```swift
documentsProvider.contents(path: "old.txt", completionHandler: {
	contents, error in
	if let contents = contents {
		print(String(data: contents, encoding: .utf8)) // "hello world!"
	}
})
```
	
If you want to retrieve a portion of file you can use `contents` method with offset and length arguments. Please note first byte of file has offset: 0.

```swift
documentsProvider.contents(path: "old.txt", offset: 2, length: 5, completionHandler: {
	contents, error in
	if let contents = contents {
		print(String(data: contents, encoding: .utf8)) // "llo w"
	}
})
```

### Write Data To Files

```swift
let data = "What's up Newyork!".data(encoding: .utf8)
documentsProvider.writeContents(path: "old.txt", content: data, atomically: true, completionHandler: nil)
```

### Copying Files to and From Local Storage

There are two methods to download and upload files between provider's and local storage. These methods use `URLSessionDownloadTask` and `URLSessionUploadTask` classes and allows to use background session and provide progress via delegate.

To upload a file:

```swift
let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("image.jpg")
documentsProvider.copyItem(localFile: fileURL, to: "/upload/image.jpg", overwrite: true, completionHandler: nil)
```

To download a file:

```swift
let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("image.jpg")
documentsProvider.copyItem(path: "/download/image.jpg", toLocalURL: fileURL, overwrite: true, completionHandler: nil)
```

* It's safe only to assume these methods **won't** handle directories to upload/download recursively. If you need, you can list directories, create directories on target and copy files using these methods.
* FTP provider allows developer to either use apple implemented `URLSessionDownloadTask` or custom implemented method based on stream task via `useAppleImplementation` property. FTP protocol is not supported by background session.

### Operation Progress

Creating/Copying/Deleting/Searching functions return a `(NS)Progress`. It provides operation type, progress and a `.cancel()` method which allows you to cancel operation in midst. You can check `cancellable` property to check either you can cancel operation via this object or not.

- **Note:** Progress reporting is not supported by native `(NS)FileManager` so `LocalFileProvider`.

### Undo Operations

Providers conform to `FileProviderUndoable` can perform undo for **some** operations like moving/renaming, copying and creating (file or folder). **Now, only `LocalFileProvider` supports this feature.** To implement:

```swift
// To setup a new UndoManager:
documentsProvider.setupUndoManager()
// or if you have an UndoManager object already:
documentsProvider.undoManager = self.undoManager

// e.g.: To undo last operation manually:
documentsProvider.undoManager?.undo()
``` 

You can also bind `UndoManager` object with view controller to use shake gesture and builtin undo support in iOS/macOS, add these code to your ViewController class like this sample code:

```swift
class ViewController: UIViewController
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var undoManager: UndoManager? {
        return (provider as? FileProvideUndoable)?.undoManager
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Your code here
        UIApplication.shared.applicationSupportsShakeToEdit = true
        self.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Your code here
        UIApplication.shared.applicationSupportsShakeToEdit = false
        self.resignFirstResponder()
    }
    // The rest of your implementation
}
```

### File Coordination

`LocalFileProvider` and its descendents has a `isCoordinating` property. By setting this, provider will use `NSFileCoordinating` class to do all file operations. It's mandatory for iCloud, while recommended when using shared container or anywhere that simultaneous operations on a file/folder is common.

### Monitoring File Changes

You can monitor updates in some file system (Local and SMB2), there is three methods in supporting provider you can use to register a handler, to unregister and to check whether it's being monitored or not. It's useful to find out when new files added or removed from directory and update user interface. The handler will be dispatched to main threads to avoid UI bugs with a 0.25 sec delay.

```swift
// to register a new notification handler
documentsProvider.registerNotifcation(path: "/") {
	// calling functions to update UI 
}
	
// To discontinue monitoring folders:
documentsProvider.unregisterNotifcation(path: "/")
```

* **Please note** in LocalFileProvider it will also monitor changes in subfolders. This behaviour can varies according to file system specification.

### Thumbnail and meta-information

Providers which conform `ExtendedFileProvider` are able to generate thumbnail or provide file meta-information for images, media and pdf files.

Local, OneDrive and Dropbox providers support this functionality.

##### Thumbnails
To check either file thumbnail is supported or not and fetch thumbnail, use (and modify) these example code:

```swift
let path = "/newImage.jpg"
let thumbSize = CGSize(width: 64, height: 64) // or nil which renders to default dimension of provider
if documentsProvider.thumbnailOfFileSupported(path: path {
    documentsProvider.thumbnailOfFile(path: file.path, dimension: thumbSize, completionHandler: { (image, error) in
        // Interacting with UI must be placed in main thread
        DispatchQueue.main.async {
            self.previewImage.image = image
        }
    }
}
```

* Please note it won't cache generated images. if you don't do it yourself, it may hit you app's performance.

##### Meta-informations

To get meta-information like image/video taken date, location, dimension, etc., use (and modify) these example code:

```swift
if documentsProvider..propertiesOfFile(path: file.path, completionHandler: { (propertiesDictionary, keys, error) in
    for key in keys {
        print("\(key): \(propertiesDictionary[key])")
    }
}
```

* **Bonus:** You can modify/extend Local provider generator by setting `LocalFileInformationGenerator` static variables and methods

## Contribute

We would love for you to contribute to **FileProvider**, check the `LICENSE` file for more info.

Things you may consider to help us:

- [ ] Implement request/response stack for `SMBClient`
- [ ] Implement Test-case (`XCTest`)
- [ ] Add Sample project for iOS
- [ ] Add Sample project for macOS

## Projects in use

* [EDM - Browse and Receive Files](https://itunes.apple.com/us/app/edm-browse-and-receive-files/id948397575?ls=1&mt=8)
* [File Manager - PDF Reader & Music Player](https://itunes.apple.com/us/app/file-manager-pdf-reader-music/id1017809685?ls=1&mt=8)

If you used this library in your project, you can open an issue to inform us.

## Meta

Amir-Abbas Mousavian – [@amosavian](https://twitter.com/amosavian)

Thanks to [Hootan Moradi](https://github.com/hoootan) for designing logo.

Distributed under the MIT license. See `LICENSE` for more information.

[https://github.com/amosavian/](https://github.com/amosavian/)

[cocoapods]: https://cocoapods.org/pods/FilesProvider
[cocoapods-old]: https://cocoapods.org/pods/FileProvider
[swift-image]: https://img.shields.io/badge/swift-4.0-orange.svg
[swift-url]: https://swift.org/
[platform-image]: https://img.shields.io/cocoapods/p/FilesProvider.svg
[license-image]: https://img.shields.io/github/license/amosavian/FileProvider.svg
[license-url]: LICENSE
[codebeat-image]: https://codebeat.co/badges/7b359f48-78eb-4647-ab22-56262a827517
[codebeat-url]: https://codebeat.co/projects/github-com-amosavian-fileprovider
[travis-image]: https://travis-ci.org/amosavian/FileProvider.svg
[travis-url]: https://travis-ci.org/amosavian/FileProvider
[release-url]: https://github.com/amosavian/FileProvider/releases
[release-image]: https://img.shields.io/github/release/amosavian/FileProvider.svg
[carthage-image]: https://img.shields.io/badge/Carthage-compatible-4BC51D.svg
[cocoapods-downloads-old]: https://img.shields.io/cocoapods/dt/FileProvider.svg
[cocoapods-apps-old]: https://img.shields.io/cocoapods/at/FileProvider.svg
[cocoapods-downloads]: https://img.shields.io/cocoapods/dt/FilesProvider.svg
[cocoapods-apps]: https://img.shields.io/cocoapods/at/FilesProvider.svg
[docs-image]: https://img.shields.io/cocoapods/metrics/doc-percent/FilesProvider.svg
[docs-url]: http://cocoadocs.org/docsets/FilesProvider/
## Support on Beerpay
Hey dude! Help me out for a couple of :beers:!

[![Beerpay](https://beerpay.io/amosavian/FileProvider/badge.svg?style=beer-square)](https://beerpay.io/amosavian/FileProvider)  [![Beerpay](https://beerpay.io/amosavian/FileProvider/make-wish.svg?style=flat-square)](https://beerpay.io/amosavian/FileProvider?focus=wish)