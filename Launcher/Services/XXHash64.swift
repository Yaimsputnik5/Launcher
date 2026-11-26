import Foundation

/// Streaming-compatible XXH64 implementation matching HashDepot.XXHash.Hash64
/// used by the existing C# launcher. The one-shot entry point accepts a mapped
/// Data buffer so large client files are not copied into memory.
enum XXHash64 {
    private static let prime1: UInt64 = 11400714785074694791
    private static let prime2: UInt64 = 14029467366897019727
    private static let prime3: UInt64 = 1609587929392839161
    private static let prime4: UInt64 = 9650029242287828579
    private static let prime5: UInt64 = 2870177450012600261

    static func hash(_ data: Data, seed: UInt64 = 0) -> UInt64 {
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return hash(bytes, seed: seed)
        }
    }

    private static func hash(_ bytes: UnsafeBufferPointer<UInt8>, seed: UInt64) -> UInt64 {
        let count = bytes.count
        var index = 0
        var h: UInt64

        if count >= 32 {
            var v1 = seed &+ prime1 &+ prime2
            var v2 = seed &+ prime2
            var v3 = seed
            var v4 = seed &- prime1

            while index + 32 <= count {
                v1 = round(v1, read64(bytes, index))
                v2 = round(v2, read64(bytes, index + 8))
                v3 = round(v3, read64(bytes, index + 16))
                v4 = round(v4, read64(bytes, index + 24))
                index += 32
            }

            h = rotateLeft(v1, 1)
                &+ rotateLeft(v2, 7)
                &+ rotateLeft(v3, 12)
                &+ rotateLeft(v4, 18)
            h = mergeRound(h, v1)
            h = mergeRound(h, v2)
            h = mergeRound(h, v3)
            h = mergeRound(h, v4)
        } else {
            h = seed &+ prime5
        }

        h &+= UInt64(count)

        while index + 8 <= count {
            let value = round(0, read64(bytes, index))
            h ^= value
            h = rotateLeft(h, 27) &* prime1 &+ prime4
            index += 8
        }

        if index + 4 <= count {
            h ^= read32(bytes, index) &* prime1
            h = rotateLeft(h, 23) &* prime2 &+ prime3
            index += 4
        }

        while index < count {
            h ^= UInt64(bytes[index]) &* prime5
            h = rotateLeft(h, 11) &* prime1
            index += 1
        }

        h ^= h >> 33
        h &*= prime2
        h ^= h >> 29
        h &*= prime3
        h ^= h >> 32
        return h
    }

    private static func round(_ accumulator: UInt64, _ input: UInt64) -> UInt64 {
        rotateLeft(accumulator &+ input &* prime2, 31) &* prime1
    }

    private static func mergeRound(_ accumulator: UInt64, _ value: UInt64) -> UInt64 {
        let merged = accumulator ^ round(0, value)
        return merged &* prime1 &+ prime4
    }

    private static func rotateLeft(_ value: UInt64, _ amount: UInt64) -> UInt64 {
        (value << amount) | (value >> (64 - amount))
    }

    private static func read32(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<4 {
            value |= UInt64(bytes[offset + index]) << (8 * index)
        }
        return value
    }

    private static func read64(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << (8 * index)
        }
        return value
    }
}
