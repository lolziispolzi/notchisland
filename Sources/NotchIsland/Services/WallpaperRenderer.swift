import Foundation
import MetalKit

/// Values the shader reads each frame. Layout must match `Uniforms` in the shader.
struct WallpaperUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var beat: Float
    var level: Float
    var scene: Int32
    var padding: SIMD2<Float> = .zero
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
}

/// What the app feeds the renderer each frame.
struct WallpaperInputs {
    var scene: Int32
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    /// Loudness, 0…1.
    var level: Float
    /// 1 right on a beat, fading to 0.
    var beat: Float
}

enum WallpaperError: Error {
    case noCommandQueue
    case missingFunction
}

/// Draws the live wallpaper with Metal: one full-screen triangle and a fragment shader.
/// The shader is compiled from source at run time, so the app needs no Metal build step.
final class WallpaperRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Called on the main thread before each frame.
    var provider: (@MainActor () -> WallpaperInputs)?

    /// Animation time. Advances faster when the music is louder, so motion follows energy.
    private var phase: Double = 0
    private var lastFrame = CFAbsoluteTimeGetCurrent()

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let queue = device.makeCommandQueue() else { throw WallpaperError.noCommandQueue }
        let library = try device.makeLibrary(source: WallpaperShader.source, options: nil)
        guard let vertex = library.makeFunction(name: "wallpaper_vertex"),
              let fragment = library.makeFunction(name: "wallpaper_fragment")
        else { throw WallpaperError.missingFunction }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        self.queue = queue
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // MTKView calls this on the main thread.
        MainActor.assumeIsolated {
            guard let provider,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
            else { return }

            let inputs = provider()
            let now = CFAbsoluteTimeGetCurrent()
            let delta = min(now - lastFrame, 0.1)
            lastFrame = now
            phase += delta * Double(0.5 + 0.9 * inputs.level)
            if phase > 10_000 { phase = 0 }

            var uniforms = WallpaperUniforms(
                resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                time: Float(phase),
                beat: inputs.beat,
                level: inputs.level,
                scene: inputs.scene,
                colorA: inputs.colorA,
                colorB: inputs.colorB
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WallpaperUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

enum WallpaperShader {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut wallpaper_vertex(uint vid [[vertex_id]]) {
        float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VertexOut out;
        out.position = float4(corners[vid], 0.0, 1.0);
        out.uv = corners[vid] * 0.5 + 0.5;
        return out;
    }

    struct Uniforms {
        float2 resolution;
        float time;
        float beat;
        float level;
        int scene;
        float2 padding;
        float4 colorA;
        float4 colorB;
    };

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float valueNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    static float fbm(float2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        for (int i = 0; i < 5; i++) {
            value += amplitude * valueNoise(p);
            p = p * 2.02 + float2(3.1, 1.7);
            amplitude *= 0.5;
        }
        return value;
    }

    // Thin lines where `value * density` crosses whole numbers.
    static float contourLines(float value, float density) {
        float f = fract(value * density);
        float d = min(f, 1.0 - f);
        return 1.0 - smoothstep(0.02, 0.09, d);
    }

    // Curtains of light. `sky` is 0 at the horizon, 1 at the top.
    static float3 aurora(float x, float sky, float t, float energy, float3 a, float3 b) {
        float3 color = float3(0.0);
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float wave = fbm(float2(x * 2.2 + fi * 4.0 + t * 0.04 * (fi + 1.0), t * 0.07 + fi * 2.0));
            float base = 0.18 + 0.16 * wave + fi * 0.05;
            float h = sky - base;
            float curtain = smoothstep(-0.015, 0.015, h) * exp(-max(h, 0.0) * (6.0 - 3.0 * energy));
            float rays = 0.55 + 0.45 * valueNoise(float2(x * 90.0 + fi * 13.0, t * 0.4 + fi));
            float3 tint = mix(a, b, clamp(fi * 0.45 + 0.25 * sin(t * 0.2 + x * 3.0), 0.0, 1.0));
            color += tint * curtain * rays * (0.25 + 0.6 * energy);
        }
        return color;
    }

    fragment float4 wallpaper_fragment(VertexOut vin [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = vin.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float t = u.time;
        float energy = clamp(0.3 + 0.7 * u.level, 0.0, 1.0);
        float beat = clamp(u.beat, 0.0, 1.0);
        float3 a = u.colorA.rgb;
        float3 b = u.colorB.rgb;
        float3 color = float3(0.0);

        if (u.scene == 0) {
            // Aurora Lake: aurora above the horizon, rippling contour water below.
            float horizon = 0.42;
            if (uv.y >= horizon) {
                float sky = (uv.y - horizon) / (1.0 - horizon);
                color = aurora(uv.x, sky, t, energy, a, b);
                color += float3(0.0, 0.01, 0.03) * sky;
                color *= 1.0 + 0.5 * beat;
            } else {
                float depth = horizon - uv.y;
                float z = 1.0 / (depth + 0.03);
                float2 p = float2((uv.x - 0.5) * aspect * z * 0.35, z * 0.35 + t * 0.15);
                float d = length(float2((uv.x - 0.5) * aspect, (uv.y - 0.12) * 2.5));
                float ripple = 0.12 * sin(d * 30.0 - t * 4.0) * (0.3 + beat) * exp(-d * 1.2);
                float field = fbm(p * 0.6) + ripple;
                float lines = contourLines(field, 12.0);
                float nearHorizon = 1.0 - smoothstep(0.0, 0.12, depth);
                float3 water = float3(0.78, 0.80, 0.92) * (0.45 + 0.55 * energy);
                float3 reflection = mix(a, b, uv.x) * 0.6;
                color = lines * mix(water, reflection, nearHorizon * 0.7);
                color *= smoothstep(0.0, 0.02, depth);
            }
        } else if (u.scene == 1) {
            // Contours: a topographic map rippling out from the center.
            float2 p = float2(uv.x * aspect, uv.y);
            float d = length(p - float2(0.5 * aspect, 0.5));
            float ripple = 0.15 * sin(d * 25.0 - t * 3.0) * (0.3 + beat) * exp(-d * 1.5);
            float field = fbm(p * 2.5 + float2(t * 0.03, -t * 0.02)) + ripple;
            float lines = contourLines(field, 14.0);
            float3 tint = mix(a, b, smoothstep(0.2, 0.8, field));
            color = tint * lines * (0.4 + 0.6 * energy) * (1.0 + 0.4 * beat);
        } else {
            // Nebula: warped clouds in two colors, with a few stars.
            float2 p = float2(uv.x * aspect, uv.y) * 1.6;
            float2 q = float2(fbm(p + t * 0.05), fbm(p + float2(5.2, 1.3) - t * 0.04));
            float f = fbm(p + 2.5 * q + float2(t * 0.02, 0.0));
            color = mix(a * 0.12, a, smoothstep(0.3, 0.85, f));
            color = mix(color, b, smoothstep(0.5, 1.0, q.x) * 0.7);
            color *= 0.4 + 0.6 * energy + 0.3 * beat;
            float star = hash21(floor(uv * u.resolution / 2.0));
            color += step(0.9985, star) * 0.7;
        }

        float2 v = uv - 0.5;
        color *= 1.0 - dot(v, v) * 0.6;
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }
    """#
}
