shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform vec4 gas_color : source_color = vec4(0.6, 0.75, 0.15, 0.35);
uniform float drift_speed : hint_range(0.0, 3.0) = 0.8;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;

varying vec3 local_vertex;

void vertex() {
	local_vertex = VERTEX;
}

float hash(vec2 p) {
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

void fragment() {
	vec2 uv = local_vertex.xz * noise_scale;
	uv.y += TIME * drift_speed;

	float n = value_noise(uv) * 0.5 + value_noise(uv * 2.0) * 0.3 + value_noise(uv * 4.0) * 0.2;
	float pulse = sin(TIME * pulse_speed) * 0.1 + 0.9;

	ALBEDO = gas_color.rgb;
	ALPHA = gas_color.a * n * pulse;
	ROUGHNESS = 1.0;
}
