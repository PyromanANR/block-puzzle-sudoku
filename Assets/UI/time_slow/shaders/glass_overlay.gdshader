shader_type canvas_item;

uniform sampler2D u_glass_tex : source_color, filter_linear;
uniform float u_gloss : hint_range(0.0, 0.3) = 0.10;

void fragment() {
	vec4 base_col = texture(u_glass_tex, UV);
	float highlight = pow(1.0 - abs((UV.y * 2.0) - 1.0), 5.0) * u_gloss;
	COLOR = vec4(base_col.rgb + vec3(highlight), base_col.a);
}
