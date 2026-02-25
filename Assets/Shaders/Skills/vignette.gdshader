shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 centered = UV * 2.0 - vec2(1.0);
    float dist = length(centered);
    float vig = smoothstep(0.55, 1.10, dist) * clamp(u_strength, 0.0, 1.0);

    // Output black overlay with alpha = vignette amount.
    COLOR = vec4(0.0, 0.0, 0.0, vig);
}
