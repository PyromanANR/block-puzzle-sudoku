shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_time = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float pulse = 0.5 + 0.5 * sin(u_time * 18.0 + UV.y * 22.0);
	float strip = smoothstep(0.35, 0.8, pulse) * clamp(u_strength, 0.0, 1.0);
	vec3 electric = vec3(0.65, 0.85, 1.0) * strip;
	vec3 rgb = base.rgb + electric;
	COLOR = vec4(rgb, max(base.a, strip * 0.6));
}
