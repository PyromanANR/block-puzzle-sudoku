shader_type canvas_item;

uniform float u_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_time = 0.0;
uniform float u_vertical : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 uv = UV;
    if (u_vertical > 0.5) {
        uv = vec2(UV.y, UV.x); // rotate 90 degrees in shader
    }

    vec4 base = texture(TEXTURE, uv);
    float pulse = 0.5 + 0.5 * sin(u_time * 18.0 + uv.y * 22.0);
    float strip = smoothstep(0.35, 0.8, pulse) * clamp(u_strength, 0.0, 1.0);

    vec3 electric = vec3(0.65, 0.85, 1.0) * strip;
    vec3 rgb = base.rgb + electric;

    // Keep alpha from texture, but ensure some visibility when strip is active.
    float a = max(base.a, strip * 0.6);
    COLOR = vec4(rgb, a);
}
