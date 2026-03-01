shader_type canvas_item;

uniform float u_reveal : hint_range(0.0, 1.0) = 1.0;
uniform float u_pulse_strength : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec4 sample_col = texture(TEXTURE, UV);
	float reveal_mask = smoothstep(u_reveal - 0.2, u_reveal + 0.2, UV.y);
	float pulse = 1.0 + sin(TIME * 6.0) * u_pulse_strength;
	vec3 rgb = sample_col.rgb * pulse;
	float alpha = sample_col.a * reveal_mask;
	COLOR = vec4(rgb, alpha);
}
