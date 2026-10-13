// Painted corrugated steel for shipping containers, computed in the box's local space so it
// works on a plain CSGBox3D in either orientation. Ribs run vertically on the walls.
shader_type spatial;

uniform vec4 paint_color : source_color = vec4(0.12, 0.25, 0.42, 1.0);
uniform vec4 rust_color : source_color = vec4(0.33, 0.17, 0.08, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.22;
// Metres per corrugation and how strongly the ribs tilt the lighting.
uniform float rib_pitch = 0.28;
uniform float rib_depth = 0.55;
// Box half-height, used to place the top and bottom rails.
uniform float half_height = 1.295;
uniform float rail_size = 0.13;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(local_normal);
	bool wall = n.y < 0.5;
	bool rail = wall && abs(local_pos.y) > half_height - rail_size;

	float u = n.z > n.x ? local_pos.x : local_pos.z;
	vec3 u_axis = n.z > n.x ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
	vec2 uv = wall ? vec2(u, local_pos.y) : local_pos.xz;

	float phase = fract(u / rib_pitch);
	// Fade the ribs out where they'd shimmer (fewer than ~3 pixels per rib).
	float fade = 1.0 - smoothstep(0.25, 0.7, fwidth(u) / rib_pitch);
	float rib_on = (wall && !rail) ? fade : 0.0;
	float slope = clamp(sin(phase * TAU) * 2.0, -1.0, 1.0) * rib_on;
	float trough = (0.5 + 0.5 * cos(phase * TAU)) * rib_on;

	float fine = texture(noise_tex, uv * 0.9).r;
	vec3 paint = paint_color.rgb * mix(0.9, 1.08, fine) * (1.0 - 0.1 * trough);
	if (rail) {
		paint *= 0.82;
	}

	// Patches, plus streaks that run down from the top and pool near the bottom rail.
	float patches = texture(noise_tex, uv * 0.35 + vec2(0.13, 0.57)).r;
	float streaks = texture(noise_tex, vec2(uv.x * 1.6, uv.y * 0.12) + vec2(0.61, 0.29)).r;
	float bottom = 1.0 - smoothstep(-half_height, -half_height + 0.6, local_pos.y);
	float rust_level = patches * 0.6 + streaks * 0.4 + bottom * 0.25;
	float rust = smoothstep(1.0 - rust_amount, 1.0 - rust_amount + 0.07, rust_level);
	vec3 albedo = mix(paint, rust_color.rgb * mix(0.8, 1.15, fine), rust);

	vec3 u_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(u_axis, 0.0)).xyz);
	NORMAL = normalize(NORMAL - u_view * slope * rib_depth);

	ALBEDO = albedo;
	METALLIC = mix(0.25, 0.0, rust);
	ROUGHNESS = mix(0.5, 0.88, rust) + (fine - 0.5) * 0.08;
}
