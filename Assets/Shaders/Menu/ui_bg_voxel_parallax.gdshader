shader_type canvas_item;
render_mode unshaded;

// Tune per emitter (make 2 emitters for parallax: bg and fg).
uniform float layer_depth : hint_range(0.0, 1.0) = 0.35; // 0=far, 1=near
uniform float parallax_strength : hint_range(0.0, 0.05) = 0.015;

// "Voxel-ish" look
uniform float pixel_snap : hint_range(0.0, 8.0) = 2.0;   // 0 disables, >0 snaps UV to texel grid
uniform float blur_strength : hint_range(0.0, 2.0) = 0.55; // 0 disables
uniform float glow_boost : hint_range(0.0, 1.5) = 0.35;    // mild brightening

// Subtle animated drift (keeps it alive even if particle motion is slow)
uniform vec2 uv_drift = vec2(0.0, 0.015);

vec4 sample_voxel(sampler2D tex, vec2 uv, vec2 texel) {
    // Optional pixel snap to make it feel more "voxel/pixel"
    if (pixel_snap > 0.0) {
        vec2 snapped_texel = texel * max(pixel_snap, 1.0);
        uv = floor(uv / snapped_texel) * snapped_texel + snapped_texel * 0.5;
    }

    // Cheap blur: 5 taps. Keep low for performance.
    vec4 c = texture(tex, uv);
    if (blur_strength <= 0.0) return c;

    float b = blur_strength * (0.35 + (1.0 - layer_depth) * 0.65); // blur more for far layer
    vec2 o = texel * (2.0 + 6.0 * b);

    vec4 sum = c * 0.40;
    sum += texture(tex, uv + vec2( o.x, 0.0)) * 0.15;
    sum += texture(tex, uv + vec2(-o.x, 0.0)) * 0.15;
    sum += texture(tex, uv + vec2(0.0,  o.y)) * 0.15;
    sum += texture(tex, uv + vec2(0.0, -o.y)) * 0.15;

    return sum;
}

void fragment() {
    vec2 uv = UV;
    vec2 tex_size = vec2(textureSize(TEXTURE, 0));
    vec2 texel = 1.0 / max(tex_size, vec2(1.0));

    // Parallax-like UV drift (small!). Near layer drifts more.
    float p = parallax_strength * layer_depth;
    uv += uv_drift * TIME * p;

    vec4 tex = sample_voxel(TEXTURE, uv, texel);

    // Mild "premium" lift: brighten a bit + keep alpha
    vec3 rgb = tex.rgb;
    rgb = mix(rgb, rgb * (1.0 + glow_boost), 0.35);

    COLOR = vec4(rgb, tex.a) * COLOR;
}
