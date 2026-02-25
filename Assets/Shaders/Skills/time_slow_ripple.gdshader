shader_type canvas_item;

uniform float u_progress : hint_range(0.0, 1.0) = 0.0;
uniform float u_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 u_center = vec2(0.5, 0.5);

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, u_center);
	float wave_front = u_progress * 0.9;
	float ring_shape = exp(-28.0 * pow(max(dist - wave_front, 0.0), 2.0));
	float ripples = 0.5 + 0.5 * cos((dist - wave_front) * 70.0);
	float envelope = exp(-4.0 * dist) * smoothstep(0.0, 0.08, wave_front);
	float ring = ring_shape * ripples * envelope;
	float alpha = clamp(ring * u_strength, 0.0, 0.65);
	vec3 tint = vec3(0.70, 0.88, 1.00);
	COLOR = vec4(tint * alpha, alpha);
}
