// Grass clumps drawn with MultiMesh: wind sway (tips move most, with slow gusts), root-to-tip
// colour that matches the terrain's dry patches, and a distance shrink-out so chunk culling
// never pops. Mesh UV.y = 0 at the root, 1 at the tip; vertex colour = per-blade tone.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 root_color : source_color = vec4(0.09, 0.15, 0.04, 1.0);
uniform vec4 tip_color : source_color = vec4(0.36, 0.48, 0.13, 1.0);
uniform vec4 dry_tip_color : source_color = vec4(0.5, 0.48, 0.22, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 wind_direction = vec2(0.94, 0.34);
uniform float wind_strength = 0.16;
uniform float wind_speed = 1.4;
// Set by vegetation.gd from grass_view_distance.
uniform float fade_start = 32.0;
uniform float fade_end = 42.0;

varying float tip;
varying float dryness;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = distance(origin, CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(fade_start, fade_end, dist);
	tip = UV.y;
	float gust = textureLod(noise_tex, origin.xz * 0.012 - wind_direction * TIME * 0.04, 0.0).r;
	float sway = sin(TIME * wind_speed + dot(origin.xz, wind_direction) * 0.3 + VERTEX.x * 3.0) * 0.3
		+ (gust - 0.35) * 1.6;
	vec3 offset = vec3(wind_direction.x, 0.0, wind_direction.y) * sway * wind_strength * tip * tip;
	offset.y = -abs(sway) * wind_strength * 0.3 * tip * tip;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset;
	dryness = textureLod(noise_tex, origin.xz * 0.011, 0.0).r;
}

void fragment() {
	vec3 tip_col = mix(tip_color.rgb, dry_tip_color.rgb, smoothstep(0.5, 0.85, dryness));
	vec3 col = mix(root_color.rgb, tip_col, smoothstep(0.0, 1.0, tip)) * COLOR.r;
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.6;
	// Light blades like the ground they grow from, not like thin cards.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
