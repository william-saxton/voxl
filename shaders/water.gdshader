shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.15, 0.35, 0.65, 0.7);
uniform float flow_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.02;
uniform float wave_frequency : hint_range(0.0, 20.0) = 8.0;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.5;

// UV encoding from Voxel Tools VoxelBlockyModelFluid:
//   UV.x = projection axis (0=x, 1=y, 2=z)
//   UV.y = flow state (0-7 = directional, 8 = idle)

varying vec3 local_vertex;

void vertex() {
	local_vertex = VERTEX;
}

vec2 get_flow_direction(float flow_state) {
	int state = int(round(flow_state));
	if (state >= 8) return vec2(0.0);
	float angle = float(state) * 0.785398;
	return vec2(cos(angle), sin(angle));
}

vec2 get_projected_coords(vec3 vertex_pos, float proj_axis) {
	int axis = int(round(proj_axis));
	if (axis == 0) return vertex_pos.zy;
	if (axis == 1) return vertex_pos.xz;
	return vertex_pos.xy;
}

void fragment() {
	vec2 proj_coords = get_projected_coords(local_vertex, UV.x);
	vec2 flow_dir = get_flow_direction(UV.y);

	vec2 animated_uv = proj_coords + flow_dir * TIME * flow_speed;

	float wave = sin(animated_uv.x * wave_frequency + TIME * 2.0) *
	             cos(animated_uv.y * wave_frequency + TIME * 1.5) * wave_amplitude;

	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
	ROUGHNESS = 0.1;
	SPECULAR = specular_strength;
	NORMAL = normalize(vec3(wave * 4.0, 1.0, wave * 4.0));
}
