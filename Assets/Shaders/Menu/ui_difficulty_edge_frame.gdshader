shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.26, 1.0);

// Per-side core thickness (top thinner)
uniform float edge_w_top = 0.006;
uniform float edge_w_sides = 0.006;
uniform float edge_w_bottom = 0.010;

uniform float softness = 0.45;
uniform float intensity = 0.07;

uniform float core_boost = 1.9;
uniform float core_power = 3.0;

// Halo INSIDE (towards game center), close to the edge
uniform float halo_inner = 0.004;   // how close halo starts to edge (smaller = closer)
uniform float halo_width = 0.035;   // how far it goes inward (towards center)
uniform float halo_boost = 1.10;
uniform float halo_power = 1.15;

uniform float halo_tail_width = 0.22;   // long fade distance into center
uniform float halo_tail_boost = 0.15;   // how strong the long fade is
uniform float halo_tail_power = 1.8;    // higher = slower start, smoother tail

// Extra: make TOP halo slightly weaker if you want (optional)
uniform float top_halo_mul = 0.85;

float edge_mask(float d, float edge_w) {
	float edge_start = edge_w * (1.0 - softness);
	return 1.0 - smoothstep(edge_start, edge_w, d);
}

float halo_mask(float d) {
	// 1) Near-edge halo (strong, close)
	float near_h = 1.0 - smoothstep(halo_inner, halo_inner + halo_width, d);
	near_h = pow(clamp(near_h, 0.0, 1.0), halo_power) * halo_boost;

	// 2) Long tail into center (very smooth)
	// Starts near the edge and fades much deeper.
	float tail_end = halo_inner + halo_tail_width;
	float tail_h = 1.0 - smoothstep(halo_inner, tail_end, d);

	// This power makes the fade "start strong then slowly melt"
	tail_h = pow(clamp(tail_h, 0.0, 1.0), halo_tail_power) * halo_tail_boost;

	return near_h + tail_h;
}

void fragment() {
	// Distances to each side
	float d_left = UV.x;
	float d_right = 1.0 - UV.x;
	float d_top = UV.y;
	float d_bottom = 1.0 - UV.y;

	// Core per-side (top is thinner)
	float m_left = edge_mask(d_left, edge_w_sides);
	float m_right = edge_mask(d_right, edge_w_sides);
	float m_top = edge_mask(d_top, edge_w_top);
	float m_bottom = edge_mask(d_bottom, edge_w_bottom);

	// Combine edges (max = strongest edge wins)
	float base = max(max(m_left, m_right), max(m_top, m_bottom));

	// Core
	float core = pow(clamp(base, 0.0, 1.0), core_power) * core_boost;

	// Halo: compute per-side too, then combine (so it hugs edges inward)
	float h_left = halo_mask(d_left);
	float h_right = halo_mask(d_right);
	float h_top = halo_mask(d_top) * top_halo_mul;      // optional: weaker top blur
	float h_bottom = halo_mask(d_bottom);

	float halo = max(max(h_left, h_right), max(h_top, h_bottom));

	float a = (core + halo) * intensity;
	COLOR = vec4(glow_color.rgb * (1.0 + 0.30 * core), a);
}