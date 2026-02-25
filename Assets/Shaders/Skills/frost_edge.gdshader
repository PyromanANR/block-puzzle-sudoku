shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float edge = max(max(1.0 - UV.x, UV.x), max(1.0 - UV.y, UV.y));
	float edge_mask = smoothstep(0.65, 1.0, edge);
	vec3 frost = mix(base.rgb, vec3(0.75, 0.90, 1.0), edge_mask * clamp(u_strength, 0.0, 1.0));
	COLOR = vec4(frost, base.a);
}
