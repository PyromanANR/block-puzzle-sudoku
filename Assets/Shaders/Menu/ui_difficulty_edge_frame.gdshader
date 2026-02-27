shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.26, 1.0);
uniform float edge_width = 0.16;
uniform float softness = 0.65;
uniform float intensity = 0.16;

void fragment() {
	float dist_to_edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge_start = edge_width * (1.0 - softness);
	float edge_mask = 1.0 - smoothstep(edge_start, edge_width, dist_to_edge);
	COLOR = vec4(glow_color.rgb, edge_mask * intensity);
}
