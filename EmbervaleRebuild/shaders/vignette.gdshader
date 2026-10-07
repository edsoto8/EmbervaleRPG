// Subtle screen-edge darkening (Medium and High presets).
shader_type canvas_item;

uniform float strength = 0.32;
uniform float inner = 0.45;
uniform float outer = 1.05;

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(inner, outer, length(d) * 1.4);
	COLOR = vec4(0.06, 0.03, 0.01, v * strength);
}
