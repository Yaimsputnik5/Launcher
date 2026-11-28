import Foundation

/// portable image decoding for original client textures.
///
/// Only Foundation is used. Decoders produce top-left-origin RGBA8 byte buffers
/// and never create platform images; the SwiftUI/Metal layer can convert the
/// result later. PNG files are passed through as `pngData` for platform decode.
public enum ImageCodecError: Error, LocalizedError, Equatable {
    case truncated(field: String, expected: Int, available: Int)
    case invalidMagic(String)
    case invalidHeader(String)
    case invalidDimensions(width: Int, height: Int)
    case decodedSizeLimitExceeded(bytes: Int, limit: Int)
    case unsupportedTGAType(UInt8)
    case unsupportedBitsPerPixel(UInt8)
    case unsupportedColorMap
    case invalidTGADescriptor(UInt8)
    case invalidTGARLE(String)
    case unsupportedDDSFourCC(String)
    case unsupportedDDSFormat(String)
    case invalidDDSMask(String)
    case malformedPNG(String)
    case resourceNotFound(String)
    case compressedRCCResource(String)
    case ambiguousFormat(String)

    public var errorDescription: String? {
        switch self {
        case .truncated(let field, let expected, let available):
            return "Truncated \(field): needed \(expected) byte(s), \(available) available."
        case .invalidMagic(let format):
            return "Not a \(format) image (magic mismatch)."
        case .invalidHeader(let detail):
            return "Invalid image header: \(detail)."
        case .invalidDimensions(let width, let height):
            return "Invalid image dimensions \(width)x\(height)."
        case .decodedSizeLimitExceeded(let bytes, let limit):
            return "Decoded image would be \(bytes) bytes, above the \(limit)-byte limit."
        case .unsupportedTGAType(let type):
            return String(format: "Unsupported TGA image type 0x%02X.", type)
        case .unsupportedBitsPerPixel(let bpp):
            return "Unsupported image bit depth \(bpp)."
        case .unsupportedColorMap:
            return "Color-mapped TGA images are not supported."
        case .invalidTGADescriptor(let descriptor):
            return String(format: "Invalid TGA image descriptor 0x%02X.", descriptor)
        case .invalidTGARLE(let detail):
            return "Invalid TGA RLE data: \(detail)."
        case .unsupportedDDSFourCC(let fourCC):
            return "Unsupported DDS compression format '\(fourCC)'."
        case .unsupportedDDSFormat(let detail):
            return "Unsupported DDS pixel format: \(detail)."
        case .invalidDDSMask(let detail):
            return "Invalid DDS channel mask: \(detail)."
        case .malformedPNG(let detail):
            return "Malformed PNG container: \(detail)."
        case .resourceNotFound(let path):
            return "Texture resource not found: \(path)."
        case .compressedRCCResource(let path):
            return "Compressed RCC texture '\(path)' needs a zlib decompressor."
        case .ambiguousFormat(let name):
            return "Cannot determine texture format for '\(name)'."
        }
    }
}

/// A decoded texture in portable top-left-origin RGBA8 form.
///
/// For PNG passthrough, `pixels` is empty and `pngData` contains the original
/// bytes; the UI layer should decode `pngData` with the platform image API.
public struct DecodedImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: Data
    public let pngData: Data?

    init(width: Int, height: Int, pixels: Data, pngData: Data? = nil) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.pngData = pngData
    }

    /// Number of bytes in the RGBA8 buffer (zero for PNG passthrough).
    public var byteCount: Int { pixels.count }

    /// True when this result carries PNG bytes instead of decoded pixels.
    public var isPNGPassthrough: Bool { pngData != nil }
}

// MARK: - Shared bounds-checked byte access

private enum CodecLimits {
    static let maxDecodedBytes = 64 * 1024 * 1024
}

private func checkedMultiply(_ a: Int, _ b: Int, field: String) throws -> Int {
    let (value, overflow) = a.multipliedReportingOverflow(by: b)
    guard !overflow, value >= 0 else {
        throw ImageCodecError.decodedSizeLimitExceeded(bytes: Int.max, limit: CodecLimits.maxDecodedBytes)
    }
    return value
}

private func checkedPixelBytes(width: Int, height: Int) throws -> Int {
    guard width > 0, height > 0 else {
        throw ImageCodecError.invalidDimensions(width: width, height: height)
    }
    let bytes = try checkedMultiply(width, height, field: "image pixels")
    let rgba = try checkedMultiply(bytes, 4, field: "RGBA image")
    guard rgba <= CodecLimits.maxDecodedBytes else {
        throw ImageCodecError.decodedSizeLimitExceeded(bytes: rgba, limit: CodecLimits.maxDecodedBytes)
    }
    return rgba
}

private struct ByteReader {
    let bytes: [UInt8]

    var count: Int { bytes.count }

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    func range(offset: Int, length: Int, field: String) throws -> Range<Int> {
        guard offset >= 0, length >= 0 else {
            throw ImageCodecError.truncated(field: field, expected: length, available: 0)
        }
        let (end, overflow) = offset.addingReportingOverflow(length)
        guard !overflow, end <= bytes.count else {
            let available = offset <= bytes.count ? bytes.count - offset : 0
            throw ImageCodecError.truncated(field: field, expected: length, available: available)
        }
        return offset..<end
    }

    func byte(at offset: Int, field: String) throws -> UInt8 {
        _ = try range(offset: offset, length: 1, field: field)
        return bytes[offset]
    }

    func u16LE(at offset: Int, field: String) throws -> UInt16 {
        let range = try self.range(offset: offset, length: 2, field: field)
        return UInt16(bytes[range.lowerBound]) | (UInt16(bytes[range.lowerBound + 1]) << 8)
    }

    func u32LE(at offset: Int, field: String) throws -> UInt32 {
        let range = try self.range(offset: offset, length: 4, field: field)
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(bytes[range.lowerBound + index]) << UInt32(index * 8)
        }
        return value
    }

    func u32BE(at offset: Int, field: String) throws -> UInt32 {
        let range = try self.range(offset: offset, length: 4, field: field)
        var value: UInt32 = 0
        for index in 0..<4 {
            value = (value << 8) | UInt32(bytes[range.lowerBound + index])
        }
        return value
    }

    func fourCC(at offset: Int, field: String) throws -> String {
        let range = try self.range(offset: offset, length: 4, field: field)
        let chars = range.map { bytes[$0] }
        return String(decoding: chars, as: UTF8.self)
    }
}

private struct RGBA8 {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

private func scaledChannel(_ value: UInt32, maxValue: UInt32) -> UInt8 {
    guard maxValue > 0 else { return 0 }
    let wideValue = UInt64(value)
    let wideMax = UInt64(maxValue)
    let scaled = (wideValue * 255 + wideMax / 2) / wideMax
    return UInt8(min(scaled, 255))
}

private func channel(from raw: UInt32, mask: UInt32) -> UInt8 {
    guard mask != 0 else { return 0 }
    let shift = UInt32(mask.trailingZeroBitCount)
    let field = (raw & mask) >> shift
    return scaledChannel(field, maxValue: mask >> shift)
}

// MARK: - TGA

/// Decoder for uncompressed and RLE true-color/grayscale TGA images.
///
/// Handles 8/16-bit grayscale and 16/24/32-bit true-color, including the
/// bottom-left origin used by the client's UI TGAs and the top-left origin.
public enum TGADecoder {
    private enum ImageType {
        static let grayscale: UInt8 = 3
        static let trueColor: UInt8 = 2
        static let rleGrayscale: UInt8 = 11
        static let rleTrueColor: UInt8 = 10
    }

    public static func decode(data: Data) throws -> DecodedImage {
        let reader = ByteReader(data)
        guard reader.count >= 18 else {
            throw ImageCodecError.truncated(field: "TGA header", expected: 18, available: reader.count)
        }

        let idLength = Int(try reader.byte(at: 0, field: "TGA ID length"))
        let colorMapType = try reader.byte(at: 1, field: "TGA color map type")
        let imageType = try reader.byte(at: 2, field: "TGA image type")
        let colorMapLength = try reader.u16LE(at: 5, field: "TGA color map length")
        let width = Int(try reader.u16LE(at: 12, field: "TGA width"))
        let height = Int(try reader.u16LE(at: 14, field: "TGA height"))
        let bpp = try reader.byte(at: 16, field: "TGA pixel depth")
        let descriptor = try reader.byte(at: 17, field: "TGA descriptor")

        guard colorMapType == 0, colorMapLength == 0 else {
            throw ImageCodecError.unsupportedColorMap
        }
        guard imageType == ImageType.trueColor || imageType == ImageType.rleTrueColor ||
              imageType == ImageType.grayscale || imageType == ImageType.rleGrayscale
        else {
            throw ImageCodecError.unsupportedTGAType(imageType)
        }

        let isGrayscale = imageType == ImageType.grayscale || imageType == ImageType.rleGrayscale
        let isRLE = imageType == ImageType.rleTrueColor || imageType == ImageType.rleGrayscale
        let validBPP: [UInt8] = isGrayscale ? [8, 16] : [16, 24, 32]
        guard validBPP.contains(bpp) else {
            throw ImageCodecError.unsupportedBitsPerPixel(bpp)
        }
        guard (descriptor & 0x0F) <= 8 else {
            throw ImageCodecError.invalidTGADescriptor(descriptor)
        }

        let pixelCount = try checkedPixelBytes(width: width, height: height)
        let pixelSize = Int(bpp) / 8
        var cursor = 18 + idLength
        guard cursor <= reader.count else {
            throw ImageCodecError.truncated(field: "TGA image ID", expected: idLength, available: reader.count - 18)
        }

        let alphaBits = descriptor & 0x0F
        let topOrigin = (descriptor & 0x20) != 0
        let rightToLeft = (descriptor & 0x10) != 0
        var pixels = [UInt8](repeating: 0, count: pixelCount)

        func write(_ pixel: RGBA8, at sourceIndex: Int) {
            let sourceRow = sourceIndex / width
            let sourceColumn = sourceIndex % width
            let destinationRow = topOrigin ? sourceRow : height - 1 - sourceRow
            let destinationColumn = rightToLeft ? width - 1 - sourceColumn : sourceColumn
            let offset = (destinationRow * width + destinationColumn) * 4
            pixels[offset] = pixel.r
            pixels[offset + 1] = pixel.g
            pixels[offset + 2] = pixel.b
            pixels[offset + 3] = pixel.a
        }

        func readPixel() throws -> RGBA8 {
            let range = try reader.range(offset: cursor, length: pixelSize, field: "TGA pixel")
            cursor = range.upperBound
            switch bpp {
            case 8:
                let gray = bytesValue(reader.bytes, range.lowerBound, 1)
                return RGBA8(r: UInt8(truncatingIfNeeded: gray),
                             g: UInt8(truncatingIfNeeded: gray),
                             b: UInt8(truncatingIfNeeded: gray), a: 255)
            case 16:
                let value = UInt16(reader.bytes[range.lowerBound]) |
                    (UInt16(reader.bytes[range.lowerBound + 1]) << 8)
                if isGrayscale {
                    return RGBA8(r: UInt8(truncatingIfNeeded: value & 0xFF),
                                 g: UInt8(truncatingIfNeeded: value & 0xFF),
                                 b: UInt8(truncatingIfNeeded: value & 0xFF),
                                 a: UInt8(truncatingIfNeeded: value >> 8))
                }
                if alphaBits == 4 {
                    return RGBA8(
                        r: UInt8(truncatingIfNeeded: (value >> 12) & 0x0F) * 17,
                        g: UInt8(truncatingIfNeeded: (value >> 8) & 0x0F) * 17,
                        b: UInt8(truncatingIfNeeded: (value >> 4) & 0x0F) * 17,
                        a: UInt8(truncatingIfNeeded: value & 0x0F) * 17
                    )
                }
                let red5 = (value >> 10) & 0x1F
                let green5 = (value >> 5) & 0x1F
                let blue5 = value & 0x1F
                let alpha: UInt8 = alphaBits == 1
                    ? ((value & 0x8000) != 0 ? 255 : 0)
                    : 255
                return RGBA8(
                    r: UInt8(scaledChannel(UInt32(red5), maxValue: 31)),
                    g: UInt8(scaledChannel(UInt32(green5), maxValue: 31)),
                    b: UInt8(scaledChannel(UInt32(blue5), maxValue: 31)),
                    a: alpha
                )
            case 24:
                return RGBA8(
                    r: reader.bytes[range.lowerBound + 2],
                    g: reader.bytes[range.lowerBound + 1],
                    b: reader.bytes[range.lowerBound],
                    a: 255
                )
            default:
                return RGBA8(
                    r: reader.bytes[range.lowerBound + 2],
                    g: reader.bytes[range.lowerBound + 1],
                    b: reader.bytes[range.lowerBound],
                    a: reader.bytes[range.lowerBound + 3]
                )
            }
        }

        let totalPixels = pixelCount / 4
        if isRLE {
            var produced = 0
            while produced < totalPixels {
                let packet = try reader.byte(at: cursor, field: "TGA RLE packet")
                cursor += 1
                let runLength = Int(packet & 0x7F) + 1
                guard runLength <= totalPixels - produced else {
                    throw ImageCodecError.invalidTGARLE("run of \(runLength) pixels exceeds image bounds")
                }
                if (packet & 0x80) != 0 {
                    let pixel = try readPixel()
                    for _ in 0..<runLength {
                        write(pixel, at: produced)
                        produced += 1
                    }
                } else {
                    for _ in 0..<runLength {
                        write(try readPixel(), at: produced)
                        produced += 1
                    }
                }
            }
        } else {
            let required = try checkedMultiply(totalPixels, pixelSize, field: "TGA pixel data")
            _ = try reader.range(offset: cursor, length: required, field: "TGA pixel data")
            for index in 0..<totalPixels {
                write(try readPixel(), at: index)
            }
        }

        return DecodedImage(width: width, height: height, pixels: Data(pixels))
    }
}

private func bytesValue(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> UInt32 {
    var value: UInt32 = 0
    for index in 0..<count {
        value |= UInt32(bytes[offset + index]) << UInt32(index * 8)
    }
    return value
}

// MARK: - DDS

/// Decoder for DirectDraw Surface textures used by the original client.
///
/// Supports DXT1/BC1, DXT3/BC2, DXT5/BC3, uncompressed RGB(A) at 16/24/32 bpp,
/// and simple 8/16-bit luminance maps. Only the top mip level is returned.
public enum DDSDecoder {
    private enum PixelFormatFlags {
        static let alphaPixels: UInt32 = 0x1
        static let fourCC: UInt32 = 0x4
        static let rgb: UInt32 = 0x40
        static let luminance: UInt32 = 0x2_0000
    }

    public static func decode(data: Data) throws -> DecodedImage {
        let reader = ByteReader(data)
        guard reader.count >= 128 else {
            throw ImageCodecError.truncated(field: "DDS header", expected: 128, available: reader.count)
        }
        guard try reader.fourCC(at: 0, field: "DDS magic") == "DDS " else {
            throw ImageCodecError.invalidMagic("DDS")
        }

        let headerSize = Int(try reader.u32LE(at: 4, field: "DDS header size"))
        guard headerSize >= 124 else {
            throw ImageCodecError.invalidHeader("DDS header size \(headerSize)")
        }
        let payloadOffset = 4 + headerSize
        guard payloadOffset <= reader.count else {
            throw ImageCodecError.truncated(field: "DDS header", expected: payloadOffset, available: reader.count)
        }

        guard let width = Int(exactly: try reader.u32LE(at: 16, field: "DDS width")),
              let height = Int(exactly: try reader.u32LE(at: 12, field: "DDS height"))
        else {
            throw ImageCodecError.invalidHeader("DDS dimensions are too large")
        }
        _ = try checkedPixelBytes(width: width, height: height)

        let pfSize = Int(try reader.u32LE(at: 76, field: "DDS pixel format size"))
        guard pfSize >= 32 else {
            throw ImageCodecError.invalidHeader("DDS pixel format size \(pfSize)")
        }
        let pfFlags = try reader.u32LE(at: 80, field: "DDS pixel format flags")
        let fourCC = try reader.fourCC(at: 84, field: "DDS fourCC")
        let bitCount = Int(try reader.u32LE(at: 88, field: "DDS bit count"))
        let redMask = try reader.u32LE(at: 92, field: "DDS red mask")
        let greenMask = try reader.u32LE(at: 96, field: "DDS green mask")
        let blueMask = try reader.u32LE(at: 100, field: "DDS blue mask")
        let alphaMask = try reader.u32LE(at: 104, field: "DDS alpha mask")

        switch fourCC {
        case "DXT1":
            return try decodeBC1(
                reader: reader, payloadOffset: payloadOffset, width: width, height: height
            )
        case "DXT3":
            return try decodeBC2(
                reader: reader, payloadOffset: payloadOffset, width: width, height: height
            )
        case "DXT5":
            return try decodeBC3(
                reader: reader, payloadOffset: payloadOffset, width: width, height: height
            )
        case "DX10":
            throw ImageCodecError.unsupportedDDSFourCC("DX10 (DXGI formats are not decoded)")
        default:
            break
        }

        if (pfFlags & PixelFormatFlags.fourCC) != 0 {
            throw ImageCodecError.unsupportedDDSFourCC(fourCC.isEmpty ? "(empty)" : fourCC)
        }
        if (pfFlags & PixelFormatFlags.luminance) != 0 {
            return try decodeLuminance(
                reader: reader, payloadOffset: payloadOffset, width: width, height: height,
                bitCount: bitCount, pfFlags: pfFlags, pitch: Int(try reader.u32LE(at: 20, field: "DDS pitch")),
                luminanceMask: redMask, alphaMask: alphaMask
            )
        }
        guard (pfFlags & PixelFormatFlags.rgb) != 0 else {
            throw ImageCodecError.unsupportedDDSFormat(
                "pixel format flags 0x\(String(pfFlags, radix: 16)) with fourCC '\(fourCC)'"
            )
        }
        return try decodeRGB(
            reader: reader, payloadOffset: payloadOffset, width: width, height: height,
            bitCount: bitCount, pfFlags: pfFlags,
            pitch: Int(try reader.u32LE(at: 20, field: "DDS pitch")),
            redMask: redMask, greenMask: greenMask, blueMask: blueMask, alphaMask: alphaMask
        )
    }

    private static func blockDimensions(width: Int, height: Int) throws -> (blocksWide: Int, blocksHigh: Int) {
        let blocksWide = try checkedMultiply(width + 3, 1, field: "DDS block width") / 4
        let blocksHigh = try checkedMultiply(height + 3, 1, field: "DDS block height") / 4
        return (blocksWide, blocksHigh)
    }

    private static func makePixels(width: Int, height: Int) throws -> [UInt8] {
        let count = try checkedPixelBytes(width: width, height: height)
        return [UInt8](repeating: 0, count: count)
    }

    private static func write(
        _ pixel: RGBA8, x: Int, y: Int, width: Int, height: Int, into pixels: inout [UInt8]
    ) throws {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = (y * width + x) * 4
        pixels[offset] = pixel.r
        pixels[offset + 1] = pixel.g
        pixels[offset + 2] = pixel.b
        pixels[offset + 3] = pixel.a
    }

    private static func expand565(_ value: UInt16) -> RGBA8 {
        RGBA8(
            r: scaledChannel(UInt32((value >> 11) & 0x1F), maxValue: 31),
            g: scaledChannel(UInt32((value >> 5) & 0x3F), maxValue: 63),
            b: scaledChannel(UInt32(value & 0x1F), maxValue: 31),
            a: 255
        )
    }

    private static func bc1Colors(
        _ reader: ByteReader, blockOffset: Int, forceFourColor: Bool = false
    ) throws -> [RGBA8] {
        let color0 = try reader.u16LE(at: blockOffset, field: "BC1 color 0")
        let color1 = try reader.u16LE(at: blockOffset + 2, field: "BC1 color 1")
        let first = expand565(color0)
        let second = expand565(color1)
        // BC2 and BC3 always interpolate four colors; only BC1 has the
        // c0 <= c1 three-color mode with a transparent fourth entry.
        if color0 > color1 || forceFourColor {
            let third = RGBA8(
                r: UInt8((UInt16(first.r) * 2 + UInt16(second.r)) / 3),
                g: UInt8((UInt16(first.g) * 2 + UInt16(second.g)) / 3),
                b: UInt8((UInt16(first.b) * 2 + UInt16(second.b)) / 3),
                a: 255
            )
            let fourth = RGBA8(
                r: UInt8((UInt16(first.r) + UInt16(second.r) * 2) / 3),
                g: UInt8((UInt16(first.g) + UInt16(second.g) * 2) / 3),
                b: UInt8((UInt16(first.b) + UInt16(second.b) * 2) / 3),
                a: 255
            )
            return [first, second, third, fourth]
        }
        let midpoint = RGBA8(
            r: UInt8((UInt16(first.r) + UInt16(second.r)) / 2),
            g: UInt8((UInt16(first.g) + UInt16(second.g)) / 2),
            b: UInt8((UInt16(first.b) + UInt16(second.b)) / 2),
            a: 255
        )
        return [first, second, midpoint, RGBA8(r: 0, g: 0, b: 0, a: 0)]
    }

    private static func colorIndices(_ reader: ByteReader, blockOffset: Int) throws -> UInt32 {
        try reader.u32LE(at: blockOffset + 4, field: "BC1 color indices")
    }

    private static func decodeBC1(
        reader: ByteReader, payloadOffset: Int, width: Int, height: Int
    ) throws -> DecodedImage {
        let dimensions = try blockDimensions(width: width, height: height)
        let required = try checkedMultiply(dimensions.blocksWide * dimensions.blocksHigh, 8, field: "DXT1 data")
        guard payloadOffset <= reader.count, required <= reader.count - payloadOffset else {
            throw ImageCodecError.truncated(
                field: "DXT1 blocks", expected: required, available: reader.count - payloadOffset
            )
        }

        var pixels = try makePixels(width: width, height: height)
        for blockY in 0..<dimensions.blocksHigh {
            for blockX in 0..<dimensions.blocksWide {
                let offset = payloadOffset + (blockY * dimensions.blocksWide + blockX) * 8
                let colors = try bc1Colors(reader, blockOffset: offset)
                let indices = try colorIndices(reader, blockOffset: offset)
                for pixelY in 0..<4 {
                    for pixelX in 0..<4 {
                        let index = Int((indices >> UInt32((pixelY * 4 + pixelX) * 2)) & 0x3)
                        try write(
                            colors[index], x: blockX * 4 + pixelX, y: blockY * 4 + pixelY,
                            width: width, height: height, into: &pixels
                        )
                    }
                }
            }
        }
        return DecodedImage(width: width, height: height, pixels: Data(pixels))
    }

    private static func dxt3Alpha(_ reader: ByteReader, blockOffset: Int, pixelX: Int, pixelY: Int) throws -> UInt8 {
        let byte = try reader.byte(at: blockOffset + pixelY * 2 + pixelX / 2, field: "DXT3 alpha")
        let nibble = pixelX % 2 == 0 ? byte & 0x0F : byte >> 4
        return nibble * 17
    }

    private static func decodeBC2(
        reader: ByteReader, payloadOffset: Int, width: Int, height: Int
    ) throws -> DecodedImage {
        let dimensions = try blockDimensions(width: width, height: height)
        let required = try checkedMultiply(dimensions.blocksWide * dimensions.blocksHigh, 16, field: "DXT3 data")
        guard payloadOffset <= reader.count, required <= reader.count - payloadOffset else {
            throw ImageCodecError.truncated(
                field: "DXT3 blocks", expected: required, available: reader.count - payloadOffset
            )
        }

        var pixels = try makePixels(width: width, height: height)
        for blockY in 0..<dimensions.blocksHigh {
            for blockX in 0..<dimensions.blocksWide {
                let offset = payloadOffset + (blockY * dimensions.blocksWide + blockX) * 16
                let colors = try bc1Colors(reader, blockOffset: offset + 8, forceFourColor: true)
                let indices = try colorIndices(reader, blockOffset: offset + 8)
                for pixelY in 0..<4 {
                    for pixelX in 0..<4 {
                        let index = Int((indices >> UInt32((pixelY * 4 + pixelX) * 2)) & 0x3)
                        let base = colors[index]
                        let alpha = try dxt3Alpha(
                            reader, blockOffset: offset, pixelX: pixelX, pixelY: pixelY
                        )
                        let color = RGBA8(r: base.r, g: base.g, b: base.b, a: alpha)
                        try write(
                            color, x: blockX * 4 + pixelX, y: blockY * 4 + pixelY,
                            width: width, height: height, into: &pixels
                        )
                    }
                }
            }
        }
        return DecodedImage(width: width, height: height, pixels: Data(pixels))
    }

    private static func dxt5Alphas(_ reader: ByteReader, blockOffset: Int) throws -> [UInt8] {
        let alpha0 = try reader.byte(at: blockOffset, field: "DXT5 alpha 0")
        let alpha1 = try reader.byte(at: blockOffset + 1, field: "DXT5 alpha 1")
        if alpha0 > alpha1 {
            // Indices 6 and 7 are undefined in the BC3 spec; use the same
            // 0/255 fallback as the <= branch so real streams remain decodable.
            return [
                alpha0, alpha1,
                UInt8((Int(alpha0) * 4 + Int(alpha1)) / 5),
                UInt8((Int(alpha0) * 3 + Int(alpha1) * 2) / 5),
                UInt8((Int(alpha0) * 2 + Int(alpha1) * 3) / 5),
                UInt8((Int(alpha0) + Int(alpha1) * 4) / 5),
                0, 255
            ]
        }
        return [
            alpha0, alpha1,
            UInt8((Int(alpha0) * 2 + Int(alpha1)) / 3),
            UInt8((Int(alpha0) + Int(alpha1) * 2) / 3),
            0, 255,
            0, 255
        ]
    }

    private static func dxt5AlphaIndex(_ reader: ByteReader, blockOffset: Int, pixel: Int) throws -> Int {
        let bitOffset = pixel * 3
        let byteOffset = blockOffset + 2 + bitOffset / 8
        let low = try reader.byte(at: byteOffset, field: "DXT5 alpha index")
        let high = try reader.byte(at: byteOffset + 1, field: "DXT5 alpha index")
        let bits = UInt16(low) | (UInt16(high) << 8)
        return Int((bits >> UInt16(bitOffset % 8)) & 0x7)
    }

    private static func decodeBC3(
        reader: ByteReader, payloadOffset: Int, width: Int, height: Int
    ) throws -> DecodedImage {
        let dimensions = try blockDimensions(width: width, height: height)
        let required = try checkedMultiply(dimensions.blocksWide * dimensions.blocksHigh, 16, field: "DXT5 data")
        guard payloadOffset <= reader.count, required <= reader.count - payloadOffset else {
            throw ImageCodecError.truncated(
                field: "DXT5 blocks", expected: required, available: reader.count - payloadOffset
            )
        }

        var pixels = try makePixels(width: width, height: height)
        for blockY in 0..<dimensions.blocksHigh {
            for blockX in 0..<dimensions.blocksWide {
                let offset = payloadOffset + (blockY * dimensions.blocksWide + blockX) * 16
                let colors = try bc1Colors(reader, blockOffset: offset + 8, forceFourColor: true)
                let alphas = try dxt5Alphas(reader, blockOffset: offset)
                let indices = try colorIndices(reader, blockOffset: offset + 8)
                for pixelY in 0..<4 {
                    for pixelX in 0..<4 {
                        let pixel = pixelY * 4 + pixelX
                        let alphaIndex = try dxt5AlphaIndex(reader, blockOffset: offset, pixel: pixel)
                        guard alphaIndex < alphas.count else {
                            throw ImageCodecError.invalidHeader("DXT5 alpha index \(alphaIndex) is out of range")
                        }
                        let base = colors[Int((indices >> UInt32(pixel * 2)) & 0x3)]
                        let color = RGBA8(r: base.r, g: base.g, b: base.b, a: alphas[alphaIndex])
                        try write(
                            color, x: blockX * 4 + pixelX, y: blockY * 4 + pixelY,
                            width: width, height: height, into: &pixels
                        )
                    }
                }
            }
        }
        return DecodedImage(width: width, height: height, pixels: Data(pixels))
    }

    private static func validateMasks(_ masks: [UInt32], bitCount: Int, field: String) throws {
        let fullMask: UInt32 = bitCount == 32 ? 0xFFFF_FFFF : ((UInt32(1) << UInt32(bitCount)) - 1)
        for mask in masks where mask != 0 && (mask & ~fullMask) != 0 {
            throw ImageCodecError.invalidDDSMask("\(field) mask exceeds \(bitCount) bits")
        }
        for index in 0..<masks.count {
            for other in (index + 1)..<masks.count where masks[index] != 0 && masks[other] != 0 {
                guard masks[index] & masks[other] == 0 else {
                    throw ImageCodecError.invalidDDSMask("\(field) channel masks overlap")
                }
            }
        }
    }

    private static func rowStride(
        pitch: Int, width: Int, height: Int, bytesPerPixel: Int,
        availableBytes: Int, field: String
    ) throws -> Int {
        let minimum = try checkedMultiply(width, bytesPerPixel, field: field)
        let candidate = pitch > 0 ? pitch : minimum
        guard candidate >= minimum else {
            throw ImageCodecError.invalidHeader("DDS pitch \(candidate) is smaller than row width \(minimum)")
        }
        // Some client writers put the whole linear size in dwPitchOrLinearSize.
        // Use the declared pitch only when the file really contains those rows;
        // otherwise read tightly packed rows, which is how these files store data.
        let paddedBytes = try checkedMultiply(candidate, height, field: field)
        let tightBytes = try checkedMultiply(minimum, height, field: field)
        guard tightBytes <= availableBytes else {
            throw ImageCodecError.truncated(
                field: field, expected: tightBytes, available: availableBytes
            )
        }
        return paddedBytes <= availableBytes ? candidate : minimum
    }

    private static func decodeRGB(
        reader: ByteReader, payloadOffset: Int, width: Int, height: Int,
        bitCount: Int, pfFlags: UInt32, pitch: Int,
        redMask: UInt32, greenMask: UInt32, blueMask: UInt32, alphaMask: UInt32
    ) throws -> DecodedImage {
        guard bitCount == 16 || bitCount == 24 || bitCount == 32 else {
            throw ImageCodecError.unsupportedBitsPerPixel(UInt8(truncatingIfNeeded: bitCount))
        }
        let masks = [redMask, greenMask, blueMask, alphaMask]
        try validateMasks(masks, bitCount: bitCount, field: "RGB")
        guard redMask != 0, greenMask != 0, blueMask != 0 else {
            throw ImageCodecError.invalidDDSMask("RGB channels need red, green, and blue masks")
        }

        let bytesPerPixel = bitCount / 8
        guard payloadOffset <= reader.count else {
            throw ImageCodecError.truncated(
                field: "DDS RGB pixels", expected: payloadOffset, available: reader.count
            )
        }
        let available = reader.count - payloadOffset
        let stride = try rowStride(
            pitch: pitch, width: width, height: height, bytesPerPixel: bytesPerPixel,
            availableBytes: available, field: "DDS RGB data"
        )
        let dataBytes = try checkedMultiply(stride, height, field: "DDS RGB data")
        guard dataBytes <= available else {
            throw ImageCodecError.truncated(
                field: "DDS RGB pixels", expected: dataBytes, available: available
            )
        }

        let usesAlpha = (pfFlags & PixelFormatFlags.alphaPixels) != 0 || alphaMask != 0
        var pixels = try makePixels(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = payloadOffset + y * stride + x * bytesPerPixel
                let raw = bytesValue(reader.bytes, offset, bytesPerPixel)
                let color = RGBA8(
                    r: channel(from: raw, mask: redMask),
                    g: channel(from: raw, mask: greenMask),
                    b: channel(from: raw, mask: blueMask),
                    a: usesAlpha ? channel(from: raw, mask: alphaMask) : 255
                )
                try write(color, x: x, y: y, width: width, height: height, into: &pixels)
            }
        }
        return DecodedImage(width: width, height: height, pixels: Data(pixels))
    }

    private static func decodeLuminance(
        reader: ByteReader, payloadOffset: Int, width: Int, height: Int,
        bitCount: Int, pfFlags: UInt32, pitch: Int,
        luminanceMask: UInt32, alphaMask: UInt32
    ) throws -> DecodedImage {
        guard bitCount == 8 || bitCount == 16 else {
            throw ImageCodecError.unsupportedBitsPerPixel(UInt8(truncatingIfNeeded: bitCount))
        }
        try validateMasks([luminanceMask, alphaMask], bitCount: bitCount, field: "luminance")
        guard luminanceMask != 0 else {
            throw ImageCodecError.invalidDDSMask("luminance channel needs a mask")
        }

        let bytesPerPixel = bitCount / 8
        guard payloadOffset <= reader.count else {
            throw ImageCodecError.truncated(
                field: "DDS luminance pixels", expected: payloadOffset, available: reader.count
            )
        }
        let available = reader.count - payloadOffset
        let stride = try rowStride(
            pitch: pitch, width: width, height: height, bytesPerPixel: bytesPerPixel,
            availableBytes: available, field: "DDS luminance data"
        )
        let dataBytes = try checkedMultiply(stride, height, field: "DDS luminance data")
        guard dataBytes <= available else {
            throw ImageCodecError.truncated(
                field: "DDS luminance pixels", expected: dataBytes, available: available
            )
        }

        let usesAlpha = (pfFlags & PixelFormatFlags.alphaPixels) != 0 || alphaMask != 0
        var pixels = try makePixels(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = payloadOffset + y * stride + x * bytesPerPixel
                let raw = bytesValue(reader.bytes, offset, bytesPerPixel)
                let value = channel(from: raw, mask: luminanceMask)
                let color = RGBA8(
                    r: value, g: value, b: value,
                    a: usesAlpha ? channel(from: raw, mask: alphaMask) : 255
                )
                try write(color, x: x, y: y, width: width, height: height, into: &pixels)
            }
        }
        return DecodedImage(width: width, height: height, pixels: Data(pixels))
    }
}

// MARK: - Loading and container resolution

/// Resolves texture paths through `ClientAssetStore`, the original client's
/// manifest/pack index, `.pack` directories, and Qt `.rcc` archives, then
/// dispatches to the TGA/DDS/PNG handler.
public struct TextureLoader {
    public enum Format: Equatable, Sendable {
        case tga
        case dds
        case png
    }

    /// Byte lookup for manifest-relative paths. The app passes
    /// `ClientAssetStore.shared.data(for:)`; tests can inject in-memory data.
    public typealias Lookup = @Sendable (String) -> Data?

    private let lookup: Lookup?
    private let rccZlibDecompressor: ((Data) throws -> Data)?
    private let worldCatalog: WorldAssetCatalog?

    public init(
        lookup: Lookup? = nil,
        rccZlibDecompressor: ((Data) throws -> Data)? = nil,
        worldCatalog: WorldAssetCatalog? = nil
    ) {
        self.lookup = lookup
        self.rccZlibDecompressor = rccZlibDecompressor
        self.worldCatalog = worldCatalog
    }

    /// Uses the app's embedded/sandbox asset store and world asset catalog.
    public init() {
        self.init(
            lookup: { ClientAssetStore.shared.data(for: $0) },
            worldCatalog: WorldAssetCatalog.bundledCatalog
        )
    }

    /// Chooses a decoder from the file magic and, for extension-only formats
    /// such as TGA, the file name.
    public static func format(for data: Data, name: String? = nil) -> Format? {
        let reader = ByteReader(data)
        if reader.count >= 4, (try? reader.fourCC(at: 0, field: "magic")) == "DDS " {
            return .dds
        }
        if reader.count >= 8 {
            let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
            if Array(reader.bytes[0..<8]) == signature {
                return .png
            }
        }
        if reader.count >= 18, looksLikeTGA(reader, name: name) {
            return .tga
        }
        switch (name as NSString?)?.pathExtension.lowercased() {
        case "dds"?:
            return .dds
        case "png"?:
            return .png
        case "tga"?:
            return .tga
        default:
            return nil
        }
    }

    private static func looksLikeTGA(_ reader: ByteReader, name: String?) -> Bool {
        guard let idLength = try? reader.byte(at: 0, field: "TGA ID"),
              let colorMapType = try? reader.byte(at: 1, field: "TGA map"),
              let imageType = try? reader.byte(at: 2, field: "TGA type"),
              let width = try? reader.u16LE(at: 12, field: "TGA width"),
              let height = try? reader.u16LE(at: 14, field: "TGA height"),
              let bpp = try? reader.byte(at: 16, field: "TGA bpp")
        else { return false }
        guard width > 0, height > 0, Int(idLength) + 18 <= reader.count else { return false }
        guard colorMapType == 0, [2, 3, 10, 11].contains(imageType) else { return false }
        if [8, 16, 24, 32].contains(bpp) { return true }
        // A short file named *.tga is still handed to the decoder for a clear error.
        return (name as NSString?)?.pathExtension.lowercased() == "tga"
    }

    /// Decodes data directly. PNG data is returned as passthrough.
    @discardableResult
    public static func decode(data: Data, name: String) throws -> DecodedImage {
        guard let format = format(for: data, name: name) else {
            throw ImageCodecError.ambiguousFormat(name)
        }
        switch format {
        case .tga:
            return try TGADecoder.decode(data: data)
        case .dds:
            return try DDSDecoder.decode(data: data)
        case .png:
            return try decodePNG(data)
        }
    }

    /// Resolves `relativePath` through the injected byte lookup and world asset
    /// catalog. A container entry uses `archive#entry` syntax, e.g.
    /// `Assets_000.pack#ui.png` or `tcg/cards.rcc#template_trick_nature_foil.png`.
    /// Manifest names such as `img10888699995024875749.dds.z` resolve to the
    /// CRC-verified pack payload stored under the name without `.z`.
    public func load(relativePath: String) throws -> DecodedImage {
        let parts = relativePath.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let archivePath = String(parts[0])
        let entry = parts.count == 2 ? String(parts[1]) : nil
        var data = lookup?(archivePath)
        var resolvedName = archivePath
        if data == nil, let worldCatalog {
            data = try worldCatalog.payload(for: archivePath)
            if resolvedName.hasSuffix(".z") {
                resolvedName = String(resolvedName.dropLast(2))
            }
        }
        guard let data else {
            throw ImageCodecError.resourceNotFound(relativePath)
        }
        if let entry, !entry.isEmpty {
            if (archivePath as NSString).pathExtension.lowercased() == "pack" {
                return try load(packData: data, entryName: entry)
            }
            return try load(rccData: data, nodePath: entry)
        }
        return try Self.decode(data: data, name: resolvedName)
    }

    /// Reads one named payload from a `.pack` directory and decodes it.
    public func load(packData: Data, entryName: String) throws -> DecodedImage {
        let archive = try PackArchive(packData)
        let payload = try archive.payload(named: entryName)
        return try Self.decode(data: payload, name: entryName)
    }

    /// Reads one file node from a `.rcc` archive and decodes it.
    ///
    /// TCG archives XOR their payloads with 0x73; pass `deobfuscateKey: 0` for
    /// unobfuscated archives. Compressed nodes require a zlib decompressor at
    /// initialization.
    public func load(
        rccData: Data, nodePath: String, deobfuscateKey: UInt8? = 0x73
    ) throws -> DecodedImage {
        var archive = try RccArchive(rccData)
        archive.zlibDecompressor = rccZlibDecompressor
        guard let node = archive.node(atPath: nodePath), node.isFile else {
            throw ImageCodecError.resourceNotFound(nodePath)
        }
        let payload: Data
        if case .file(_, let compression) = node.kind, compression != .none {
            guard rccZlibDecompressor != nil else {
                throw ImageCodecError.compressedRCCResource(nodePath)
            }
            payload = try archive.decompressedPayload(
                for: node, key: deobfuscateKey ?? 0x73
            )
        } else if let key = deobfuscateKey {
            payload = try archive.deobfuscatedPayload(for: node, key: key)
        } else {
            payload = try archive.payload(for: node)
        }
        return try Self.decode(data: payload, name: nodePath)
    }

    private static func decodePNG(_ data: Data) throws -> DecodedImage {
        let reader = ByteReader(data)
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard reader.count >= 8, Array(reader.bytes[0..<8]) == signature else {
            throw ImageCodecError.invalidMagic("PNG")
        }
        guard reader.count >= 24 else {
            throw ImageCodecError.truncated(field: "PNG IHDR", expected: 24, available: reader.count)
        }
        let chunkLength = try reader.u32BE(at: 8, field: "PNG IHDR length")
        guard chunkLength >= 13,
              try reader.fourCC(at: 12, field: "PNG IHDR type") == "IHDR"
        else {
            throw ImageCodecError.malformedPNG("missing or short IHDR chunk")
        }
        guard let width = Int(exactly: try reader.u32BE(at: 16, field: "PNG width")),
              let height = Int(exactly: try reader.u32BE(at: 20, field: "PNG height"))
        else {
            throw ImageCodecError.malformedPNG("dimensions are too large")
        }
        _ = try checkedPixelBytes(width: width, height: height)
        return DecodedImage(width: width, height: height, pixels: Data(), pngData: Data(data))
    }
}
