import Foundation
import SwiftUI

#if canImport(MetalKit) && canImport(UIKit)
import Metal
import MetalKit
import UIKit

/// Minimal Metal renderer for `EngineFrame`. It draws tiles, entities and the
/// player as colored primitives; texture-backed meshes remain an engine asset
/// pipeline responsibility so no desktop executable or external framework is
/// required on iOS.
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
        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut vertex_main(
            const device float *vertices [[buffer(0)]],
            uint vertexID [[vertex_id]],
            constant float2 &viewport [[buffer(1)]]
        ) {
            // Each vertex is six floats: x, y, r, g, b, a.
            // vertexID indexes vertices, not quads.
            uint base = vertexID * 6u;
            float2 point = float2(vertices[base], vertices[base + 1u]);
            float4 color = float4(vertices[base + 2u], vertices[base + 3u],
                                  vertices[base + 4u], vertices[base + 5u]);
            float2 clip = point * 2.0 - 1.0;
            clip.y = -clip.y;
            return VertexOut { float4(clip, 0.0, 1.0), color };
        }

        fragment float4 fragment_main(VertexOut input [[stage_in]]) {
            return input.color;
        }
        """

        var frame: EngineFrame
        private var pipelineState: MTLRenderPipelineState?

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
                  let device = view.device,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable
            else { return }

            var vertices: [Float] = []
            for drawableItem in frame.drawables.sorted(by: { $0.layer < $1.layer }) {
                Self.appendQuad(drawableItem.rect, color: drawableItem.color, into: &vertices)
                if let outline = drawableItem.outline {
                    let thickness = 0.0015
                    let rect = drawableItem.rect
                    Self.appendQuad(
                        EngineRect(x: rect.x, y: rect.y, width: rect.width, height: thickness),
                        color: outline,
                        into: &vertices
                    )
                    Self.appendQuad(
                        EngineRect(x: rect.x, y: rect.y + rect.height - thickness,
                                   width: rect.width, height: thickness),
                        color: outline,
                        into: &vertices
                    )
                    Self.appendQuad(
                        EngineRect(x: rect.x, y: rect.y, width: thickness, height: rect.height),
                        color: outline,
                        into: &vertices
                    )
                    Self.appendQuad(
                        EngineRect(x: rect.x + rect.width - thickness, y: rect.y,
                                   width: thickness, height: rect.height),
                        color: outline,
                        into: &vertices
                    )
                }
            }
            guard !vertices.isEmpty else { return }

            guard let buffer = device.makeBuffer(
                bytes: &vertices,
                length: vertices.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ) else { return }

            let commandQueue = device.makeCommandQueue()
            guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            guard let encoder else { return }
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            var viewport = simd_float2(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            )
            encoder.setVertexBytes(&viewport, length: MemoryLayout<simd_float2>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 6)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// Each vertex is six floats: x, y, r, g, b, a.
        private static func appendQuad(_ rect: EngineRect, color: EngineColor, into vertices: inout [Float]) {
            let x0 = Float(rect.x)
            let y0 = Float(rect.y)
            let x1 = Float(rect.x + rect.width)
            let y1 = Float(rect.y + rect.height)
            let points = [(x0, y0), (x1, y0), (x0, y1), (x0, y1), (x1, y0), (x1, y1)]
            for point in points {
                vertices.append(point.0)
                vertices.append(point.1)
                vertices.append(Float(color.r))
                vertices.append(Float(color.g))
                vertices.append(Float(color.b))
                vertices.append(Float(color.a))
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
        }
    }
}
#endif
