#version 440
// AetherOS wallpaper transitions: blends `source` (old) into `target` (new).
//
// mode: 0 fade · 1 wipe (direction `dir`) · 2 circle reveal from `center`
//       3 dissolve (noise threshold) · 4 blinds · 5 zoom (old pushes in, new settles)
// All modes use a soft edge of width `softness` so the boundary is never a
// hard aliased line. Both textures are already cropped/fitted by their
// Image items; the shader only blends.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;    // 0 = old fully shown, 1 = new fully shown
    float mode;
    float softness;    // 0.01-0.3
    vec2 dir;          // wipe direction (normalised)
    vec2 center;       // circle origin, 0-1
    vec2 size;         // px, for aspect-correct circles
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D target;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    float s = max(softness, 0.001);
    int m = int(mode + 0.5);
    float w;   // weight of the new image

    if (m == 1) {
        vec2 d = normalize(dir);
        // Project onto the direction; remap so the edge sweeps fully across.
        float x = dot(uv - 0.5, d) / (abs(d.x) + abs(d.y)) + 0.5;
        w = 1.0 - smoothstep(p * (1.0 + s) - s, p * (1.0 + s), x);
    } else if (m == 2) {
        float aspect = size.x / max(size.y, 1.0);
        vec2 q = (uv - center) * vec2(aspect, 1.0);
        float far = length(max(abs(center - vec2(0.0)), abs(center - vec2(1.0))) * vec2(aspect, 1.0));
        float r = p * (far + s);
        w = 1.0 - smoothstep(r - s, r, length(q));
    } else if (m == 3) {
        float n = hash(floor(uv * size / 3.0));
        w = smoothstep(n - s, n, p * (1.0 + s));
    } else if (m == 4) {
        float band = fract(uv.y * 12.0);
        w = 1.0 - smoothstep(p * (1.0 + s) - s, p * (1.0 + s), band);
    } else if (m == 5) {
        vec2 uo = (uv - 0.5) / (1.0 + 0.12 * p) + 0.5;           // old drifts towards the viewer
        vec2 un = (uv - 0.5) / (1.0 + 0.08 * (1.0 - p)) + 0.5;   // new settles from slightly large
        vec4 a = texture(source, uo);
        vec4 b = texture(target, un);
        float k = smoothstep(0.0, 1.0, p);
        fragColor = mix(a, b, k) * qt_Opacity;
        return;
    } else {
        w = smoothstep(0.0, 1.0, p);
    }
    fragColor = mix(texture(source, uv), texture(target, uv), w) * qt_Opacity;
}
