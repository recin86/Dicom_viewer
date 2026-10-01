import Foundation
@preconcurrency import Metal
@preconcurrency import QuartzCore
import ViewerBridge

public enum RenderingError: Error, Sendable {
    case unavailable, invalidDisplay, allocationFailed, commandFailed, referenceLimit
}

public enum PixelInterpolation: Sendable { case nearest, linear }
public enum DrawableRenderEvent: String, Sendable {
    case submitted, gpuCompleted, gpuFailed, presented, skipped
}

public final class UploadedPixelFrame: @unchecked Sendable {
    public let owned: OwnedPixelFrame
    fileprivate let pixels: any MTLTexture
    fileprivate let mask: any MTLTexture
    fileprivate init(owned: OwnedPixelFrame, pixels: any MTLTexture, mask: any MTLTexture) {
        self.owned = owned; self.pixels = pixels; self.mask = mask
    }
}

private struct ShaderUniforms {
    var dimensions: SIMD4<Float>
    var mapping: SIMD4<Float>
    var window: SIMD4<Float>
    var flags: SIMD4<UInt32>
}

/// Immutable per-frame textures. Uploads never overwrite a texture in flight.
public final class MetalFrameRenderer: @unchecked Sendable {
    public let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let rgbaPipeline: any MTLRenderPipelineState
    private let bgraPipeline: any MTLRenderPipelineState

    public static func make() async throws -> MetalFrameRenderer {
        try await Task.detached { try MetalFrameRenderer() }.value
    }

    private init() throws {
        guard !Thread.isMainThread, let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw RenderingError.unavailable }
        self.device = device; self.queue = queue
        let options = MTLCompileOptions()
        options.mathMode = .safe
        let library = try device.makeLibrary(source: Self.shaderSource, options: options)
        func pipeline(_ format: MTLPixelFormat) throws -> any MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "frame_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "frame_fragment")
            descriptor.colorAttachments[0].pixelFormat = format
            descriptor.colorAttachments[0].isBlendingEnabled = false
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        rgbaPipeline = try pipeline(.rgba8Unorm)
        bgraPipeline = try pipeline(.bgra8Unorm)
    }

    public func upload(_ frame: OwnedPixelFrame) async throws -> UploadedPixelFrame {
        try await Task.detached { [self] in try uploadWorker(frame) }.value
    }

    private func uploadWorker(_ frame: OwnedPixelFrame) throws -> UploadedPixelFrame {
            guard !Thread.isMainThread else { throw RenderingError.commandFailed }
            let info = frame.info
            guard info.width <= 16_384, info.height <= 16_384 else { throw RenderingError.invalidDisplay }
            guard frame.display.descriptorRevision == 1,
                  frame.display.pixelHeightOverWidth.isFinite, frame.display.pixelHeightOverWidth > 0 else {
                throw RenderingError.invalidDisplay
            }
            let format: MTLPixelFormat = info.pixelFormat == .grayF32LE ? .r32Float : .rgba8Unorm
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: Int(info.width), height: Int(info.height), mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.shaderRead]
            guard let pixels = device.makeTexture(descriptor: descriptor) else { throw RenderingError.allocationFailed }
            frame.withUnsafePixelBytes { bytes in
                pixels.replace(region: MTLRegionMake2D(0, 0, Int(info.width), Int(info.height)),
                               mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: Int(info.rowStrideBytes))
            }
            let maskDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Uint, width: info.maskLen == 0 ? 1 : Int(info.width),
                height: info.maskLen == 0 ? 1 : Int(info.height), mipmapped: false)
            maskDescriptor.storageMode = .shared; maskDescriptor.usage = [.shaderRead]
            guard let mask = device.makeTexture(descriptor: maskDescriptor) else { throw RenderingError.allocationFailed }
            frame.withUnsafeMaskBytes { bytes in
                if let bytes {
                    mask.replace(region: MTLRegionMake2D(0, 0, Int(info.width), Int(info.height)),
                                 mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: Int(info.width))
                } else {
                    var valid: UInt8 = 1
                    mask.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &valid, bytesPerRow: 1)
                }
            }
            return UploadedPixelFrame(owned: frame, pixels: pixels, mask: mask)
    }

    /// Test-only CPU readback, limited independently of the product frame budget.
    /// At native dimensions the output is a pixel grid; aspect is tested separately.
    public func renderOffscreen(_ frame: UploadedPixelFrame, window: VoiWindow? = nil,
                                userInvert: Bool = false, interpolation: PixelInterpolation = .linear,
                                transform: ViewportTransform? = nil,
                                outputWidth: Int? = nil, outputHeight: Int? = nil) async throws -> [UInt8] {
        try await Task.detached { [self] in
            try renderWorker(frame, window: window, userInvert: userInvert, interpolation: interpolation,
                             transform: transform, outputWidth: outputWidth, outputHeight: outputHeight)
        }.value
    }

    private func renderWorker(_ frame: UploadedPixelFrame, window: VoiWindow?, userInvert: Bool,
                              interpolation: PixelInterpolation, transform: ViewportTransform?,
                              outputWidth: Int?, outputHeight: Int?) throws -> [UInt8] {
            guard !Thread.isMainThread else { throw RenderingError.commandFailed }
            let width = outputWidth ?? Int(frame.owned.info.width)
            let height = outputHeight ?? Int(frame.owned.info.height)
            let (count, overflow) = width.multipliedReportingOverflow(by: height)
            guard width > 0, height > 0, !overflow, count <= 16_384 else { throw RenderingError.referenceLimit }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
            guard let target = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else {
                throw RenderingError.allocationFailed
            }
            let mapping = try transform ?? ViewportTransform(width: frame.owned.info.width, height: frame.owned.info.height,
                                                           aspect: 1, viewWidth: Double(width), viewHeight: Double(height))
            try encode(frame, target: target, command: command, pipeline: rgbaPipeline,
                       transform: mapping, window: window, userInvert: userInvert, interpolation: interpolation)
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { throw RenderingError.commandFailed }
            var result = [UInt8](repeating: 0, count: count * 4)
            result.withUnsafeMutableBytes { bytes in
                target.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            withExtendedLifetime((frame, target, command)) {}
            return result
    }

    /// Encoding is short. The completion retains source pixels and GPU resources;
    /// success is delivered by the drawable's actual presentation callback.
    public func draw(_ frame: UploadedPixelFrame, drawable: any CAMetalDrawable,
                     transform: ViewportTransform, window: VoiWindow?, userInvert: Bool,
                     interpolation: PixelInterpolation = .linear,
                     event: (@Sendable (DrawableRenderEvent) -> Void)? = nil,
                     completion: @escaping @Sendable (Bool) -> Void) throws {
        guard let command = queue.makeCommandBuffer() else { throw RenderingError.allocationFailed }
        try encode(frame, target: drawable.texture, command: command, pipeline: bgraPipeline,
                   transform: transform, window: window, userInvert: userInvert, interpolation: interpolation)
        let latch = PresentationLatch(completion)
        drawable.addPresentedHandler { presented in
            withExtendedLifetime(frame) {
                if presented.presentedTime > 0 {
                    event?(.presented)
                    latch.finish(true)
                } else {
                    // A skipped drawable is neither a GPU error nor an actual
                    // presentation. A loading viewport keeps drawing to retry.
                    event?(.skipped)
                }
            }
        }
        command.addCompletedHandler { completed in
            withExtendedLifetime((frame, drawable)) {
                if completed.status != .completed { latch.finish(false) }
                event?(completed.status == .completed ? .gpuCompleted : .gpuFailed)
            }
        }
        command.present(drawable)
        command.commit()
        event?(.submitted)
    }

    private func encode(_ frame: UploadedPixelFrame, target: any MTLTexture,
                        command: any MTLCommandBuffer, pipeline: any MTLRenderPipelineState,
                        transform: ViewportTransform, window: VoiWindow?, userInvert: Bool,
                        interpolation: PixelInterpolation) throws {
        let display = frame.owned.display
        let selected = window ?? display.defaultWindow
        let gray = frame.owned.info.pixelFormat == .grayF32LE
        var center: Float = 0, centerLow: Float = 0, width: Float = 1, function: Float = 1
        if let selected, gray {
            guard selected.center.isFinite, selected.width.isFinite,
                  selected.width > 0, selected.function != .linear || selected.width >= 1 else {
                throw RenderingError.invalidDisplay
            }
            center = Float(selected.center)
            width = Float(selected.function == .linear ? selected.width - 1 : selected.width)
            centerLow = Float(selected.center - Double(center))
            guard center.isFinite, centerLow.isFinite, width.isFinite,
                  selected.function == .linear && selected.width == 1 ? width == 0 : width > 0 else {
                throw RenderingError.invalidDisplay
            }
            switch selected.function { case .linear: function = 0; case .linearExact: function = 1; case .sigmoid: function = 2 }
        }
        let scale = Double(target.width) / transform.viewWidth
        let sy = Double(target.height) / transform.viewHeight
        let scaleX = Float(transform.zoom * scale)
        let scaleY = Float(transform.zoom * transform.aspect * sy)
        let panX = Float(transform.pan.x), panY = Float(transform.pan.y)
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
              panX.isFinite, panY.isFinite else { throw RenderingError.invalidDisplay }
        var uniforms = ShaderUniforms(
            dimensions: SIMD4(Float(frame.owned.info.width), Float(frame.owned.info.height), Float(target.width), Float(target.height)),
            mapping: SIMD4(scaleX, scaleY, panX, panY),
            window: SIMD4(center, width, function, centerLow),
            flags: SIMD4(gray ? 1 : 0, frame.owned.info.maskLen > 0 ? 1 : 0,
                         interpolation == .linear ? 1 : 0, gray && (display.inverted != userInvert) ? 1 : 0)
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderingError.commandFailed }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frame.pixels, index: 0); encoder.setFragmentTexture(frame.mask, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms { float4 dimensions; float4 mapping; float4 window; uint4 flags; };
    vertex float4 frame_vertex(uint id [[vertex_id]]) {
        const float2 positions[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
        return float4(positions[id], 0, 1);
    }
    fragment float4 frame_fragment(float4 position [[position]],
        texture2d<float, access::read> pixels [[texture(0)]],
        texture2d<uint, access::read> mask [[texture(1)]], constant Uniforms &u [[buffer(0)]]) {
        float2 size = u.dimensions.xy;
        float2 p = (position.xy - u.dimensions.zw * 0.5) / u.mapping.xy
                   + (size - 1.0) * 0.5 - u.mapping.zw;
        if (any(p < -0.5) || any(p >= size - 0.5)) return float4(0,0,0,1);
        int2 nearest = clamp(int2(floor(p + 0.5)), int2(0), int2(size)-1);
        if (u.flags.y && mask.read(uint2(nearest)).r == 0) return float4(0,0,0,1);
        float4 sample = pixels.read(uint2(nearest));
        if (u.flags.z) {
            int2 lo = int2(floor(p)); float2 frac = p - float2(lo);
            float4 sum = float4(0); float total = 0;
            for (int y=0; y<2; y++) for (int x=0; x<2; x++) {
                int2 q = clamp(lo + int2(x,y), int2(0), int2(size)-1);
                float w = (x ? frac.x : 1-frac.x) * (y ? frac.y : 1-frac.y);
                if (!u.flags.y || mask.read(uint2(q)).r != 0) { sum += pixels.read(uint2(q))*w; total += w; }
            }
            if (total <= 0) return float4(0,0,0,1);
            sample = sum / total;
        }
        if (!u.flags.x) return float4(sample.rgb, 1);
        float d = (sample.r - u.window.x) - u.window.w;
        float v;
        if (u.window.z < 0.5) v = u.window.y == 0.0 ? (d > -0.5 ? 1.0 : 0.0)
            : clamp((d + 0.5)/u.window.y+0.5, 0.0, 1.0);
        else if (u.window.z < 1.5) v = clamp(d/u.window.y+0.5, 0.0, 1.0);
        else {
            float n = isfinite(d) ? d/u.window.y
                : (sample.r/u.window.y-u.window.x/u.window.y)-u.window.w/u.window.y;
            v = 1.0/(1.0+exp(-n*4.0));
        }
        if (u.flags.w) v = 1.0-v;
        return float4(v,v,v,1);
    }
    """
}

private final class PresentationLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let completion: @Sendable (Bool) -> Void
    init(_ completion: @escaping @Sendable (Bool) -> Void) { self.completion = completion }
    func finish(_ success: Bool) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true; lock.unlock()
        completion(success)
    }
}
