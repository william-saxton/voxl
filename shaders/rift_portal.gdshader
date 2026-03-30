shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 void_color : source_color = vec4(0.05, 0.0, 0.1, 1.0);
uniform vec4 star_color_dim : source_color = vec4(0.4, 0.3, 0.7, 1.0);
uniform vec4 star_color_bright : source_color = vec4(0.9, 0.7, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.6, 0.2, 0.9, 1.0);
uniform float edge_glow_intensity : hint_range(0.5, 8.0) = 3.0;
uniform float star_density : hint_range(10.0, 200.0) = 80.0;
uniform float star_twinkle_speed : hint_range(0.5, 5.0) = 2.0;
uniform float scroll_speed : hint_range(0.0, 0.5) = 0.05;
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float distortion_strength : hint_range(0.0, 0.15) = 0.04;
uniform float uv_scale : hint_range(0.1, 10.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// --- Noise helpers ---

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}

// --- Star field ---

float stars(vec2 uv, float density, float time) {
	float brightness = 0.0;
	vec2 cell = floor(uv * density);
	vec2 cell_uv = fract(uv * density);

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 id = cell + neighbor;

			vec2 star_pos = vec2(hash(id), hash2(id));
			float d = length(cell_uv - neighbor - star_pos);

			float star_size = hash(id * 7.77) * 0.015 + 0.003;

			float twinkle = sin(time * star_twinkle_speed * (hash(id * 3.33) * 2.0 + 1.0)
			                    + hash(id * 5.55) * 6.283) * 0.5 + 0.5;

			float star_chance = step(0.65, hash(id * 13.37));

			float star = smoothstep(star_size, 0.0, d) * star_chance;
			star *= mix(0.3, 1.0, twinkle);

			brightness += star;
		}
	}

	return brightness;
}

// --- World-space projection ---
// Pick the best 2D plane based on which axis the face normal is strongest on.

vec2 get_world_uv(vec3 wp, vec3 normal) {
	vec3 abs_n = abs(normal);
	if (abs_n.y > abs_n.x && abs_n.y > abs_n.z) {
		// Horizontal face — project onto XZ
		return wp.xz;
	} else if (abs_n.x > abs_n.z) {
		// X-facing — project onto ZY
		return wp.zy;
	} else {
		// Z-facing — project onto XY
		return wp.xy;
	}
}

void fragment() {
	float time = TIME;

	// World-space UVs — seamless across all portal voxel faces
	vec2 wuv = get_world_uv(world_pos, NORMAL) * uv_scale;

	// Slight animated distortion at the edges of reality
	vec2 distorted = wuv + vec2(
		sin(wuv.y * 12.0 + time * 1.8) * distortion_strength,
		cos(wuv.x * 12.0 + time * 1.3) * distortion_strength
	);

	// --- Starfield ---

	vec2 star_uv = distorted + vec2(time * scroll_speed * 0.3, time * scroll_speed);

	// Two layers for parallax depth
	float star_layer1 = stars(star_uv, star_density, time);
	float star_layer2 = stars(star_uv * 0.5 + vec2(43.7, 91.2), star_density * 0.5, time * 0.7);

	// --- Nebula ---

	vec2 nebula_uv = distorted * 3.0 + vec2(time * 0.02, time * 0.03);
	float nebula = fbm(nebula_uv) * nebula_intensity;

	// Compose interior
	vec3 interior = void_color.rgb;
	interior += vec3(0.3, 0.1, 0.5) * nebula;
	interior += vec3(0.15, 0.0, 0.25) * fbm(nebula_uv * 1.5 + vec2(100.0));
	interior = mix(interior, star_color_dim.rgb, star_layer2 * 0.6);
	interior = mix(interior, star_color_bright.rgb, star_layer1);

	// --- Edge glow ---
	// Exposed voxel faces at the portal boundary naturally face outward.
	// Use the view angle to add glow — faces viewed at grazing angles
	// (portal edges) glow brighter, giving the tear its border.

	float facing = abs(dot(NORMAL, VIEW));
	// Grazing faces glow, head-on faces show the void
	float edge = 1.0 - facing;
	edge = pow(edge, 2.0);

	float edge_flicker = sin(time * 4.0 + world_pos.y * 15.0) * 0.3 + 0.7;
	vec3 glow = edge_color.rgb * edge * edge_glow_intensity * edge_flicker;

	// --- Final ---

	vec3 final_color = interior + glow;

	ALBEDO = final_color;
	EMISSION = final_color * 1.5;
}
