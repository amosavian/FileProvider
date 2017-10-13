// Originally based on CryptoSwift by Marcin Krzyżanowski <marcin.krzyzanowski@gmail.com>
// Copyright (C) 2014 Marcin Krzyżanowski <marcin.krzyzanowski@gmail.com>
// This software is provided 'as-is', without any express or implied warranty.
//
// In no event will the authors be held liable for any damages arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
//
// - The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation is required.
// - Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
// - This notice may not be removed or altered from any source or binary distribution.

import Foundation

protocol SHA2Variant {
    static var size: Int { get }
    static var h: [UInt64] { get }
    static var k: [UInt64] { get }
    
    static func resultingArray<T>(_ hh:[T]) -> ArraySlice<T>
    static func calculate(_ message: [UInt8]) -> [UInt8]
}

protocol SHA2Variant32: SHA2Variant { }
protocol SHA2Variant64: SHA2Variant { }

extension SHA2Variant32 {
    static var size: Int {
        return 64
    }
    
    static var k: [UInt64] {
        return [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
    }
    
    // codebeat:disable[ABC]
    static func calculate(_ message: [UInt8]) -> [UInt8] {
        var tmpMessage = message
        
        let len = Self.size
        
        // Step 1. Append Padding Bits
        tmpMessage.append(0x80) // append one bit (UInt8 with one bit) to message
        
        // append "0" bit until message length in bits ≡ 448 (mod 512)
        var msgLength = tmpMessage.count
        var counter = 0
        
        while msgLength % len != (len - 8) {
            counter += 1
            msgLength += 1
        }
        
        tmpMessage.append(contentsOf: [UInt8](repeating: 0, count: counter))
        
        // hash values
        var hh: [UInt32] = Self.h.map { UInt32($0) }
        let k = Self.k
        
        // append message length, in a 64-bit big-endian integer. So now the message length is a multiple of 512 bits.
        tmpMessage.append(contentsOf: arrayOfBytes(message.count * 8, length: 64 / 8))
        
        // Process the message in successive 512-bit chunks:
        let chunkSizeBytes = 512 / 8 // 64
        for chunk in BytesSequence(chunkSize: chunkSizeBytes, data: tmpMessage) {
            // break chunk into sixteen 32-bit words M[j], 0 ≤ j ≤ 15, big-endian
            // Extend the sixteen 32-bit words into sixty-four 32-bit words:
            var M:[UInt32] = [UInt32](repeating: 0, count: k.count)
            for x in 0..<M.count {
                switch (x) {
                case 0...15:
                    let start: Int = chunk.startIndex + (x * MemoryLayout.size(ofValue: M[x]))
                    let end: Int = start + MemoryLayout.size(ofValue: M[x])
                    let le = toUInt32Array(chunk[start..<end])[0]
                    M[x] = le.bigEndian
                    break
                default:
                    let s0 = rotateRight(M[x-15], n: 7) ^ rotateRight(M[x-15], n: 18) ^ (M[x-15] >> 3) //FIXME: n
                    let s1 = rotateRight(M[x-2], n: 17) ^ rotateRight(M[x-2], n: 19) ^ (M[x-2] >> 10)
                    let s2 = M[x-16]
                    let s3 = M[x-7]
                    M[x] = s2 &+ s0 &+ s3 &+ s1
                    break
                }
            }
            
            var A = hh[0], B = hh[1], C = hh[2], D = hh[3], E = hh[4], F = hh[5], G = hh[6], H = hh[7]
            
            // Main loop
            for j in 0..<k.count {
                let s0 = rotateRight(A,n: 2) ^ rotateRight(A,n: 13) ^ rotateRight(A,n: 22)
                let maj = (A & B) ^ (A & C) ^ (B & C)
                let t2 = s0 &+ maj
                let s1 = rotateRight(E,n: 6) ^ rotateRight(E,n: 11) ^ rotateRight(E,n: 25)
                let ch = (E & F) ^ ((~E) & G)
                let t1 = H &+ s1 &+ ch &+ UInt32(k[j]) &+ M[j]
                
                H = G; G = F; F = E; E = D &+ t1
                D = C; C = B; B = A; A = t1 &+ t2
            }
            
            hh[0] = (hh[0] &+ A)
            hh[1] = (hh[1] &+ B)
            hh[2] = (hh[2] &+ C)
            hh[3] = (hh[3] &+ D)
            hh[4] = (hh[4] &+ E)
            hh[5] = (hh[5] &+ F)
            hh[6] = (hh[6] &+ G)
            hh[7] = (hh[7] &+ H)
        }
        
        // Produce the final hash value (big-endian) as a 160 bit number:
        var result = [UInt8]()
        result.reserveCapacity(hh.count / 4)
        Self.resultingArray(hh).forEach {
            let item = $0.bigEndian
            #if swift(>=4.0)
                result.append(UInt8(truncatingIfNeeded: item))
                result.append(UInt8(truncatingIfNeeded: item >> 8))
                result.append(UInt8(truncatingIfNeeded: item >> 16))
                result.append(UInt8(truncatingIfNeeded: item >> 24))
            #else
                result.append(UInt8(item))
                result.append(UInt8((item >> 8)  & 0xFF))
                result.append(UInt8((item >> 16) & 0xFF))
                result.append(UInt8((item >> 24) & 0xFF))
            #endif
            
        }
        return result
    }
    // codebeat:enable[ABC]
}

extension SHA2Variant64 {
    static var size: Int {
        return 128
    }
    
    static var k: [UInt64] {
        return [0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538,
                0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe,
                0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
                0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
                0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab,
                0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
                0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
                0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
                0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
                0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
                0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373,
                0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
                0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c,
                0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
                0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
                0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817]
    }
    
    // codebeat:disable[ABC]
    static func calculate(_ message: [UInt8]) -> [UInt8] {
        var tmpMessage = message
        
        let len = Self.size
        
        // Step 1. Append Padding Bits
        tmpMessage.append(0x80) // append one bit (UInt8 with one bit) to message
        
        // append "0" bit until message length in bits ≡ 448 (mod 512)
        var msgLength = tmpMessage.count
        var counter = 0
        
        while msgLength % len != (len - 8) {
            counter += 1
            msgLength += 1
        }
        
        tmpMessage += [UInt8](repeating: 0, count: counter)
        
        // hash values
        var hh: [UInt64] = Self.h
        let k = Self.k
        
        // append message length, in a 64-bit big-endian integer. So now the message length is a multiple of 512 bits.
        tmpMessage += arrayOfBytes(message.count * 8, length: 64 / 8)
        
        // Process the message in successive 1024-bit chunks:
        let chunkSizeBytes = 1024 / 8 // 128
        for chunk in BytesSequence(chunkSize: chunkSizeBytes, data: tmpMessage) {
            // break chunk into sixteen 64-bit words M[j], 0 ≤ j ≤ 15, big-endian
            // Extend the sixteen 64-bit words into eighty 64-bit words:
            var M = [UInt64](repeating: 0, count: k.count)
            for x in 0..<M.count {
                switch (x) {
                case 0...15:
                    let start = chunk.startIndex + (x * MemoryLayout.size(ofValue: M[x]))
                    let end = start + MemoryLayout.size(ofValue: M[x])
                    let le = toUInt64Array(chunk[start..<end])[0]
                    M[x] = le.bigEndian
                    break
                default:
                    let s0 = rotateRight(M[x-15], n: 1) ^ rotateRight(M[x-15], n: 8) ^ (M[x-15] >> 7)
                    let s1 = rotateRight(M[x-2], n: 19) ^ rotateRight(M[x-2], n: 61) ^ (M[x-2] >> 6)
                    let s2 = M[x-16]
                    let s3 = M[x-7]
                    M[x] = s2 &+ s0 &+ s3 &+ s1
                    break
                }
            }
            
            var A = hh[0], B = hh[1], C = hh[2], D = hh[3], E = hh[4], F = hh[5], G = hh[6], H = hh[7]
            
            // Main loop
            for j in 0..<k.count {
                let s0 = rotateRight(A,n: 28) ^ rotateRight(A,n: 34) ^ rotateRight(A,n: 39) //FIXME: n:
                let maj = (A & B) ^ (A & C) ^ (B & C)
                let t2 = s0 &+ maj
                let s1 = rotateRight(E,n: 14) ^ rotateRight(E,n: 18) ^ rotateRight(E,n: 41)
                let ch = (E & F) ^ ((~E) & G)
                let t1 = H &+ s1 &+ ch &+ k[j] &+ UInt64(M[j])
                
                H = G; G = F; F = E; E = D &+ t1
                D = C; C = B; B = A; A = t1 &+ t2
            }
            
            hh[0] = (hh[0] &+ A)
            hh[1] = (hh[1] &+ B)
            hh[2] = (hh[2] &+ C)
            hh[3] = (hh[3] &+ D)
            hh[4] = (hh[4] &+ E)
            hh[5] = (hh[5] &+ F)
            hh[6] = (hh[6] &+ G)
            hh[7] = (hh[7] &+ H)
        }
        
        // Produce the final hash value (big-endian)
        var result = [UInt8]()
        result.reserveCapacity(hh.count / 4)
        Self.resultingArray(hh).forEach {
            let item = $0.bigEndian
            var partialResult = [UInt8]()
            partialResult.reserveCapacity(8)
            for i in 0..<8 {
                let shift = UInt64(8 * i)
                partialResult.append(UInt8((item >> shift) & 0xff))
            }
            result += partialResult
        }
        return result
    }
    // codebeat:enable[ABC]
}

final class SHA256 : SHA2Variant32 {
    static let h: [UInt64] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    
    static func resultingArray<T>(_ hh: [T]) -> ArraySlice<T> {
        return ArraySlice(hh)
    }
}

final class SHA384 : SHA2Variant64 {
    static let h: [UInt64] = [0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939, 0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4]
    
    public static func resultingArray<T>(_ hh: [T]) -> ArraySlice<T> {
        return hh[0..<6]
    }
}

final class SHA512 : SHA2Variant64 {
    static let h: [UInt64] = [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179]
    
    static func resultingArray<T>(_ hh: [T]) -> ArraySlice<T> {
        return ArraySlice(hh)
    }
}

final class SHA2<Variant: SHA2Variant> {
    static var size: Int {
        return Variant.size
    }
    
    static func calculate(_ message: [UInt8]) -> [UInt8] {
        return Variant.calculate(message)
    }
}

final class HMAC<Variant: SHA2Variant> {
    public static func authenticate(message:[UInt8], withKey key: [UInt8]) -> [UInt8] {
        var key = key
        
        if (key.count > Variant.size) {
            key = Variant.calculate(key)
        }
        
        if (key.count < Variant.size) { // keys shorter than blocksize are zero-padded
            key = key + [UInt8](repeating: 0, count: Variant.size - key.count)
        }
        
        var opad = [UInt8](repeating: 0x5c, count: Variant.size)
        for (idx, _) in key.enumerated() {
            opad[idx] = key[idx] ^ opad[idx]
        }
        var ipad = [UInt8](repeating: 0x36, count: Variant.size)
        for (idx, _) in key.enumerated() {
            ipad[idx] = key[idx] ^ ipad[idx]
        }
        
        let ipadAndMessageHash = Variant.calculate(ipad + message)
        let finalHash = Variant.calculate(opad + ipadAndMessageHash);
        
        return finalHash
    }
    
    static func authenticate(message: String, withKey key: [UInt8]) -> [UInt8] {
        return authenticate(message: [UInt8](message.utf8), withKey: key)
    }
    
    static func authenticate(message: Data, withKey key: Data) -> Data {
        return Data(bytes: authenticate(message: Array(message), withKey: Array(key)))
    }
    
    static func authenticate(message: String, withKey key: Data) -> Data {
        return Data(bytes: authenticate(message: [UInt8](message.utf8), withKey: Array(key)))
    }
}

fileprivate struct BytesSequence: Sequence {
    let chunkSize: Int
    let data: [UInt8]
    
    init(chunkSize: Int, data: [UInt8]) {
        self.chunkSize = chunkSize
        self.data = data
    }
    
    func makeIterator() -> AnyIterator<ArraySlice<UInt8>> {
        var offset:Int = 0
        
        return AnyIterator {
            let end = Swift.min(self.chunkSize, self.data.count - offset)
            let result = self.data[offset..<offset + end]
            offset += result.count
            return result.count > 0 ? result : nil
        }
    }
}

fileprivate func rotateRight(_ x:UInt16, n:UInt16) -> UInt16 {
    return (x >> n) | (x << (16 - n))
}

fileprivate func rotateRight(_ x:UInt32, n:UInt32) -> UInt32 {
    return (x >> n) | (x << (32 - n))
}

fileprivate func rotateRight(_ x:UInt64, n:UInt64) -> UInt64 {
    return ((x >> n) | (x << (64 - n)))
}

fileprivate func toUInt32Array(_ slice: ArraySlice<UInt8>) -> Array<UInt32> {
    var result = Array<UInt32>()
    result.reserveCapacity(16)
    
    for idx in stride(from: slice.startIndex, to: slice.endIndex, by: MemoryLayout<UInt32>.size) {
        let val1:UInt32 = (UInt32(slice[idx.advanced(by: 3)]) << 24)
        let val2:UInt32 = (UInt32(slice[idx.advanced(by: 2)]) << 16)
        let val3:UInt32 = (UInt32(slice[idx.advanced(by: 1)]) << 8)
        let val4:UInt32 = UInt32(slice[idx])
        let val:UInt32 = val1 | val2 | val3 | val4
        result.append(val)
    }
    return result
}

fileprivate func toUInt64Array(_ slice: ArraySlice<UInt8>) -> Array<UInt64> {
    var result = Array<UInt64>()
    result.reserveCapacity(32)
    for idx in stride(from: slice.startIndex, to: slice.endIndex, by: MemoryLayout<UInt64>.size) {
        var val:UInt64 = 0
        val |= UInt64(slice[idx.advanced(by: 7)]) << 56
        val |= UInt64(slice[idx.advanced(by: 6)]) << 48
        val |= UInt64(slice[idx.advanced(by: 5)]) << 40
        val |= UInt64(slice[idx.advanced(by: 4)]) << 32
        val |= UInt64(slice[idx.advanced(by: 3)]) << 24
        val |= UInt64(slice[idx.advanced(by: 2)]) << 16
        val |= UInt64(slice[idx.advanced(by: 1)]) << 8
        val |= UInt64(slice[idx.advanced(by: 0)]) << 0
        result.append(val)
    }
    return result
}

fileprivate func arrayOfBytes<T>(_ value:T, length:Int? = nil) -> [UInt8] {
    let totalBytes = length ?? MemoryLayout<T>.size
    
    let valuePointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    
    valuePointer.pointee = value
    
    let bytesPointer = UnsafeMutableRawPointer(valuePointer).assumingMemoryBound(to: UInt8.self)
    var bytes = [UInt8](repeating: 0, count: totalBytes)
    for j in 0..<min(MemoryLayout<T>.size,totalBytes) {
        bytes[totalBytes - 1 - j] = (bytesPointer + j).pointee
    }
    
    valuePointer.deinitialize()
    valuePointer.deallocate(capacity: 1)
    
    return bytes
}

public extension String {
    public func fp_sha256() -> [UInt8] {
        return SHA2<SHA256>.calculate([UInt8](self.utf8))
    }
    
    public func fp_sha384() -> [UInt8] {
        return SHA2<SHA384>.calculate([UInt8](self.utf8))
    }
    
    public func fp_sha512() -> [UInt8] {
        return SHA2<SHA512>.calculate([UInt8](self.utf8))
    }
}

public extension Data {
    public func fp_sha256() -> [UInt8] {
        return SHA2<SHA256>.calculate(Array(self))
    }
    
    public func fp_sha384() -> [UInt8] {
        return SHA2<SHA384>.calculate(Array(self))
    }
    
    public func fp_sha512() -> [UInt8] {
        return SHA2<SHA512>.calculate(Array(self))
    }
}
