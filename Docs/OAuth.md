# Authentication

Dropbox and OneDrive are using OAuth2 authentication method. Here is sample codes to get Bearer token using [OAuthSwift](https://github.com/OAuthSwift/OAuthSwift)

## Handling url scheme in App delegate

Add these lines to your application delegate:

```swift
extension AppDelegate {
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any]) -> Bool {
        if url.host == "oauth-callback" {
            OAuthSwift.handle(url: url)
        }
        
        // HANDLING OTHER PATERNS
    }
}
```

## Dropbox

Your client id and secret must be given by Dropbox developer portal. Bearer tokens created by this method are permanent.

```swift
let appScheme = "YOUR_APP_SCHEME"
oauth = OAuth2Swift(consumerKey:    "CLIENT_ID",
                    consumerSecret: "CLIENT_SECRET",
                    authorizeUrl:   "https://www.dropbox.com/oauth2/authorize",
                    responseType:   "token")!
oauth.authorizeURLHandler = SafariURLHandler(viewController: self, oauthSwift: oauth)
_ = oauth.authorize(withCallbackURL: URL(string: "\(appScheme)://oauth-callback/dropbox")!,
    scope: "", state:"DROPBOX",
    success: { credential, response, parameters in
        let urlcredential = URLCredential(user: user ?? "anonymous", password: credential.oauthToken, persistence: .permanent)
        // TODO: Save credential in keychain
        // TODO: Create Dropbox provider using urlcredential
    }, failure: { error in
        print(error.localizedDescription)
    }
)
```

## OneDrive

Your client id must be given by Microsoft developer portal. OneDrive doesn't need client secret for native apps, but will need to refresh token every one hour.

We must save refresh token in adition to bearer token and use it when we get `.unauthorized` 401 HTTP error in completion handlers to get a new bearer token.

```swift
let appScheme = "YOUR_APP_SCHEME"
oauth = OAuth2Swift.init(consumerKey: "CLIENT_ID",
                         consumerSecret: "",
                         authorizeUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                         accessTokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                         responseType: "code")!
oauth.authorizeURLHandler = SafariURLHandler(viewController: self, oauthSwift: oauth)
if let refreshToken = {SAVED_REFRESH_TOKEN} {
    oauth.renewAccessToken(withRefreshToken: token,
        success: { credential, response, parameters in
            let urlcredential = URLCredential(user: user ?? "anonymous", password: credential.oauthToken, persistence: .permanent)
            let refreshToken = credential.oauthRefreshToken
            // TODO: Save refreshToken in keychain
            // TODO: Save credential in keychain
            // TODO: Create OneDrive provider using urlcredential
    }, failure: { error in
        print(error.localizedDescription)
        // TODO: Clear saved refresh token and call this method again to get authorization token 
    })
} else {
    _ = oauth.authorize(
        withCallbackURL: URL(string: "\(appScheme)://oauth-callback/onedrive")!,
        scope: "offline_access User.Read Files.ReadWrite.All", state: "ONEDRIVE",
        success: { credential, response, parameters in
            let credential = URLCredential(user: user ?? "anonymous", password: credential.oauthToken, persistence: .permanent)
            // TODO: Save refreshToken in keychain
            // TODO: Save credential in keychain
            // TODO: Create OneDrive provider using credential
    }, failure: { error in
        print(error.localizedDescription)
    })
}
```