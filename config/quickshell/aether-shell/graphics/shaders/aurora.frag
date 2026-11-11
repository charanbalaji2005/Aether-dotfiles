#version 440
// AetherOS aurora: an ambient animated gradient.
//
// Three colour fields drift on slow, incommensurate sine paths and are
// blended with domain-warped value noise, so the motion never visibly
// loops. `time` is driven only while the surface is visible; the lock
// screen stops it under reduced motion and on battery saver.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;       // seconds
    vec2 size;        // px, for aspect correction
    vec4 base;        // background colour
    vec4 colorA;
    vec4 colorB;
    vec4 colorC;
    float strength;   // 0-1 how much colour over the base
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}

void main() {
    float aspect = size.x / max(size.y, 1.0);
    vec2 uv = qt_TexCoord0 * vec2(aspect, 1.0);
    float t = time * 0.035;

    vec2 warp = vec2(fbm(uv * 1.6 + vec2(t, -t)), fbm(uv * 1.6 + vec2(-t * 0.8, t * 1.3) + 4.0));
    vec2 p = uv + 0.35 * (warp - 0.5);

    vec2 ca = vec2(0.25 * aspect + 0.18 * sin(t * 2.1), 0.30 + 0.12 * cos(t * 1.7));
    vec2 cb = vec2(0.75 * aspect + 0.20 * cos(t * 1.3), 0.45 + 0.15 * sin(t * 2.4));
    vec2 cc = vec2(0.50 * aspect + 0.25 * sin(t * 0.9 + 1.0), 0.85 + 0.10 * cos(t * 1.1));

    float wa = exp(-dot(p - ca, p - ca) * 3.0);
    float wb = exp(-dot(p - cb, p - cb) * 3.2);
    float wc = exp(-dot(p - cc, p - cc) * 2.6);

    vec3 col = base.rgb;
    col = mix(col, colorA.rgb, wa * strength);
    col = mix(col, colorB.rgb, wb * strength);
    col = mix(col, colorC.rgb, wc * strength * 0.8);

    // Vignette + a whisper of dithering against gradient banding.
    vec2 q = qt_TexCoord0 - 0.5;
    col *= 1.0 - 0.35 * dot(q, q) * 2.0;
    col += (hash(qt_TexCoord0 * size) - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
