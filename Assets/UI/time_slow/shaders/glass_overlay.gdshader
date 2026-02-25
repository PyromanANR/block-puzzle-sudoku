shader_type canvas_item;

uniform sampler2D u_glass_tex : filter_linear;
uniform float u_highlight_strength = 0.18;
uniform float u_highlight_width = 0.10;
uniform float u_highlight_speed = 0.20;

void fragment() {
	vec2 uv = UV;
	vec4 glass = texture(u_glass_tex, uv);

	// subtle moving diagonal highlight
	float t = TIME * u_highlight_speed;
	float d = uv.x * 0.85 + uv.y * 0.35;
	float c = fract(t);
	float stripe = 1.0 - smoothstep(0.0, u_highlight_width, abs(d - c));
	stripe *= glass.a;

	glass.rgb += vec3(1.0) * stripe * u_highlight_strength;

	COLOR = glass;
}