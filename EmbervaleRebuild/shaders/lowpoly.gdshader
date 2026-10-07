// Shared flat-shaded low-poly material. Face normals come from screen-space derivatives, so meshes
// need no duplicated vertices. Batched props (MeshMerger) carry their colour in COLOR.rgb (in this
// renderer a vertex colour renders like the same value in `albedo`, so it is used as-is) and their
// wind weight in COLOR.a (alpha = 1 - weight), so never put other data in vertex alpha.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
// Wind weight for unbatched plant meshes (batched ones use vertex alpha).
uniform float sway = 0.0;
uniform bool anchored = false;
uniform float rim_strength = 0.0;

global uniform float wind_strength;
global uniform float wind_grass_only;

varying float v_sway;

void vertex() {
	float w = use_vertex_color ? (1.0 - COLOR.a) : sway;
	if (!use_vertex_color && anchored) {
		w *= clamp(VERTEX.y * 1.5, 0.0, 1.0);
	}
	// Grass-only wind (Low preset) keeps just the lightest weights moving.
	if (wind_grass_only > 0.5 && w > 0.75) {
		w = 0.0;
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float gust = 0.55 + 0.45 * sin(t * 0.37 + world.x * 0.031) * sin(t * 0.23 + world.z * 0.027);
	float wave = sin(t * 1.9 + world.x * 0.45 + world.z * 0.35) + 0.35 * sin(t * 3.7 + world.z * 0.8);
	vec3 offset = vec3(wave * 0.06, 0.0, wave * 0.035) * w * wind_strength * gust;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	v_sway = w;
}

void fragment() {
	vec3 n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	NORMAL = n;
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	if (rim_strength > 0.0) {
		float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
		EMISSION = c * rim * rim_strength;
	}
}
