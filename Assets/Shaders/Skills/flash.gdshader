shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 flash = vec3(1.0);
	vec3 rgb = mix(base.rgb, flash, clamp(u_strength, 0.0, 1.0));
	COLOR = vec4(rgb, base.a);
}
