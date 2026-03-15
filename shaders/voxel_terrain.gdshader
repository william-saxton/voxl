shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float fade_above_y = 100.0;
uniform float fade_range = 2.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	COLOR = COLOR;
}

void fragment() {
	ALBEDO = COLOR.rgb;

	float fade = 1.0 - smoothstep(fade_above_y, fade_above_y + fade_range, world_position.y);

	if (fade < 0.01) {
		discard;
	}

	ALPHA = fade;
}
