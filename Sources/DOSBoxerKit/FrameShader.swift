// The frame shader, compiled at runtime so building needs no Metal toolchain.
let frameShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// A full-viewport quad from four vertices (triangle strip, no vertex buffer).
/// The renderer sets the viewport to the aspect-correct rectangle.
vertex VertexOut frameVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = { {-1, -1}, {1, -1}, {-1, 1}, {1, 1} };
    const float2 texCoords[4] = { {0, 1}, {1, 1}, {0, 0}, {1, 0} };
    VertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    out.texCoord = texCoords[vertexID];
    return out;
}

struct FrameUniforms {
    float2 outputSize;   // pixels being drawn
};

/// "Sharp bilinear": nearest-neighbor inside each source pixel, with a
/// one-output-pixel blend at the edges. Crisp pixels without uneven sizes
/// when the scale factor isn't a whole number.
static float4 sharpSample(texture2d<float> frame, float2 uv, float2 outputSize) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    const float2 sourceSize = float2(frame.get_width(), frame.get_height());
    const float2 texel = uv * sourceSize;
    const float2 scale = max(outputSize / sourceSize, float2(1.0));
    const float2 texelFloor = floor(texel);
    const float2 fraction = texel - texelFloor;
    const float2 region = 0.5 - 0.5 / scale;
    const float2 centerDistance = fraction - 0.5;
    const float2 adjusted = (centerDistance - clamp(centerDistance, -region, region)) * scale + 0.5;
    return frame.sample(linearSampler, (texelFloor + adjusted) / sourceSize);
}

/// Darkens the gaps between a CRT's scanlines. `strength` 0–1.
static float scanline(float2 uv, float sourceHeight, float strength) {
    const float position = fract(uv.y * sourceHeight);
    const float beam = 0.5 + 0.5 * cos(6.2831853 * (position - 0.5));
    return mix(1.0 - strength, 1.0, beam);
}

/// A vertical RGB aperture-grille mask, one triad per three output pixels.
static float3 apertureMask(float2 position, float strength) {
    const int column = int(position.x) % 3;
    float3 mask = float3(1.0 - strength);
    mask[column] = 1.0;
    return mask;
}

fragment float4 crispFragment(VertexOut in [[stage_in]],
                              texture2d<float> frame [[texture(0)]],
                              constant FrameUniforms& uniforms [[buffer(0)]]) {
    return float4(sharpSample(frame, in.texCoord, uniforms.outputSize).rgb, 1.0);
}

fragment float4 smoothFragment(VertexOut in [[stage_in]],
                               texture2d<float> frame [[texture(0)]],
                               constant FrameUniforms& uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    return float4(frame.sample(linearSampler, in.texCoord).rgb, 1.0);
}

fragment float4 arcadeFragment(VertexOut in [[stage_in]],
                               texture2d<float> frame [[texture(0)]],
                               constant FrameUniforms& uniforms [[buffer(0)]]) {
    float3 color = sharpSample(frame, in.texCoord, uniforms.outputSize).rgb;
    color *= scanline(in.texCoord, frame.get_height(), 0.45);
    color *= apertureMask(in.position.xy, 0.25);
    // Win back the brightness the scanlines and mask take away
    return float4(saturate(color * 1.45), 1.0);
}

fragment float4 tvFragment(VertexOut in [[stage_in]],
                           texture2d<float> frame [[texture(0)]],
                           constant FrameUniforms& uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

    // Curved glass: push the picture outward from the center
    float2 centered = in.texCoord * 2.0 - 1.0;
    centered *= 1.0 + 0.045 * dot(centered.yx, centered.yx);
    const float2 uv = centered * 0.5 + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0)) {
        return float4(0, 0, 0, 1);
    }

    // A soft beam: blend each pixel a little with its neighbors
    const float2 texelSize = 1.0 / float2(frame.get_width(), frame.get_height());
    float3 color = frame.sample(linearSampler, uv).rgb * 0.6
                 + frame.sample(linearSampler, uv + float2(texelSize.x, 0)).rgb * 0.2
                 + frame.sample(linearSampler, uv - float2(texelSize.x, 0)).rgb * 0.2;
    color *= scanline(uv, frame.get_height(), 0.3);
    color *= apertureMask(in.position.xy, 0.12);

    // Darker toward the edges, and rounded corners
    const float2 edge = uv * (1.0 - uv);
    const float vignette = pow(edge.x * edge.y * 16.0, 0.25);
    const float2 corner = abs(centered) - (1.0 - 0.06);
    const float rounded = 1.0 - smoothstep(0.0, 0.02, length(max(corner, 0.0)) - 0.0);
    return float4(saturate(color * 1.35 * vignette * rounded), 1.0);
}
"""#
