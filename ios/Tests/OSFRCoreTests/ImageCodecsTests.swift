import Foundation
import XCTest
@testable import OSFRCore

// All fixtures are generated here: no files are read from the embedded client.
// Helpers are file-private so they cannot collide with other test fixtures.

private struct TestPixel {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    static let red = TestPixel(r: 255, g: 0, b: 0, a: 255)
    static let green = TestPixel(r: 0, g: 255, b: 0, a: 255)
    static let blue = TestPixel(r: 0, g: 0, b: 255, a: 255)
    static let white = TestPixel(r: 255, g: 255, b: 255, a: 255)
    static let black = TestPixel(r: 0, g: 0, b: 0, a: 255)
    static let yellow = TestPixel(r: 255, g: 255, b: 0, a: 255)
    static let cyan = TestPixel(r: 0, g: 255, b: 255, a: 255)
}

private func le16(_ value: UInt16) -> Data {
    Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
}

private func le32(_ value: UInt32) -> Data {
    Data([
        UInt8(truncatingIfNeeded: value),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 24)
    ])
}

private func be16(_ value: UInt16) -> Data {
    Data([UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
}

private func be32(_ value: UInt32) -> Data {
    Data([
        UInt8(truncatingIfNeeded: value >> 24),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value)
    ])
}

private func bgra(_ pixel: TestPixel) -> Data {
    Data([pixel.b, pixel.g, pixel.r, pixel.a])
}

private func bgr(_ pixel: TestPixel) -> Data {
    Data([pixel.b, pixel.g, pixel.r])
}

private func tga(
    width: Int, height: Int, type: UInt8, bpp: UInt8, descriptor: UInt8, payload: Data,
    colorMapType: UInt8 = 0, colorMapLength: UInt16 = 0
) -> Data {
    var data = Data([0, colorMapType, type])
    data.append(le16(0)) // color map first entry
    data.append(le16(colorMapLength))
    data.append(0)       // color map entry size
    data.append(le16(0)) // x origin
    data.append(le16(0)) // y origin
    data.append(le16(UInt16(width)))
    data.append(le16(UInt16(height)))
    data.append(bpp)
    data.append(descriptor)
    data.append(payload)
    return data
}

private func rlePacket(repeat: Bool, pixels: [TestPixel], count: Int? = nil) -> Data {
    let run = count ?? pixels.count
    precondition(!pixels.isEmpty && run >= 1 && run <= 128)
    var data = Data([UInt8(run - 1) | (`repeat` ? 0x80 : 0)])
    if `repeat` {
        data.append(bgra(pixels[0]))
    } else {
        for pixel in pixels { data.append(bgra(pixel)) }
    }
    return data
}

private func dds(
    width: Int,
    height: Int,
    fourCC: String?,
    pfFlags: UInt32,
    pitch: Int,
    bitCount: Int,
    masks: [UInt32] = [0, 0, 0, 0],
    mipCount: UInt32 = 0,
    payload: Data
) -> Data {
    var data = Data("DDS ".utf8)
    data.append(le32(124))
    data.append(le32(0x1007)) // CAPS | HEIGHT | WIDTH | PIXELFORMAT
    data.append(le32(UInt32(height)))
    data.append(le32(UInt32(width)))
    data.append(le32(UInt32(pitch)))
    data.append(le32(0)) // depth
    data.append(le32(mipCount))
    for _ in 0..<11 { data.append(le32(0)) } // reserved
    data.append(le32(32)) // pixel format size
    data.append(le32(pfFlags))
    var code = Array((fourCC ?? "").utf8.prefix(4))
    while code.count < 4 { code.append(0) }
    data.append(Data(code))
    data.append(le32(UInt32(bitCount)))
    for mask in masks { data.append(le32(mask)) }
    data.append(le32(0x1000)) // DDSCAPS_TEXTURE
    data.append(le32(0)) // caps2
    data.append(le32(0)) // caps3
    data.append(le32(0)) // caps4
    data.append(le32(0)) // reserved2
    precondition(data.count == 128)
    data.append(payload)
    return data
}

private func bc1Block(color0: UInt16, color1: UInt16, indices: [UInt8]) -> Data {
    precondition(indices.count == 16)
    var bits: UInt32 = 0
    for (index, value) in indices.enumerated() {
        bits |= UInt32(value & 0x3) << UInt32(index * 2)
    }
    var data = le16(color0)
    data.append(le16(color1))
    data.append(le32(bits))
    return data
}

private func dxt3Block(color: Data, alphas: [UInt8]) -> Data {
    precondition(alphas.count == 16 && color.count == 8)
    var alphaBytes = [UInt8](repeating: 0, count: 8)
    for (index, alpha) in alphas.enumerated() {
        let nibble = UInt8((alpha / 17) & 0x0F)
        let byte = (index / 4) * 2 + (index % 4) / 2
        if index % 2 == 0 {
            alphaBytes[byte] |= nibble
        } else {
            alphaBytes[byte] |= nibble << 4
        }
    }
    var data = Data(alphaBytes)
    data.append(color)
    return data
}

private func dxt5Block(alpha0: UInt8, alpha1: UInt8, alphaIndices: [UInt8], color: Data) -> Data {
    precondition(alphaIndices.count == 16 && color.count == 8)
    var indexBytes = [UInt8](repeating: 0, count: 6)
    for (pixel, index) in alphaIndices.enumerated() {
        let bit = pixel * 3
        let byte = bit / 8
        let shift = bit % 8
        indexBytes[byte] |= UInt8(index & 0x7) << UInt8(shift)
        if shift > 5 {
            indexBytes[byte + 1] |= UInt8(index & 0x7) >> UInt8(8 - shift)
        }
    }
    var data = Data([alpha0, alpha1])
    data.append(Data(indexBytes))
    data.append(color)
    return data
}

private func pixel(_ image: DecodedImage, _ x: Int, _ y: Int) -> [UInt8] {
    let offset = (y * image.width + x) * 4
    return Array(image.pixels[offset..<(offset + 4)])
}

private func testPack(name: String, payload: Data) -> Data {
    let nameBytes = Data(name.utf8)
    var data = be32(0)
    data.append(be32(1))
    data.append(be32(UInt32(nameBytes.count)))
    data.append(nameBytes)
    data.append(be32(8 + 4 + UInt32(nameBytes.count) + 12))
    data.append(be32(UInt32(payload.count)))
    data.append(be32(CRC32.checksum(payload)))
    data.append(payload)
    return data
}

private func testRCC(name: String, payload: Data, xorKey: UInt8?) -> Data {
    let stored = Data(payload.map { byte in
        guard let key = xorKey else { return byte }
        return byte ^ key
    })
    var rootName = be16(0)
    rootName.append(be32(0))
    var names = rootName
    let fileOffset = names.count
    names.append(be16(UInt16(name.utf16.count)))
    names.append(be32(0))
    for unit in name.utf16 { names.append(be16(unit)) }

    var blobs = be32(UInt32(stored.count))
    blobs.append(stored)

    var tree = be32(0) // root name offset
    tree.append(be16(0x02)) // directory
    tree.append(be32(1))
    tree.append(be32(1))
    tree.append(be32(UInt32(fileOffset)))
    tree.append(be16(0)) // file flags
    tree.append(be16(0)) // territory
    tree.append(be16(0)) // language
    tree.append(be32(0)) // first blob at data offset

    let dataOffset = 20
    let namesOffset = dataOffset + blobs.count
    let treeOffset = namesOffset + names.count
    var data = Data("qres".utf8)
    data.append(be32(1))
    data.append(be32(UInt32(treeOffset)))
    data.append(be32(UInt32(dataOffset)))
    data.append(be32(UInt32(namesOffset)))
    data.append(blobs)
    data.append(names)
    data.append(tree)
    return data
}

final class ImageCodecsTests: XCTestCase {
    // MARK: - TGA

    func testTGADecodeUncompressed32bppWithBottomOrigin() throws {
        let payload = bgra(.red) + bgra(.green) + bgra(.blue) + bgra(.white)
        // Descriptor 0x08: 8 alpha bits, lower-left origin (the client's usual TGA).
        let file = tga(width: 2, height: 2, type: 2, bpp: 32, descriptor: 0x08, payload: payload)

        let image = try TGADecoder.decode(data: file)
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.byteCount, 16)
        XCTAssertEqual(pixel(image, 0, 0), [0, 0, 255, 255])
        XCTAssertEqual(pixel(image, 1, 0), [255, 255, 255, 255])
        XCTAssertEqual(pixel(image, 0, 1), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, 1, 1), [0, 255, 0, 255])
    }

    func testTGADecodeRLEWithTopOrigin() throws {
        var payload = rlePacket(repeat: true, pixels: [.red], count: 2)
        payload.append(rlePacket(repeat: false, pixels: [.green, .blue, .white, .black]))
        payload.append(rlePacket(repeat: true, pixels: [.yellow], count: 2))
        // Descriptor 0x28: 8 alpha bits + upper-left origin.
        let file = tga(width: 4, height: 2, type: 10, bpp: 32, descriptor: 0x28, payload: payload)

        let image = try TGADecoder.decode(data: file)
        XCTAssertEqual(pixel(image, 0, 0), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, 2, 0), [0, 255, 0, 255])
        XCTAssertEqual(pixel(image, 3, 0), [0, 0, 255, 255])
        XCTAssertEqual(pixel(image, 0, 1), [255, 255, 255, 255])
        XCTAssertEqual(pixel(image, 1, 1), [0, 0, 0, 255])
        XCTAssertEqual(pixel(image, 2, 1), [255, 255, 0, 255])
    }

    func testTGADecode24bppAndGrayscale() throws {
        let trueColor = tga(
            width: 2, height: 1, type: 2, bpp: 24, descriptor: 0x20,
            payload: bgr(.red) + bgr(.blue)
        )
        let rgb = try TGADecoder.decode(data: trueColor)
        XCTAssertEqual(pixel(rgb, 0, 0), [255, 0, 0, 255])
        XCTAssertEqual(pixel(rgb, 1, 0), [0, 0, 255, 255])

        let gray = tga(
            width: 2, height: 1, type: 3, bpp: 8, descriptor: 0x20,
            payload: Data([10, 200])
        )
        let grayImage = try TGADecoder.decode(data: gray)
        XCTAssertEqual(pixel(grayImage, 0, 0), [10, 10, 10, 255])
        XCTAssertEqual(pixel(grayImage, 1, 0), [200, 200, 200, 255])
    }

    func testTGADecode16bppARGB1555() throws {
        let opaqueRed: UInt16 = 0xFC00
        let transparentBlue: UInt16 = 0x001F
        let file = tga(
            width: 2, height: 1, type: 2, bpp: 16, descriptor: 0x21,
            payload: le16(opaqueRed) + le16(transparentBlue)
        )
        let image = try TGADecoder.decode(data: file)
        XCTAssertEqual(pixel(image, 0, 0), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, 1, 0), [0, 0, 255, 0])
    }

    func testTGARejectsMalformedInputs() {
        let colorMapped = tga(
            width: 1, height: 1, type: 2, bpp: 32, descriptor: 0,
            payload: bgra(.red), colorMapType: 1, colorMapLength: 1
        )
        XCTAssertThrowsError(try TGADecoder.decode(data: colorMapped)) { error in
            guard case ImageCodecError.unsupportedColorMap = error else {
                return XCTFail("Expected unsupportedColorMap, got \(error)")
            }
        }

        let truncated = tga(
            width: 2, height: 2, type: 2, bpp: 32, descriptor: 0x08,
            payload: bgra(.red) + bgra(.green) + bgra(.blue)
        )
        XCTAssertThrowsError(try TGADecoder.decode(data: truncated)) { error in
            guard case ImageCodecError.truncated = error else {
                return XCTFail("Expected truncated, got \(error)")
            }
        }

        let badRun = tga(
            width: 2, height: 1, type: 10, bpp: 32, descriptor: 0x08,
            payload: rlePacket(repeat: true, pixels: [.red], count: 3)
        )
        XCTAssertThrowsError(try TGADecoder.decode(data: badRun)) { error in
            guard case ImageCodecError.invalidTGARLE = error else {
                return XCTFail("Expected invalidTGARLE, got \(error)")
            }
        }

        let short = Data([0, 0, 2])
        XCTAssertThrowsError(try TGADecoder.decode(data: short)) { error in
            guard case ImageCodecError.truncated = error else {
                return XCTFail("Expected truncated header, got \(error)")
            }
        }
    }

    // MARK: - DDS uncompressed

    func testDDSDecodeUncompressedBGRA() throws {
        // pitch=16 mimics client files that store the whole linear size here.
        let file = dds(
            width: 2, height: 1, fourCC: nil, pfFlags: 0x41, pitch: 16, bitCount: 32,
            masks: [0x00FF_0000, 0x0000_FF00, 0x0000_00FF, 0xFF00_0000],
            payload: bgra(.red) + bgra(.green)
        )
        let image = try DDSDecoder.decode(data: file)
        XCTAssertEqual(pixel(image, 0, 0), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, 1, 0), [0, 255, 0, 255])
    }

    func testDDSDecodeUncompressedRGB565AndLuminanceAlpha() throws {
        let rgb565 = dds(
            width: 2, height: 1, fourCC: nil, pfFlags: 0x40, pitch: 4, bitCount: 16,
            masks: [0xF800, 0x07E0, 0x001F, 0],
            payload: le16(0xF800) + le16(0x001F)
        )
        let rgbImage = try DDSDecoder.decode(data: rgb565)
        XCTAssertEqual(pixel(rgbImage, 0, 0), [255, 0, 0, 255])
        XCTAssertEqual(pixel(rgbImage, 1, 0), [0, 0, 255, 255])

        // DDPF_LUMINANCE | DDPF_ALPHAPIXELS, 8-bit luminance + 8-bit alpha.
        let luminance = dds(
            width: 1, height: 1, fourCC: nil, pfFlags: 0x2_0001, pitch: 2, bitCount: 16,
            masks: [0x00FF, 0, 0, 0xFF00],
            payload: le16(0x40C8) // L=0xC8, A=0x40
        )
        let luminanceImage = try DDSDecoder.decode(data: luminance)
        XCTAssertEqual(pixel(luminanceImage, 0, 0), [200, 200, 200, 64])
    }

    // MARK: - DDS block compression

    func testDDSDecodeDXT1FourColorBlock() throws {
        let indices: [UInt8] = [
            0, 1, 2, 3,
            3, 2, 1, 0,
            1, 2, 3, 0,
            2, 3, 0, 1
        ]
        let block = bc1Block(color0: 0xF800, color1: 0x001F, indices: indices)
        let file = dds(
            width: 4, height: 4, fourCC: "DXT1", pfFlags: 0x4, pitch: 8, bitCount: 0,
            payload: block
        )
        let image = try DDSDecoder.decode(data: file)
        let expected: [[UInt8]] = [
            [255, 0, 0, 255],
            [0, 0, 255, 255],
            [170, 0, 85, 255],
            [85, 0, 170, 255]
        ]
        for (index, value) in indices.enumerated() {
            let x = index % 4
            let y = index / 4
            XCTAssertEqual(pixel(image, x, y), expected[Int(value)])
        }
    }

    func testDDSDecodeDXT3ExplicitAlpha() throws {
        let alphas: [UInt8] = [
            0, 255, 136, 119,
            255, 0, 119, 136,
            136, 119, 0, 255,
            119, 136, 255, 0
        ]
        let color = bc1Block(
            color0: 0xF800, color1: 0x001F,
            indices: [UInt8](repeating: 0, count: 16)
        )
        let file = dds(
            width: 4, height: 4, fourCC: "DXT3", pfFlags: 0x4, pitch: 16, bitCount: 0,
            payload: dxt3Block(color: color, alphas: alphas)
        )
        let image = try DDSDecoder.decode(data: file)
        for (index, alpha) in alphas.enumerated() {
            let pixelValue = pixel(image, index % 4, index / 4)
            XCTAssertEqual(pixelValue[0], 255)
            XCTAssertEqual(pixelValue[3], alpha)
        }
    }

    func testDDSDecodeDXT5InterpolatedAlpha() throws {
        let alphaIndices: [UInt8] = [
            0, 1, 2, 3,
            4, 5, 0, 1,
            2, 3, 4, 5,
            0, 1, 2, 3
        ]
        let color = bc1Block(
            color0: 0xFFFF, color1: 0xF800,
            indices: [UInt8](repeating: 0, count: 16)
        )
        let file = dds(
            width: 4, height: 4, fourCC: "DXT5", pfFlags: 0x4, pitch: 16, bitCount: 0,
            payload: dxt5Block(
                alpha0: 255, alpha1: 0, alphaIndices: alphaIndices, color: color
            )
        )
        let image = try DDSDecoder.decode(data: file)
        let expected: [UInt8] = [255, 0, 204, 153, 102, 51]
        for (index, alpha) in alphaIndices.enumerated() {
            XCTAssertEqual(pixel(image, index % 4, index / 4)[3], expected[Int(alpha)])
        }
    }

    func testDDSRejectsUnsupportedAndTruncatedBlocks() {
        let unsupported = dds(
            width: 4, height: 4, fourCC: "DXT2", pfFlags: 0x4, pitch: 16, bitCount: 0,
            payload: Data(repeating: 0, count: 16)
        )
        XCTAssertThrowsError(try DDSDecoder.decode(data: unsupported)) { error in
            guard case ImageCodecError.unsupportedDDSFourCC("DXT2") = error else {
                return XCTFail("Expected unsupportedDDSFourCC(DXT2), got \(error)")
            }
        }

        let truncated = dds(
            width: 4, height: 4, fourCC: "DXT1", pfFlags: 0x4, pitch: 8, bitCount: 0,
            payload: Data(repeating: 0, count: 7)
        )
        XCTAssertThrowsError(try DDSDecoder.decode(data: truncated)) { error in
            guard case ImageCodecError.truncated = error else {
                return XCTFail("Expected truncated DXT1 data, got \(error)")
            }
        }
    }

    // MARK: - TextureLoader

    func testTextureLoaderPassesPNGThrough() throws {
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        png.append(be32(13))
        png.append(Data("IHDR".utf8))
        png.append(be32(3))
        png.append(be32(5))
        png.append(Data([8, 6, 0, 0, 0]))

        XCTAssertEqual(TextureLoader.format(for: png, name: "unused.bin"), .png)
        let image = try TextureLoader.decode(data: png, name: "unused.bin")
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 5)
        XCTAssertTrue(image.isPNGPassthrough)
        XCTAssertEqual(image.byteCount, 0)
        XCTAssertEqual(image.pngData, png)
    }

    func testTextureLoaderPackLookup() throws {
        let payload = tga(
            width: 1, height: 1, type: 2, bpp: 32, descriptor: 0x28,
            payload: bgra(.red)
        )
        let pack = testPack(name: "icon.tga", payload: payload)
        let loader = TextureLoader(lookup: { path in path == "Assets_000.pack" ? pack : nil })

        let image = try loader.load(relativePath: "Assets_000.pack#icon.tga")
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(pixel(image, 0, 0), [255, 0, 0, 255])
    }

    func testTextureLoaderRCCLookupWithDeobfuscation() throws {
        let payload = dds(
            width: 1, height: 1, fourCC: nil, pfFlags: 0x41, pitch: 4, bitCount: 32,
            masks: [0x00FF_0000, 0x0000_FF00, 0x0000_00FF, 0xFF00_0000],
            payload: bgra(.blue)
        )
        let archive = testRCC(name: "icon.dds", payload: payload, xorKey: 0x73)
        let loader = TextureLoader(lookup: { path in path == "tcg/cards.rcc" ? archive : nil })

        let image = try loader.load(relativePath: "tcg/cards.rcc#icon.dds")
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(pixel(image, 0, 0), [0, 0, 255, 255])

        let plaintextArchive = testRCC(name: "icon.dds", payload: payload, xorKey: nil)
        let plainImage = try TextureLoader().load(
            rccData: plaintextArchive, nodePath: "icon.dds", deobfuscateKey: 0
        )
        XCTAssertEqual(pixel(plainImage, 0, 0), [0, 0, 255, 255])
    }
}
