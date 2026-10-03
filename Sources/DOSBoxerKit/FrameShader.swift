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

/// "Sharp bilinear": nearest-neighbour inside each source pixel, with a
/// one-output-pixel blend at the edges. Crisp pixels without uneven sizes
/// when the scale factor isn't a whole number.
fragment float4 frameFragment(VertexOut in [[stage_in]],
                              texture2d<float> frame [[texture(0)]],
                              constant float2& outputSize [[buffer(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

    const float2 sourceSize = float2(frame.get_width(), frame.get_height());
    const float2 texel = in.texCoord * sourceSize;
    const float2 scale = max(outputSize / sourceSize, float2(1.0));

    const float2 texelFloor = floor(texel);
    const float2 fraction = texel - texelFloor;
    const float2 region = 0.5 - 0.5 / scale;
    const float2 centerDistance = fraction - 0.5;
    const float2 adjusted = (centerDistance - clamp(centerDistance, -region, region)) * scale + 0.5;

    return float4(frame.sample(linearSampler, (texelFloor + adjusted) / sourceSize).rgb, 1.0);
}
"""#
