// Sea and pond water. Gentle low-poly waves; colour by depth from a texture baked from the terrain
// (TutorialIsland._bake_water_depth), so no depth-buffer reads are needed in the Compatibility renderer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float level = 0.0;
uniform float wave_height = 0.06;
uniform vec4 shallow_color : source_color = vec4(0.36, 0.72, 0.70, 1.0);
uniform vec4 deep_color : source_color = vec4(0.13, 0.33, 0.52, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 0.95, 1.0);
// Signed depth (metres below the surface, negative over land) in R; sampled over depth_rect.
uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform bool has_depth = false;
uniform vec4 depth_rect = vec4(-64.0, -64.0, 128.0, 128.0);
uniform float max_depth = 3.0;
uniform float foam_amount = 1.0;
uniform float sparkle = 1.0;
// World-space points (xz) where posts stand in the water, for foam rings.
uniform vec4 posts[24];
uniform int post_count = 0;

varying vec3 world_pos;

float depth_at(vec2 xz) {
	if (!has_depth) {
		return max_depth;
	}
	vec2 uv = (xz - depth_rect.xy) / depth_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return max_depth;
	}
	return texture(depth_tex, uv).r * 8.0 - 2.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(world_pos.x * 0.35 + TIME * 1.1) * 0.6 + sin(world_pos.z * 0.27 - TIME * 0.8) * 0.4;
	VERTEX.y += w * wave_height;
	world_pos.y += w * wave_height;
}

void fragment() {
	vec3 n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	NORMAL = n;
	float d = depth_at(world_pos.xz);
	if (has_depth && d < -0.02) {
		discard;
	}
	float t = clamp(d / max_depth, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, t));
	float foam = 0.0;
	if (has_depth) {
		float band = 1.0 - smoothstep(0.0, 0.35, d);
		float ripple = 0.5 + 0.5 * sin(d * 18.0 - TIME * 2.2 + world_pos.x * 0.3);
		foam = band * mix(0.55, 1.0, ripple) * foam_amount;
	}
	for (int i = 0; i < post_count; i++) {
		float pd = distance(world_pos.xz, posts[i].xy);
		float ring = 1.0 - smoothstep(0.18, 0.5 + 0.08 * sin(TIME * 2.0 + float(i)), pd);
		foam = max(foam, ring * 0.85 * foam_amount);
	}
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));
	float glint = pow(max(sin(world_pos.x * 1.7 + TIME * 1.3) * sin(world_pos.z * 1.9 - TIME * 1.1), 0.0), 48.0);
	ALBEDO = col;
	EMISSION = vec3(glint * 0.25 * sparkle);
	ROUGHNESS = 0.45;
	SPECULAR = 0.25;
	ALPHA = mix(0.78, 0.95, t);
}
