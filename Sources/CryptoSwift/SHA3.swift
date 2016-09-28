//
//  SHA3.swift
//  CryptoSwift
//
//  Created by Marcin Krzyzanowski on 23/09/16.
//  Copyright © 2016 Marcin Krzyzanowski. All rights reserved.
//
//  http://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.202.pdf
//  http://keccak.noekeon.org/specs_summary.html
//

#if os(Linux) || os(Android)
    import Glibc
#else
    import Darwin
#endif

public final class SHA3: DigestType {
    let round_constants: Array<UInt64> = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
                                          0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
                                          0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
                                          0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
                                          0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
                                          0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

    let variant: Variant

    fileprivate var accumulated = Array<UInt8>()
    fileprivate var accumulatedLength: Int = 0
    fileprivate var accumulatedHash:Array<UInt64>

    public enum Variant: RawRepresentable {
        case sha224, sha256, sha384, sha512

        public var digestLength:Int {
            return 100 - (self.blockSize / 2)
        }
        
        public var blockSize: Int {
            return (1600 - self.rawValue * 2) / 8
        }

        public typealias RawValue = Int
        public var rawValue: RawValue {
            switch self {
            case .sha224:
                return 224
            case .sha256:
                return 256
            case .sha384:
                return 384
            case .sha512:
                return 512
            }
        }
        
        public init?(rawValue: RawValue) {
            switch (rawValue) {
            case 224:
                self = .sha224
                break;
            case 256:
                self = .sha256
                break;
            case 384:
                self = .sha384
                break;
            case 512:
                self = .sha512
                break;
            default:
                return nil
            }
        }
    }

    public init(variant: SHA3.Variant) {
        self.variant = variant
        self.accumulatedHash = Array<UInt64>(repeating: 0, count: self.variant.digestLength)
    }

    ///  1. For all pairs (x,z) such that 0≤x<5 and 0≤z<w, let
    ///     C[x,z]=A[x, 0,z] ⊕ A[x, 1,z] ⊕ A[x, 2,z] ⊕ A[x, 3,z] ⊕ A[x, 4,z].
    ///  2. For all pairs (x, z) such that 0≤x<5 and 0≤z<w let
    ///     D[x,z]=C[(x1) mod 5, z] ⊕ C[(x+1) mod 5, (z –1) mod w].
    ///  3. For all triples (x, y, z) such that 0≤x<5, 0≤y<5, and 0≤z<w, let
    ///     A′[x, y,z] = A[x, y,z] ⊕ D[x,z].
    private func θ(_ a: inout Array<UInt64>) {
        var c = Array<UInt64>(repeating: 0, count: 5)
        var d = Array<UInt64>(repeating: 0, count: 5)

        for i in 0..<5 {
            c[i] = a[i] ^ a[i + 5] ^ a[i + 10] ^ a[i + 15] ^ a[i + 20]
        }

        d[0] = rotateLeft(c[1], by: 1) ^ c[4]
        d[1] = rotateLeft(c[2], by: 1) ^ c[0]
        d[2] = rotateLeft(c[3], by: 1) ^ c[1]
        d[3] = rotateLeft(c[4], by: 1) ^ c[2]
        d[4] = rotateLeft(c[0], by: 1) ^ c[3]

        for i in 0..<5 {
            a[i] ^= d[i]
            a[i + 5]  ^= d[i]
            a[i + 10] ^= d[i]
            a[i + 15] ^= d[i]
            a[i + 20] ^= d[i]
        }
    }

    /// A′[x, y, z]=A[(x + 3y) mod 5, x, z]
    private func π(_ a: inout Array<UInt64>) {
        let a1 = a[1]
        a[1] = a[6]
        a[6] = a[9]
        a[9] = a[22]
        a[22] = a[14]
        a[14] = a[20]
        a[20] = a[2]
        a[2] = a[12]
        a[12] = a[13]
        a[13] = a[19]
        a[19] = a[23]
        a[23] = a[15]
        a[15] = a[4]
        a[4] = a[24]
        a[24] = a[21]
        a[21] = a[8]
        a[8] = a[16]
        a[16] = a[5]
        a[5] = a[3]
        a[3] = a[18]
        a[18] = a[17]
        a[17] = a[11]
        a[11] = a[7]
        a[7] = a[10]
        a[10] = a1
    }

    /// For all triples (x, y, z) such that 0≤x<5, 0≤y<5, and 0≤z<w, let
    /// A′[x, y,z] = A[x, y,z] ⊕ ((A[(x+1) mod 5, y, z] ⊕ 1) ⋅ A[(x+2) mod 5, y, z])
    private func χ(_ a: inout Array<UInt64>) {
        for i in stride(from: 0, to: 25, by: 5) {
            let a0 = a[0 + i]
            let a1 = a[1 + i]
            a[0 + i] ^= ~a1 & a[2 + i]
            a[1 + i] ^= ~a[2 + i] & a[3 + i]
            a[2 + i] ^= ~a[3 + i] & a[4 + i]
            a[3 + i] ^= ~a[4 + i] & a0
            a[4 + i] ^= ~a0 & a1
        }
    }

    private func ι(_ a: inout Array<UInt64>, round: Int) {
        a[0] ^= round_constants[round]
    }

    fileprivate func process<C: Collection>(block chunk: C, currentHash hh: inout Array<UInt64>) where C.Iterator.Element == UInt64, C.Index == Int {
        // expand
        hh[0] ^= chunk[0].littleEndian
        hh[1] ^= chunk[1].littleEndian
        hh[2] ^= chunk[2].littleEndian
        hh[3] ^= chunk[3].littleEndian
        hh[4] ^= chunk[4].littleEndian
        hh[5] ^= chunk[5].littleEndian
        hh[6] ^= chunk[6].littleEndian
        hh[7] ^= chunk[7].littleEndian
        hh[8] ^= chunk[8].littleEndian
        if self.variant.blockSize > 72 { // 72 / 8, sha-512
            hh[9]  ^= chunk[9 ].littleEndian
            hh[10] ^= chunk[10].littleEndian
            hh[11] ^= chunk[11].littleEndian
            hh[12] ^= chunk[12].littleEndian
            if self.variant.blockSize > 104 { // 104 / 8, sha-384
                hh[13] ^= chunk[13].littleEndian
                hh[14] ^= chunk[14].littleEndian
                hh[15] ^= chunk[15].littleEndian
                hh[16] ^= chunk[16].littleEndian
                if self.variant.blockSize > 136 { // 136 / 8, sha-256
                    hh[17] ^= chunk[17].littleEndian
                    // FULL_SHA3_FAMILY_SUPPORT
                    if self.variant.blockSize > 144 { // 144 / 8, sha-224
                        hh[18] ^= chunk[18].littleEndian
                        hh[19] ^= chunk[19].littleEndian
                        hh[20] ^= chunk[20].littleEndian
                        hh[21] ^= chunk[21].littleEndian
                        hh[22] ^= chunk[22].littleEndian
                        hh[23] ^= chunk[23].littleEndian
                        hh[24] ^= chunk[24].littleEndian
                    }
                }
            }
        }

        // Keccak-f
        for round in 0..<24 {
            θ(&hh)

            hh[1] = rotateLeft(hh[1], by: 1)
            hh[2] = rotateLeft(hh[2], by: 62)
            hh[3] = rotateLeft(hh[3], by: 28)
            hh[4] = rotateLeft(hh[4], by: 27)
            hh[5] = rotateLeft(hh[5], by: 36)
            hh[6] = rotateLeft(hh[6], by: 44)
            hh[7] = rotateLeft(hh[7], by: 6)
            hh[8] = rotateLeft(hh[8], by: 55)
            hh[9] = rotateLeft(hh[9], by: 20)
            hh[10] = rotateLeft(hh[10], by: 3)
            hh[11] = rotateLeft(hh[11], by: 10)
            hh[12] = rotateLeft(hh[12], by: 43)
            hh[13] = rotateLeft(hh[13], by: 25)
            hh[14] = rotateLeft(hh[14], by: 39)
            hh[15] = rotateLeft(hh[15], by: 41)
            hh[16] = rotateLeft(hh[16], by: 45)
            hh[17] = rotateLeft(hh[17], by: 15)
            hh[18] = rotateLeft(hh[18], by: 21)
            hh[19] = rotateLeft(hh[19], by: 8)
            hh[20] = rotateLeft(hh[20], by: 18)
            hh[21] = rotateLeft(hh[21], by: 2)
            hh[22] = rotateLeft(hh[22], by: 61)
            hh[23] = rotateLeft(hh[23], by: 56)
            hh[24] = rotateLeft(hh[24], by: 14)

            π(&hh)
            χ(&hh)
            ι(&hh, round: round)
        }
    }

    func calculate(for bytes: Array<UInt8>) -> Array<UInt8> {
        do {
            return try self.update(withBytes: bytes, isLast: true)
        } catch {
            return []
        }
    }
}

extension SHA3: Updatable {
    public func update<T: Sequence>(withBytes bytes: T, isLast: Bool = false) throws -> Array<UInt8> where T.Iterator.Element == UInt8 {
        let prevAccumulatedLength = self.accumulated.count
        self.accumulated += bytes
        self.accumulatedLength += self.accumulated.count - prevAccumulatedLength //avoid Array(bytes).count

        if isLast {
            // Add padding
            if self.accumulated.count == 0 || self.accumulated.count % self.variant.blockSize != 0 {
                let r = self.variant.blockSize * 8
                let q = (r/8) - (self.accumulated.count % (r/8))
                self.accumulated += Array<UInt8>(repeating: 0, count: q)
            }

            self.accumulated[self.accumulatedLength] |= 0x06 // 0x1F for SHAKE
            self.accumulated[self.accumulated.count - 1] |= 0x80
        }

        for chunk in BytesSequence(chunkSize: self.variant.blockSize, data: self.accumulated) {
            if (isLast || self.accumulated.count >= self.variant.blockSize) {
                self.process(block: chunk.toUInt64Array(), currentHash: &self.accumulatedHash)
                self.accumulated.removeFirst(chunk.count)
            }
        }

        //TODO: verify performance, reduce vs for..in
        let result = self.accumulatedHash.reduce(Array<UInt8>()) { (result, value) -> Array<UInt8> in
            return result + arrayOfBytes(value: value.bigEndian)
        }

        // reset hash value for instance
        if isLast {
            self.accumulatedHash = Array<UInt64>(repeating: 0, count: self.variant.digestLength)
        }
        
        return Array(result[0..<self.variant.digestLength])
    }
}