// Tree canopies and bushes drawn with MultiMesh. Gentle wind sway that grows with height,
// per-instance tint picked from a hash of the instance position, baked vertex-colour shading
// (darker inside and underneath) and a little back-lighting so leaves glow against the sun.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.13, 0.22, 0.09, 1.0);
uniform vec4 albedo_variation : source_color = vec4(0.18, 0.25, 0.08, 1.0);
uniform float sway_amount = 0.05;
uniform float sway_speed = 0.8;
uniform float backlight = 0.35;

varying vec3 tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float sway = sin(TIME * sway_speed + phase) + 0.4 * sin(TIME * sway_speed * 2.7 + phase * 3.0);
	VERTEX.xz += vec2(sway, sway * 0.5) * sway_amount * h * h * 0.02;
	float hsh = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	tint = mix(albedo.rgb, albedo_variation.rgb, hsh);
}

void fragment() {
	ALBEDO = tint * COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * backlight;
}
