// World-space grid for greybox geometry, so distance and scale are readable without textures.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(0.35, 0.35, 0.35, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.025;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	vec2 dist = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float line = step(min(dist.x, dist.y), line_width);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 0.85;
}
