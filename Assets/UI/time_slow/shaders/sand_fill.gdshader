shader_type canvas_item;

uniform sampler2D u_atlas_tex : source_color, repeat_enable, filter_nearest;
uniform vec4 u_region_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform float u_fill : hint_range(0.0, 1.0) = 0.0;
uniform float u_boundary_band : hint_range(0.0, 0.2) = 0.04;
uniform float u_wave_amp : hint_range(0.0, 0.08) = 0.015;
uniform float u_wave_freq = 16.0;
uniform float u_wave_speed = 1.4;
uniform vec2 u_tile_scale = vec2(1.0, 1.0);

// Pixel/grain controls
uniform float u_pixel_grid : hint_range(16.0, 512.0) = 50.0; // higher = smaller pixels
uniform float u_grain_density : hint_range(0.0, 1.0) = 0.2;  // how many grains
uniform float u_grain_speed : hint_range(0.0, 6.0) = 1.5;     // fall speed
uniform float u_grain_strength : hint_range(0.0, 1.0) = 0.3; // brightness/alpha

float hash21(vec2 p) {
	// small, fast hash
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	// Fill edge (same as your shader)
	float wave = sin((UV.x * u_wave_freq) + (TIME * u_wave_speed)) * u_wave_amp;
	float edge = clamp(u_fill + wave, 0.0, 1.0);

	// mask = 1 in filled area (below "edge"), 0 above
	float mask = step(1.0 - edge, UV.y);

	// Pixelize sampling UV (tiny pixel grid)
	vec2 local_uv = fract(UV * u_tile_scale);
	vec2 pix_uv = floor(local_uv * u_pixel_grid) / u_pixel_grid;

	vec2 atlas_uv = u_region_uv.xy + (pix_uv * u_region_uv.zw);
	vec4 sand_col = texture(u_atlas_tex, atlas_uv);

	// Slight shading near the boundary (keep your look)
	float foam = smoothstep(1.0 - edge - u_boundary_band, 1.0 - edge + u_boundary_band, UV.y);
	sand_col.rgb += vec3(0.07, 0.05, 0.02) * (1.0 - foam);

	// Falling grains ABOVE the fill (pixel dots that fall down)
	// Work in pixel cell space so dots feel pixelated
	vec2 cell = floor(UV * u_pixel_grid);
	float rnd = hash21(cell);

	// One grain per some cells
	float has_grain = step(rnd, u_grain_density);

	// Falling Y position (top -> down)
	float t = fract(TIME * u_grain_speed + hash21(cell + 17.0));
	float grain_y = 1.0 - t;

	// Grain is a tiny horizontal band around grain_y (one pixel tall-ish)
	float py = 1.0 / u_pixel_grid;
	float grain_band = 1.0 - smoothstep(0.0, py, abs(UV.y - grain_y));

	// Only show grains above the current sand surface (above fill line)
	float above_fill = 1.0 - mask;

	float grain = has_grain * grain_band * above_fill;

	// Compose
	float alpha = sand_col.a * mask + grain * u_grain_strength;
	vec3 rgb = sand_col.rgb + vec3(0.10, 0.08, 0.04) * grain * u_grain_strength;

	COLOR = vec4(rgb, alpha);
}
