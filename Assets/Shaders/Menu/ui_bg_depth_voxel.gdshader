shader_type canvas_item;

uniform float intensity = 0.10;
uniform float block_scale = 48.0;
uniform float vignette = 0.18;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	vec2 grid_uv = floor(uv * block_scale) / max(block_scale, 1.0);
	float cell_noise = hash12(grid_uv * 37.0 + vec2(2.3, 5.7));
	float vertical_grad = smoothstep(0.0, 1.0, uv.y);
	float diagonal_grad = smoothstep(0.0, 1.0, (uv.x + uv.y) * 0.5);
	float depth = mix(vertical_grad, diagonal_grad, 0.35);
	float variation = (cell_noise - 0.5) * 0.12;
	float vig = 1.0 - smoothstep(0.25, 0.95, distance(uv, vec2(0.5)) * 1.4);
	float shade = clamp(depth * 0.6 + variation + vig * vignette * 0.25, 0.0, 1.0);
	float alpha = shade * intensity;
	COLOR = vec4(tint.rgb, alpha * tint.a);
}
