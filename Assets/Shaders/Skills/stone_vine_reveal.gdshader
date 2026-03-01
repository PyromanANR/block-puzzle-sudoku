shader_type canvas_item;

uniform float u_reveal : hint_range(0.0, 1.0) = 1.0;        // progress of reveal
uniform float u_softness : hint_range(0.02, 0.40) = 0.18;   // width of reveal edge
uniform float u_alpha : hint_range(0.0, 1.0) = 0.70;        // overall opacity
uniform float u_min_coverage : hint_range(0.0, 1.0) = 0.35; // baseline coverage even before reveal
uniform float u_detail_strength : hint_range(0.0, 2.0) = 1.0; // how much texture details matter
uniform float u_pulse_strength : hint_range(0.0, 1.0) = 0.12;
uniform float u_zoom : hint_range(0.75, 2.50) = 1.15;

void fragment() {
    vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));

    // zoom texture around center (optional)
    vec2 z = (uv - vec2(0.5)) / max(0.001, u_zoom) + vec2(0.5);
    z = clamp(z, vec2(0.0), vec2(1.0));

    vec4 tex = texture(TEXTURE, z);

    // Reveal factor (0..1), but will be remapped to never fully disappear
    float edge0 = u_reveal - u_softness;
    float edge1 = u_reveal + u_softness;
    float reveal01 = smoothstep(edge0, edge1, uv.y);

    // Make sure there's always some coverage so it doesn't feel "missing"
    float coverage = mix(u_min_coverage, 1.0, reveal01);

    float pulse = 1.0 + sin(TIME * 6.0) * u_pulse_strength;

    // Build alpha that doesn't depend heavily on PNG alpha:
    // - base coverage provides full-rect presence
    // - texture alpha only adds detail contrast (scaled)
    float detail_a = clamp(tex.a * u_detail_strength, 0.0, 1.0);
    float a = u_alpha * coverage * mix(1.0, detail_a, 0.65); // 0.65 = "how much" texture alpha influences

    // Color: keep texture RGB (details), but ensure it's visible with coverage
    vec3 rgb = tex.rgb * pulse;

    COLOR = vec4(rgb, a);
}