//
//  FileProvider iOS.h
//  FileProvider iOS
//
//  Created by Amir Abbas Mousavian on 5/6/95.
//
//

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
//! Project version number for FileProvider iOS.
FOUNDATION_EXPORT double FileProvider_iOSVersionNumber;
//! Project version string for FileProvider iOS.
FOUNDATION_EXPORT const unsigned char FileProvider_iOSVersionString[];

#elif defined TARGET_OS_TV
#import <UIKit/UIKit.h>
//! Project version number for FileProvider tvOS.
FOUNDATION_EXPORT double FileProvider_tvOSVersionNumber;
//! Project version string for FileProvider tvOS.
FOUNDATION_EXPORT const unsigned char FileProvider_tvOSVersionString[];

#elif defined TARGET_OS_MAC
#import <Cocoa/Cocoa.h>
//! Project version number for FileProvider OSX.
FOUNDATION_EXPORT double FileProvider_OSXVersionNumber;
//! Project version string for FileProvider OSX.
FOUNDATION_EXPORT const unsigned char FileProvider_OSXVersionString[];

#else
// Unsupported platform
#endif

// In this header, you should import all the public headers of your framework using statements like #import <FileProvider_iOS/PublicHeader.h>


