shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 centered = UV * 2.0 - vec2(1.0);
	float dist = length(centered);
	float vig = smoothstep(0.5, 1.05, dist) * clamp(u_strength, 0.0, 1.0);
	vec3 rgb = mix(base.rgb, base.rgb * 0.7, vig);
	COLOR = vec4(rgb, base.a);
}
