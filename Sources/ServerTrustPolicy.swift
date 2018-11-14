//
//  ServerTrustPolicy.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

// MARK: - ServerTrustPolicy
/// The `ServerTrustPolicy` evaluates the server trust generally provided by an `NSURLAuthenticationChallenge` when
/// connecting to a server over a secure HTTPS connection. The policy configuration then evaluates the server trust
/// with a given set of criteria to determine whether the server trust is valid and the connection should be made.
///
/// Using pinned certificates or public keys for evaluation helps prevent man-in-the-middle (MITM) attacks and other
/// vulnerabilities. Applications dealing with sensitive customer data or financial information are strongly encouraged
/// to route all communication over an HTTPS connection with pinning enabled.
///
/// - performDefaultEvaluation: Uses the default server trust evaluation while allowing you to control whether to
///                             validate the host provided by the challenge. Applications are encouraged to always
///                             validate the host in production environments to guarantee the validity of the server's
///                             certificate chain.
///
/// - disableEvaluation:        Disables all evaluation which in turn will always consider any server trust as valid.
///
public enum ServerTrustPolicy {
    case performDefaultEvaluation(validateHost: Bool)
    case disableEvaluation
    
    // MARK: - Evaluation
    /// Evaluates whether the server trust is valid.
    ///
    /// - returns: Whether the server trust is valid.
    public func evaluate() -> Bool {
        var serverTrustIsValid = false
        
        switch self {
        case .performDefaultEvaluation(_):
            break
        case .disableEvaluation:
            serverTrustIsValid = true
        }
        
        return serverTrustIsValid
    }
    
    /// Evaluates whether the server trust is valid for the given host.
    ///
    /// - parameter serverTrust: The server trust to evaluate.
    /// - parameter host:        The host of the challenge protection space.
    ///
    /// - returns: Whether the server trust is valid.
    public func evaluate(_ serverTrust: SecTrust, forHost host: String) -> Bool {
        var serverTrustIsValid = false
        
        switch self {
        case let .performDefaultEvaluation(validateHost):
            let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
            SecTrustSetPolicies(serverTrust, policy)
        case .disableEvaluation:
            serverTrustIsValid = true
        }
        
        return serverTrustIsValid
    }
}
