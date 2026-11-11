#version 440
// AetherOS depth-map parallax.
//
// Each pixel is displaced by (depth - focus) * offset, where `offset` is
// the eased pointer position and depth comes from a grey-scale map
// (white = near). Near objects move against the pointer more than far
// ones, which reads as real depth. Two refinement taps along the offset
// reduce the "rubber sheet" smearing at depth edges. The image is drawn
// slightly zoomed (`zoom`) so displaced edges never reveal the border.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 offset;     // -1..1, eased pointer position relative to the centre
    float strength;  // max displacement as a fraction of the image (0-0.05)
    float focalDepth; // depth that stays still, 0-1 (not "focus": a FINAL Item property)
    float zoom;      // >= 1
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D depthMap;

void main() {
    vec2 uv = (qt_TexCoord0 - 0.5) / zoom + 0.5;
    vec2 shift = -offset * strength;
    float d = texture(depthMap, uv).r;
    vec2 p = uv + shift * (d - focalDepth);
    // Refine: sample depth where we actually landed (cheap occlusion fix).
    for (int i = 0; i < 2; i++) {
        d = texture(depthMap, p).r;
        p = uv + shift * (d - focalDepth);
    }
    fragColor = texture(source, clamp(p, vec2(0.001), vec2(0.999))) * qt_Opacity;
}
