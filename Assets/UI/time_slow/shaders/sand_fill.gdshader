shader_type canvas_item;

uniform float u_fill : hint_range(0.0, 1.0) = 0.0;

/*
We sample FROM THE FULL ATLAS, but restrict sampling to a sub-region:
u_region_uv = vec4(offset_uv_x, offset_uv_y, size_uv_x, size_uv_y)
This lets us tile ONLY the sand region, not the whole atlas.
*/

uniform sampler2D u_atlas_tex : repeat_enabled, filter_linear;
uniform vec4 u_region_uv = vec4(0.0, 0.0, 1.0, 1.0); // offset.xy, size.zw in UV

uniform float u_tile_scale = 6.0;
uniform float u_fall_speed = 0.55;
uniform float u_boundary_band = 0.06;
uniform float u_sand_alpha = 1.0;
uniform float u_shimmer = 0.10;

vec4 sample_region_tiled(vec2 uv, vec2 tile_uv) {
	// tile_uv is the UV inside the region (0..1 repeating)
	vec2 r_uv = u_region_uv.xy + fract(tile_uv) * u_region_uv.zw;
	return texture(u_atlas_tex, r_uv);
}

void fragment() {
	vec2 uv = UV;

	// Fill from bottom to top
	float edge = 1.0 - clamp(u_fill, 0.0, 1.0);
	float fill_mask = step(edge, uv.y);

	// Base tiled coordinates inside region
	vec2 tile_uv = uv * u_tile_scale;

	vec4 sand = sample_region_tiled(uv, tile_uv);

	// Falling band near boundary
	float band_mask = 1.0 - smoothstep(edge, edge + u_boundary_band, uv.y);
	band_mask *= fill_mask;

	float t = TIME;

	// Animated tile coords for falling effect
	vec2 fall_tile_uv = tile_uv;
	fall_tile_uv.y += t * u_fall_speed * u_tile_scale;
	fall_tile_uv.x += sin(t * 3.1 + uv.y * 25.0) * 0.015 * u_tile_scale;

	vec4 falling_sand = sample_region_tiled(uv, fall_tile_uv);

	vec4 final_sand = mix(sand, falling_sand, band_mask);

	float shimmer = (sin(t * 4.2 + uv.y * 22.0 + uv.x * 13.0) * 0.5 + 0.5) * u_shimmer;
	final_sand.rgb *= (1.0 + shimmer);

	final_sand.a *= fill_mask * u_sand_alpha;

	COLOR = final_sand;
}