shader_type canvas_item;

uniform sampler2D u_atlas_tex : source_color, repeat_enable, filter_linear;
uniform vec4 u_region_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform float u_fill : hint_range(0.0, 1.0) = 0.0;
uniform float u_boundary_band : hint_range(0.0, 0.2) = 0.04;
uniform float u_wave_amp : hint_range(0.0, 0.08) = 0.015;
uniform float u_wave_freq = 16.0;
uniform float u_wave_speed = 1.4;

void fragment() {
	float wave = sin((UV.x * u_wave_freq) + (TIME * u_wave_speed)) * u_wave_amp;
	float edge = clamp(u_fill + wave, 0.0, 1.0);
	float mask = step(1.0 - edge, UV.y);
	vec2 local_uv = fract(UV);
	vec2 atlas_uv = u_region_uv.xy + (local_uv * u_region_uv.zw);
	vec4 sand_col = texture(u_atlas_tex, atlas_uv);
	float foam = smoothstep(1.0 - edge - u_boundary_band, 1.0 - edge + u_boundary_band, UV.y);
	sand_col.rgb += vec3(0.07, 0.05, 0.02) * (1.0 - foam);
	COLOR = vec4(sand_col.rgb, sand_col.a * mask);
}
