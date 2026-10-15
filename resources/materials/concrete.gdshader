// World-space concrete: fine grain and large stains from one noise texture, plus optional
// saw-cut joints. World-space so any box size tiles at the same real-world density.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.45, 0.44, 0.42, 1.0);
uniform vec4 stain_color : source_color = vec4(0.31, 0.3, 0.28, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Texture repeats per metre.
uniform float grain_scale = 0.6;
uniform float stain_scale = 0.06;
uniform float stain_strength : hint_range(0.0, 1.0) = 0.55;
uniform float normal_strength = 0.3;
// Metres between joints along the two in-plane axes (horizontal, then vertical/depth). 0 = none.
uniform vec2 joint_spacing = vec2(4.0, 4.0);
uniform float joint_width = 0.008;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float joint_mask(float coord, float spacing) {
	if (spacing <= 0.0) {
		return 0.0;
	}
	float dist = abs(fract(coord / spacing + 0.5) - 0.5) * spacing;
	float aa = fwidth(coord) * 1.5;
	return 1.0 - smoothstep(joint_width, joint_width + aa, dist);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv;
	vec3 tangent;
	vec3 bitangent;
	if (n.y >= n.x && n.y >= n.z) {
		uv = world_pos.xz;
		tangent = vec3(1.0, 0.0, 0.0);
		bitangent = vec3(0.0, 0.0, 1.0);
	} else if (n.x >= n.z) {
		uv = world_pos.zy;
		tangent = vec3(0.0, 0.0, 1.0);
		bitangent = vec3(0.0, 1.0, 0.0);
	} else {
		uv = world_pos.xy;
		tangent = vec3(1.0, 0.0, 0.0);
		bitangent = vec3(0.0, 1.0, 0.0);
	}

	float grain = texture(noise_tex, uv * grain_scale).r;
	float stain = smoothstep(0.35, 0.75, texture(noise_tex, uv * stain_scale + vec2(0.37, 0.71)).r);
	vec3 albedo = base_color.rgb * mix(0.86, 1.12, grain);
	albedo = mix(albedo, stain_color.rgb, stain * stain_strength);

	float joints = max(joint_mask(uv.x, joint_spacing.x), joint_mask(uv.y, joint_spacing.y));
	albedo *= 1.0 - 0.55 * joints;

	vec3 nt = texture(normal_tex, uv * grain_scale).xyz * 2.0 - 1.0;
	vec3 nw = normalize(world_normal + (tangent * nt.x + bitangent * nt.y) * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	ALBEDO = albedo;
	ROUGHNESS = clamp(roughness_base + (grain - 0.5) * 0.1 + joints * 0.1, 0.0, 1.0);
}
