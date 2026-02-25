shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    float a = clamp(u_strength, 0.0, 1.0);
    COLOR = vec4(1.0, 1.0, 1.0, a);
}
