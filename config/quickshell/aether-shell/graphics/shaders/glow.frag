#version 440
// AetherOS edge illumination: a light that travels around a rounded rect.
//
// The ring's brightness is a conic (angular) gradient whose highlight
// rotates with `phase` (0-1). Inside/outside falloff is exponential in
// pixels, so the glow width is independent of the item size. `phase` is
// only animated while the owning surface is focused/active — at rest the
// shader is just a static accent border.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // item size in px (includes `spread` on each side)
    float radius;     // corner radius of the inner shape in px
    float spread;     // px of glow outside the shape
    float thickness;  // px, the bright core of the edge
    float phase;      // 0-1, position of the travelling highlight
    float intensity;  // 0-1
    vec4 colorA;
    vec4 colorB;
};

const float PI = 3.14159265;

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 c = 0.5 * size;
    vec2 half_ = c - vec2(spread);
    float r = min(radius, min(half_.x, half_.y));
    float d = sdRoundBox(px - c, half_, r);

    // Core line on the edge plus an outer halo (nothing drawn inside).
    float core = exp(-pow(abs(d) / max(thickness, 0.5), 2.0));
    float halo = d > 0.0 ? exp(-d / max(spread * 0.45, 0.5)) : 0.0;

    // Angle around the centre, 0-1, highlighted near `phase`.
    float a = atan(px.y - c.y, px.x - c.x) / (2.0 * PI) + 0.5;
    float dist = abs(fract(a - phase + 0.5) - 0.5);       // 0-0.5
    float sweep = 0.35 + 0.65 * exp(-pow(dist / 0.16, 2.0));

    vec4 col = mix(colorA, colorB, smoothstep(0.0, 0.5, dist));
    float alpha = (core * 0.9 + halo * 0.55) * sweep * intensity * col.a;
    fragColor = vec4(col.rgb * alpha, alpha) * qt_Opacity;
}
