// Forest floor for HeightmapTerrain: grass / dry grass / dirt / rock blended by slope and noise,
// plus worn dirt paths. Vertex colour R = path mask, G = clearing mask (both baked by terrain.gd).
// World-space, so it tiles at the same density on any mesh.
shader_type spatial;

uniform vec4 grass_color : source_color = vec4(0.2, 0.3, 0.08, 1.0);
uniform vec4 grass_dry_color : source_color = vec4(0.37, 0.36, 0.15, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.26, 0.19, 0.12, 1.0);
uniform vec4 path_color : source_color = vec4(0.33, 0.27, 0.2, 1.0);
uniform vec4 rock_color : source_color = vec4(0.36, 0.33, 0.28, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Slope (1 - normal.y) where grass gives way to rock.
uniform float rock_slope : hint_range(0.0, 1.0) = 0.27;
uniform float normal_strength = 0.45;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float large = texture(noise_tex, p * 0.011).r;
	float mid = texture(noise_tex, p * 0.045 + vec2(0.31, 0.67)).r;
	float fine = texture(noise_tex, p * 0.37).r;
	float micro = texture(noise_tex, p * 1.9).r;

	// Same dryness noise as grass.gdshader, so clumps match the ground under them.
	vec3 grass = mix(grass_color.rgb, grass_dry_color.rgb, smoothstep(0.5, 0.85, large));
	grass *= mix(0.78, 1.12, fine) * mix(0.9, 1.08, micro);
	vec3 dirt = dirt_color.rgb * mix(0.8, 1.15, fine);

	float dirt_w = smoothstep(0.62, 0.74, mid) * 0.7;
	dirt_w = max(dirt_w, COLOR.g * smoothstep(0.45, 0.7, mid + micro * 0.25) * 0.5);
	float path_w = smoothstep(0.3, 0.6, COLOR.r + (mid - 0.5) * 0.45 + (micro - 0.5) * 0.25);
	vec3 col = mix(grass, dirt, dirt_w);
	col = mix(col, path_color.rgb * mix(0.8, 1.1, micro) * mix(0.9, 1.05, fine), path_w);

	// Rock on steep slopes, textured on the two vertical planes.
	vec3 an = abs(world_normal);
	float rock_tex = mix(texture(noise_tex, world_pos.zy * 0.22).r,
		texture(noise_tex, world_pos.xy * 0.22).r, an.z / (an.x + an.z + 0.001));
	float slope = 1.0 - world_normal.y;
	float rock_w = smoothstep(rock_slope, rock_slope + 0.08, slope + (mid - 0.5) * 0.12);
	vec3 rock = rock_color.rgb * mix(0.55, 1.25, rock_tex) * mix(0.9, 1.05, micro);
	col = mix(col, rock, rock_w);

	vec3 nt = texture(normal_tex, p * 0.5).xyz * 2.0 - 1.0;
	float ns = normal_strength * (0.6 + path_w * 0.4 + rock_w);
	vec3 nw = normalize(world_normal + vec3(nt.x, 0.0, nt.y) * ns);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.85, rock_w);
	SPECULAR = 0.3;
}
