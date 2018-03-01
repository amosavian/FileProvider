![File Provider](fileprovider.png)

# Concepts and Design

## Protocols and base classes

Every provider class conforms to some of the protocols each defines which operations are doable by a particular provider.
This allows developers to work with any provider class and to use a simple downcast to
intended protocol via `as?` optional keyword and call intended method.

### FileProviderBasic

This protocols consists basic variables necessary for all providers and functions to query contents and status of provider.

`type` static property should return a string which is usually provider's name.
Value can be usedfor display purposes and to compare two different instances' type.

`baseURL` determines root url of provider instance.
Some providers doesn't map url to files thus this variable is set to nil. `url(of:)` default implementation 
uses this url to create a url which points to specified path.

`dispatch_queue` and `operation_queue` are dispatch and operation queues used to have async operation.
As a rule of thumb, file operations are done in operation queue and querying are done by dispatch queue. 
Some objects and classes like `NSFileCoordinator` uses OperationQueue for async operations.

`delegate` is a used to inform controller about operation status/progress to update UI.
Avoid calling delegate methods directly and use `delegateNotify()` method in your implementation instead.

`credential` property stores user and password necessary to access provider.
Local provider would ignore it.

If listing query is paginated `contentsOfDirectory()` and `searchFiles()` may return both truncated
list array and error in case 2nd page can't be retrieved.
Thus it's safe to check `error` first to ensure list is complete. Truncated result is usable until full list is retrieved.

`storageProperties()` returns `VolumeObject` see below for more information.

When implementing `searchFiles()`, check `fileObject.mapPredicate()` using `query.evaluate(with:)`.
You may use `query` parameter to create a search string if provider supports search functionality.

Practically, `searchFiles(path: path, recursive: false, query: NSPredicate(format: "TRUEPREDICATE"))` should be equal with `contentsOfDirectory()` method.
Consequently, if provider enlisting and search backend are same (e.g. iCloud, OneDrive or Google)
implement `contentsOfDirectory()` as a wrapper around `searchFiles()`,
otherwise implement'em independently for optimization reason.

Avoid `isReachable()` to check connectivity and reachability.
Instead do operation and allow it o fail if there is a connection problem.
It may be deprecated at any time.

`url(of:)` and `relativePathOf(url:)` have default implementation which build a url using `baseURL` property.
In case that `baseURL` is `nil`, it will wrap path inside a `URL` instance.
You may override them if more functionality is needed (e.g. OneDrive) or appending path to baseURL can't be mapped to file url directly.

### FileProviderBasicRemote

Adds a `session` and `cache` object for providers that need internet connection and `URLSession` object.
If your provider is a HTTP based api, subclass `HTTPFileProvider` class otherwise
(e.g. FTP or SMB) conform it to this protocol.

### FileProviderOperations

This protocol encapsulates methods for copying, moving, renaming, removing and downloading/uploading files. 

If your provider is a subclass of `HTTPFileProvider`, you may implement
`request(for:, overwrite:, attributes:)` abstract method which handles default implementation for these methods.
In this case, you need to create a `URLRequest` object based on `operation` parameter,
usually done a switch case statement. 
See [`WebDAVFileProvder`](Sources/WebDAVFileProvider.swift) and [`OneDriveFileProvider`](Sources/OneDriveFileProvider) classes to see an example. 

### FileProviderReadWrite

This protocol declares three methods to read and write files.

You must care about memory when using these functions. If you must handle big data,
write it to a temporary file and use `copyItem(localFile:, to:)` or `copyItem(path:, toLocalURL:)` methods accordingly.
 
### FileProviderMonitor

This protocol allows developer to update UI when file list is changed.
It's not implemented for all providers and some providers like FTP and WebDAV don't support such functionality.

If you are implementing it for a HTTP-based provider,
use `longpoolSession` to create a monitor request to avoid expiring requests frequently.

Implementation details vary based on provider specifications.

### FileProvideUndoable

Implementing this protocol is a little hard as you must save operation inside `undoManager` for any operation.


### FileProviderSharing

`publicLink(to:, completionHandler:)` method allows user to share file with other people.
Not all providers support this functionality and implementation details vary based on provider specification.

### ExtendedFileProvider

This protocol provides a way to fetch files' thumbnail and metadata.
Providers which have endpoint to get meta data (like Dropbox) implements this protocol.
Due to extensive network overload of fetching thumbnail, 
It's recommended to check file using `thumbnailOfFileSupported(path)` method
to find out either provider supports thumbnail generation for specified file or not.
These methods only check file extension as a indicator and won't check file using provider.
A `true` result does not indicate that the file really has a thumbnail or not.

Implementation of `thumbnailOfFile(path:, dimension:)` must provide a NSImage/UIImage with size
according to `dimension` parameter. If server supports requesting thumbnail with specified size,
implementation would pass requested dimension to server,
otherwise implementation must resize image using `ExtendedFileProvider.scaleDown(image:, toSize:)` method to resize image.

`ExtendedFileProvider.convertToImage(pdfURL:, page:)` and `ExtendedFileProvider.convertToImage(pdfPage:)` methods can convert pdf file into an image.
Please note `pdfURL` parameter must be a local file url.

`propertiesOfFile()` method will extract meta data of specified file and return it as a dictionary orders by `keys` parameter.
Keys may vary according to file type, e.g. EXIF data for an image or ID3 tags for a music file. 

To extend thumbnail generation behavior for local file to types which are not supported by Apple platform,
you may change `LocalFileInformationGenerator` struct static properties.
Some methods in this struct are unimplemented to allow developer to use third-party libraries
to provide meta data and thumbnail for other types of file.

### FileProvider

This protocol does not define any method, but indicates that class conforms to `FileProviderBasic `,
`FileProviderOperations`, `FileProviderReadWrite` and `NSCopying` protocols.

### FileOperationType

This enum holds operation type and associated information like source and destination path.
Developer is exposed to this enum in delegate methods.
Internally it's extensively used to refactor operation methods and to store operation info in
related `URLSessionTask` inside `taskDescription` property.

As a associated enum, it can not be bridged to Objective-C.

### FileObject

`FileObject` class stores file properties in a dictionary with `URLResourceKey` as key type.
All other properties are computed variables and simply cast value to a strict swift type.

Provider will create and return instance of `FileObject` class or its descendants in `contentsOfDirectory()`, `attributesOfItem()` and `searchFiles()` methods.
Provider **must** set `name` and `path` properties.

`path`'s value can be a unix-style hierarchal path or other ways to point a file supported by server.
Some providers like Dropbox and OneDrive define accessing to file by id or revision.
As a convention, these alternative paths are structured like `type:identifier` e.g. `rev:abcd1234` or `id:abcd1234`.
Google only allows to address file with `id:abcd1234` and does not provide unix-style path.

- **Important:** Never rely on `path` last component to extract file name, instead use `name` property.
Providers like `Google` have only file id in path thus using `path.lastPathComponent` to display file name may lead to confusion and improper result.

### VolumeObject

`VolumeObject` class is identical to `FileObject` structurally but only uses `URLResourceKey`'s keys which begin with `volume`.
An implementation of provider must return this enumerated in `storageProperties()` with properties like total size and free space of storage.

There is not correspondent key in storage for `usage` property, 
indeed it's calculated by subtracting available space from total space.

## Progress handling

Almost all methods return a `Progress` instance which encapsulates progress fraction and a way to cancel entire operation.
It's upon your provider's implementation to update progress `totalUnitCount` and `completedUnitCount` properties and assign a cancellation handler to Progress object.
Cancellation handler may call `Operation`'s or `URLSessionTask`'s `cancel()` method to interrupt operation.

A typical progress handling in this library is like this:

```swift
// totalUnitCount must be set to file size for downloading/uploading operation.
// totalUnitCount must be set to 1 for a simple remote file operation.
let progress = Progress(totalUnitCount: size)
// allow updating progress inside URLSession's delegate methods
progress.setUserInfoObject(operation, forKey: .fileProvderOperationTypeKey)
// kind must be set to .file for downloading/uploading operation.
progress.kind = .file
progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
// progres.cancel() will call task.cancel() method.
progress.cancellationHandler = { [weak task] in
    task?.cancel()
}
// Set .startingTimeKey to calculate estimated remaining time and speed in delegate.
progress.setUserInfoObject(Date(), forKey: .startingTimeKey)
```

Please note `.fileProvderOperationTypeKey` and `.startingTimeKey` are custom user info assigned to progress
to allow updating progress inside URLSession's delegate methods and calculating estimated remaining time and speed.
Your implementation must set these user info objects if you are using `SessionDelegate` object.

You may update cancellation handler if another task is added.

## Error handling

This library doesn't manipulate errors returned by Foundation methods and uses `URLError` and `CococaError` to report error as far as there is a corresponding defined error.
You can use `urlError(_ :, code:)` and `cocoaError(_:, code:)` convenience methods to create error object.

For HTTP providers, `FileProviderHTTPError` protocol defines a way to encapsulate HTTP status code and returned description by server.
You may declare a struct conforming to `FileProviderHTTPError` with an initializer to interpret server response.
`serverError(with:, path:, data:)` must be implemented in  `HTTPFileProvider` subclasses and will be called by HTTP provider default implementation to digest error.

**NEVER** define a custom enum for errors. Instead use Foundation errors like `URLError` and `CococaError` as
they provide comprehensive localized description for error.
Alternatively use `FileProviderHTTPError` conforming struct for HTTP providers.

## Implementing HTTP-based Custom Provider

This library provide `HTTPFileProvider` abstract class to easily implement provider which connects to a cloud/server that
uses http protocol for connection.
That's almost all REST and web based providers like Dropbox, Box, Google Drive, etc.

`HTTPFileProvider` encapsulates much of downloading/uploading logic and provides `paginated` method
to allow enlisting/searching files in providers which return result in progressively. (e.g. Dropbox and OneDrive)

By subclassing `HTTPFileProvider` class, you must override half a dozen of methods, mainly querying methods.
Your implementation may cause a **crash** if you fail to override these methods.

### Methods and properties to override

`type` static property, which returns name of provider.

`init?(coder:)` decodes and initialize instance using `NSCoder`.
Your implementation must read `aDecoder` correspondent keys and initialize a new object using your provider's initilizer.

`copy(with:)` method must create a new instance and assign properties from source (`self`) to copied object.

`contentsOfDirectory()` and `searchFiles()` methods must send listing query to server and decode json/xml response into a `FileObject`.
Providers may subclass `FileObject` and implement an initializer to encapsulate decoding logic.
If server response is paginated, use `paginated()` method. See below and inline help to find how to use it.

`attributesOfItem()` must send file attribute fetching query to server and decode response into a `FileObject` or its descendants instance.

`storageProperties()` does querying account/cloud quota and encapsulates it into a `VolumeObject` instance.
You don't need to subclass `VolumeObject`.
If your server does not support such functionality, simply call completion handler with `nil` as result.

`request(for:, overwrite:, attributes:)` creates a `URLRequest` for requested operation.
It will be called by create, copy/move and remove functions.
You may set `httpMethod` and `httpBody` and header values of request regarding operation type and associated variables.

- **Important:** NEVER forget to call `urlrequest.setValue(authentication: credential, with:)` to set provider's credential
if server uses OAuth/OAuth2 authentication method.
You may need to set other http headers according to server specifications.

- **Important**: `copyItem(path:, toLocalURL:)` and `copyItem(localFile:, to:)` methods will call `request(for:)` method with
source/destination property set to a local file url, begins with `file://`.
You must handle these separately.
See `WebDAVProvider` [source](Sources/WebDAVFileProvider.swift) as an example.

`serverError(with:, path:, data:)` method will digest http status code and server response data to create an error conforming to `FileProviderHTTPError` protocol.

### Optional overridable methods

`isReachable()` default implementation tries to fetch storage properties and will return true if result is non-nil.
You may need to override this method if server does not support `storageProperties()` or there is a more optimized way to check reachability.

`copyItem(localFile:, to:)` and `writeContents(path:, contents:)` can be overrided if server requires upload session.
See `OneDriveProvider`'s [source](Sources/OneDriveProvider) to see how create and handle an upload session.

### Paginated enlisting

`paginated()` method defines an easy way to communicate to servers which list responses are paginated. 
Here is method signature:

`pageHandler` closure gets server response as `Data`, decodes it and returns `FileObject` array or an error,
and if there is another sequel page, passes token of new page (a string tha can be a id or url) to `newToken`.
If there is no more sequel page, `newToken` must be nil.

This token will be delivered to `requestHandler` closure which returns a `URLRequest` according to token.
A nil token indicates it's the first page.
`completionHandler` is the closure which user passed to `contentsOfDirectory()` or `searchFiles()` methods.

`pageHandler` must update `progress` by adding the number of new files enlisted to `completedUnitCount` property.
This closure may filter results according to `query` parameter, using `query.evaluate(with:)`.
