#version 440
// AetherOS glass material — the "frost" layer drawn over a panel's tint.
//
// Rounded-rect signed distance field (anti-aliased in screen pixels) with:
//   * film grain: static per-pixel hash noise, which is what makes a flat
//     translucent fill read as frosted glass instead of tinted plastic;
//   * a soft specular light that follows `lightPos` (the pointer);
//   * a Fresnel-like rim: brighter at the top edge, fading towards the
//     bottom, so the surface reads as lit from above.
// No time uniform: nothing here animates on its own.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // item size in px
    float radius;       // corner radius in px
    float frost;        // grain amplitude, 0-0.1
    float specular;     // light strength, 0-0.3
    vec2 lightPos;      // 0-1 within the item
    float lightActive;  // 0-1, eased by the item when the pointer enters/leaves
    vec4 rimColor;
    float rim;          // rim strength, 0-1
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    float r = min(radius, 0.5 * min(size.x, size.y));
    float d = sdRoundBox(px - 0.5 * size, 0.5 * size, r);
    float inside = clamp(0.5 - d, 0.0, 1.0);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }

    // Grain: zero-mean, so it adds texture without changing brightness.
    float g = (hash(floor(px)) - 0.5) * 2.0 * frost;

    // Specular: a wide, soft falloff around the light position.
    vec2 dl = (qt_TexCoord0 - lightPos) * vec2(size.x / max(size.y, 1.0), 1.0);
    float spec = specular * lightActive * exp(-dot(dl, dl) * 3.0);

    // Rim: within ~1.5 px of the edge, weighted towards the top.
    float edge = clamp(1.0 - abs(d + 1.0) / 1.5, 0.0, 1.0);
    float topBias = mix(1.0, 0.25, qt_TexCoord0.y);
    float rimA = rim * edge * topBias * rimColor.a;

    // Premultiplied output: white grain + specular + rim add light; negative
    // grain is black with alpha (darkens without tinting).
    vec3 colour = vec3(max(g, 0.0) + spec) + rimColor.rgb * rimA;
    float alpha = max(-g, 0.0) + max(g, 0.0) + spec + rimA;
    fragColor = vec4(colour, clamp(alpha, 0.0, 1.0)) * inside * qt_Opacity;
}
