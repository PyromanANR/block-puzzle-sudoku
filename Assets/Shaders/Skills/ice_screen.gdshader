shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 u_tint : source_color = vec4(0.80, 0.92, 1.00, 1.0);
uniform float u_edge_width : hint_range(0.05, 0.45) = 0.22;
uniform float u_crystal_scale : hint_range(20.0, 220.0) = 110.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float dist_to_edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge = 1.0 - smoothstep(0.0, u_edge_width, dist_to_edge);

	float n1 = value_noise(UV * u_crystal_scale);
	float n2 = value_noise(UV * (u_crystal_scale * 0.47) + vec2(8.1, 2.9));
	float crystal = clamp(n1 * 0.7 + n2 * 0.3, 0.0, 1.0);
	float crystal_mask = smoothstep(0.45, 0.92, crystal);

	float haze = edge * (0.45 + 0.55 * crystal_mask);
	float intensity = clamp(u_strength, 0.0, 1.0);
	float overlay_alpha = haze * 0.75 * intensity;

	vec3 icy_color = mix(base.rgb, u_tint.rgb, 0.55 + 0.35 * crystal_mask);
	vec3 final_rgb = mix(base.rgb, icy_color, overlay_alpha);
	float final_alpha = clamp(base.a * (0.45 + 0.55 * intensity), 0.0, 1.0);

	COLOR = vec4(final_rgb, final_alpha);
}
