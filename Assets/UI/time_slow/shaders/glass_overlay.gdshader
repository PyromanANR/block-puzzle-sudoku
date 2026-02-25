shader_type canvas_item;

uniform sampler2D u_atlas_tex : source_color, filter_linear;
uniform vec4 u_region_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform float u_highlight_strength : hint_range(0.0, 1.0) = 0.25;
uniform float u_highlight_width : hint_range(0.01, 0.5) = 0.10;
uniform float u_highlight_speed : hint_range(0.0, 2.0) = 0.20;

void fragment() {
	vec2 atlas_uv = u_region_uv.xy + UV * u_region_uv.zw;
	vec4 glass = texture(u_atlas_tex, atlas_uv);
	float d = UV.x * 0.85 + UV.y * 0.35;
	float c = fract(TIME * u_highlight_speed);
	float stripe = 1.0 - smoothstep(0.0, u_highlight_width, abs(d - c));
	stripe *= clamp(glass.a * 2.0, 0.0, 1.0);
	glass.rgb += vec3(1.0) * stripe * u_highlight_strength;
	COLOR = glass;
}
