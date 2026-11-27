import Foundation
import SwiftUI

#if canImport(MetalKit) && canImport(UIKit)
import Metal
import MetalKit
import UIKit

/// Minimal Metal renderer for `EngineFrame`.
///
/// It draws colored primitives and any decoded client textures carried in the
/// frame. Textures are decoded on the Foundation side into RGBA8 bytes; Metal
/// only uploads them, so no desktop executable or external framework is needed
/// on iOS.
struct MetalWorldView: UIViewRepresentable {
    let frame: EngineFrame

    func makeCoordinator() -> Coordinator {
        Coordinator(frame: frame)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.frame = frame
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        /// x, y, r, g, b, a, u, v, useTexture.
        private static let floatsPerVertex = 9

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float4 color;
            float2 uv;
            float useTexture;
        };

        vertex VertexOut vertex_main(
            const device float *vertices [[buffer(0)]],
            uint vertexID [[vertex_id]],
            constant float2 &viewport [[buffer(1)]]
        ) {
            // Each vertex is nine floats. vertexID indexes vertices, not quads.
            uint base = vertexID * 9u;
            float2 point = float2(vertices[base], vertices[base + 1u]);
            float4 color = float4(vertices[base + 2u], vertices[base + 3u],
                                  vertices[base + 4u], vertices[base + 5u]);
            float2 clip = point * 2.0 - 1.0;
            clip.y = -clip.y;
            VertexOut out;
            out.position = float4(clip, 0.0, 1.0);
            out.color = color;
            out.uv = float2(vertices[base + 6u], vertices[base + 7u]);
            out.useTexture = vertices[base + 8u];
            // viewport is reserved for the perspective projection that replaces
            // this atlas-style orthographic pass.
            (void)viewport;
            return out;
        }

        fragment float4 fragment_main(
            VertexOut input [[stage_in]],
            texture2d<float, access::sample> texture [[texture(0)]],
            sampler textureSampler [[sampler(0)]]
        ) {
            float4 sampled = texture.sample(textureSampler, input.uv);
            return mix(input.color, sampled * input.color, input.useTexture);
        }
        """

        var frame: EngineFrame
        private var pipelineState: MTLRenderPipelineState?
        private var samplerState: MTLSamplerState?
        private var whiteTexture: MTLTexture?
        private var textureCache: [String: MTLTexture] = [:]

        init(frame: EngineFrame) {
            self.frame = frame
        }

        func configure(view: MTKView) {
            guard let device = view.device else { return }
            let library: MTLLibrary
            do {
                library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            } catch {
                NSLog("OSFR Metal shader compile failed: \(error.localizedDescription)")
                return
            }

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: 1,
                height: 1,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead]
            if let texture = device.makeTexture(descriptor: textureDescriptor) {
                let white: [UInt8] = [255, 255, 255, 255]
                white.withUnsafeBytes { raw in
                    texture.replace(
                        region: MTLRegionMake2D(0, 0, 1, 1),
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: 4
                    )
                }
                whiteTexture = texture
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                NSLog("OSFR Metal pipeline failed: \(error.localizedDescription)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipelineState,
                  let samplerState,
                  let whiteTexture,
                  let device = view.device,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable
            else { return }

            var coloredVertices: [Float] = []
            var texturedBatches: [String: [Float]] = [:]

            for item in frame.drawables.sorted(by: { $0.layer < $1.layer }) {
                if let textureName = item.textureName,
                   let image = frame.textures[textureName],
                   texture(for: textureName, image: image, device: device) != nil {
                    Self.appendQuad(
                        item.rect,
                        color: item.color,
                        textureName: textureName,
                        into: &texturedBatches[textureName, default: []]
                    )
                } else {
                    Self.appendQuad(item.rect, color: item.color, textureName: nil, into: &coloredVertices)
                }
                if let outline = item.outline {
                    let thickness = 0.0015
                    let rect = item.rect
                    Self.appendQuad(
                        EngineRect(x: rect.x, y: rect.y, width: rect.width, height: thickness),
                        color: outline,
                        textureName: nil,
                        into: &coloredVertices
                    )
                    Self.appendQuad(
                        EngineRect(x: rect.x, y: rect.y + rect.height - thickness,
                                   width: rect.width, height: thickness),
                        color: outline,
                        textureName: nil,
                        into: &coloredVertices
                    )
                    Self.appendQuad(
                        EngineRect(x: rect.x, y: rect.y, width: thickness, height: rect.height),
                        color: outline,
                        textureName: nil,
                        into: &coloredVertices
                    )
                    Self.appendQuad(
                        EngineRect(x: rect.x + rect.width - thickness, y: rect.y,
                                   width: thickness, height: rect.height),
                        color: outline,
                        textureName: nil,
                        into: &coloredVertices
                    )
                }
            }

            var batches: [(texture: MTLTexture, vertices: [Float])] = []
            if !coloredVertices.isEmpty {
                batches.append((whiteTexture, coloredVertices))
            }
            for name in texturedBatches.keys.sorted() {
                guard let image = frame.textures[name],
                      let texture = texture(for: name, image: image, device: device),
                      let vertices = texturedBatches[name]
                else { continue }
                batches.append((texture, vertices))
            }
            guard !batches.isEmpty else { return }

            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            for batch in batches {
                var vertices = batch.vertices
                guard let buffer = device.makeBuffer(
                    bytes: &vertices,
                    length: vertices.count * MemoryLayout<Float>.stride,
                    options: .storageModeShared
                ) else { continue }
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
                encoder.setRenderPipelineState(pipelineState)
                // Render encoders bind fragment resources, unlike compute encoders.
                encoder.setFragmentSamplerState(samplerState, index: 0)
                encoder.setFragmentTexture(batch.texture, index: 0)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                var viewport = simd_float2(
                    Float(view.drawableSize.width),
                    Float(view.drawableSize.height)
                )
                encoder.setVertexBytes(&viewport, length: MemoryLayout<simd_float2>.stride, index: 1)
                encoder.drawPrimitives(
                    type: .triangle,
                    vertexStart: 0,
                    vertexCount: vertices.count / Self.floatsPerVertex
                )
                encoder.endEncoding()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// Uploads a decoded client image once, keyed by path and dimensions.
        private func texture(for name: String, image: DecodedImage, device: MTLDevice) -> MTLTexture? {
            let key = "\(name):\(image.width)x\(image.height)"
            if let cached = textureCache[key] { return cached }

            let created: MTLTexture?
            if !image.pixels.isEmpty {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba8Unorm,
                    width: image.width,
                    height: image.height,
                    mipmapped: false
                )
                descriptor.usage = [.shaderRead]
                guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
                let bytes = [UInt8](image.pixels)
                let bytesPerRow = image.width * 4
                guard bytes.count >= bytesPerRow * image.height else { return nil }
                bytes.withUnsafeBytes { raw in
                    texture.replace(
                        region: MTLRegionMake2D(0, 0, image.width, image.height),
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: bytesPerRow
                    )
                }
                created = texture
            } else if let pngData = image.pngData {
                let options: [MTKTextureLoader.Option: Any] = [
                    .SRGB: false,
                    .generateMipmaps: false,
                    .origin: MTKTextureLoader.Origin.topLeft
                ]
                created = try? MTKTextureLoader(device: device).newTexture(data: pngData, options: options)
            } else {
                created = nil
            }

            if let created { textureCache[key] = created }
            return created
        }

        /// Each vertex is nine floats: x, y, r, g, b, a, u, v, useTexture.
        private static func appendQuad(
            _ rect: EngineRect,
            color: EngineColor,
            textureName: String?,
            into vertices: inout [Float]
        ) {
            let x0 = Float(rect.x)
            let y0 = Float(rect.y)
            let x1 = Float(rect.x + rect.width)
            let y1 = Float(rect.y + rect.height)
            let useTexture: Float = textureName == nil ? 0 : 1
            let points = [
                (x0, y0, Float(0), Float(0)),
                (x1, y0, Float(1), Float(0)),
                (x0, y1, Float(0), Float(1)),
                (x0, y1, Float(0), Float(1)),
                (x1, y0, Float(1), Float(0)),
                (x1, y1, Float(1), Float(1))
            ]
            for point in points {
                vertices.append(point.0)
                vertices.append(point.1)
                vertices.append(Float(color.r))
                vertices.append(Float(color.g))
                vertices.append(Float(color.b))
                vertices.append(Float(color.a))
                vertices.append(point.2)
                vertices.append(point.3)
                vertices.append(useTexture)
            }
        }
    }
}
#else
/// Placeholder used only when compiling the core outside an Apple SDK.
struct MetalWorldView: View {
    let frame: EngineFrame

    var body: some View {
        VStack {
            Text("Metal renderer unavailable")
            Text("\(frame.drawableCount) drawables · zone \(frame.zoneID)")
            if let textureStatus = frame.textureStatus {
                Text(textureStatus)
                    .font(.caption)
            }
        }
    }
}
#endif
