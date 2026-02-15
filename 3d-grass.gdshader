shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

group_uniforms Shape_and_Color;
uniform vec4 color_top : source_color = vec4(0.667, 0.922, 0.431, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.651, 0.282, 0.0, 1.0);
uniform vec3 color_variation : source_color = vec3(0.9, 0.9, 0.2);
uniform float blade_height_taper = 2.0;
uniform float blade_width = 1.0;
uniform float blade_bend = 0.5;
uniform float patch_scale = 5.0;
uniform bool billboard_mode = false;

group_uniforms Wind_Settings;
uniform sampler2D wind_noise : hint_default_white;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_texture_scale = 20.0; // Huge clouds
uniform float wind_speed = 0.1;
uniform float still_sway_speed = 4.5; // Slower, deeper breath
uniform float still_sway_strength = 0.1; // BARELY moves. 0.0 = statue.
uniform float gust_strength = 1.0; // The power of the wave
uniform float gust_frequency = 0.08; // Higher = Rarier gusts (0.5 is 50/50, 0.8 is rare)

group_uniforms Interaction;
uniform vec3 player_position = vec3(0.0);
uniform float interaction_radius = 1.0;
uniform float interaction_push = 1.0;

varying float v_wind_intensity;
varying float v_patch;
varying float v_height;

void vertex() {
// SETUP ROTATION
vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
vec3 camera_world = INV_VIEW_MATRIX[3].xyz;
vec3 dir_to_cam_world = normalize(camera_world - world_pos);
dir_to_cam_world.y = 0.0;
dir_to_cam_world = normalize(dir_to_cam_world);

vec3 dir_to_cam_model = mat3(inverse(MODEL_MATRIX)) * dir_to_cam_world;

if (length(dir_to_cam_model.xz) < 0.001) {
	dir_to_cam_model.z = 1.0;
}

dir_to_cam_model = normalize(dir_to_cam_model);

vec3 right_model = normalize(cross(vec3(0.0, 1.0, 0.0), dir_to_cam_model));
vec3 forward_model = cross(right_model, vec3(0.0, 1.0, 0.0));

mat3 billboard_rot = mat3(right_model, vec3(0.0, 1.0, 0.0), forward_model);

vec3 vertex_pos = VERTEX;
vec3 object_right_vector;
vec3 object_forward_vector;

if (billboard_mode) {
	vertex_pos = billboard_rot * vertex_pos;
	NORMAL = billboard_rot * NORMAL;
	object_right_vector = right_model;
	object_forward_vector = forward_model;
} else {
	object_right_vector = vec3(1.0, 0.0, 0.0);
	object_forward_vector = vec3(0.0, 0.0, 1.0);
}

// Variation patch factor
float patch_factor = texture(wind_noise, world_pos.xz / patch_scale).r;
v_patch = patch_factor;
v_height = UV.y;

// WIND CALCULATION
// Sample Global Wind
vec2 global_uv = world_pos.xz / wind_texture_scale;
vec2 move_uv = global_uv + (normalize(wind_direction) * TIME * wind_speed);
float noise_val = texture(wind_noise, move_uv).r;
// Gust mask/threshold
// Anything below 'gust_frequency' becomes 0.0/stillness
// Anything above becomes the Gust.
float gust_mask = smoothstep(gust_frequency, 1.0, noise_val);
// Idle movement/breath
// Very small Sine wave. Only moves along local X.
float idle_sway = sin(TIME * still_sway_speed + world_pos.x + world_pos.z) * still_sway_strength;
// Gust movement/whoosh
// Adds a high-frequency flutter only during the gust
float flutter = sin(TIME * 20.0 + world_pos.x) * 0.1;
float gust_push = (gust_mask * gust_strength) + (gust_mask * flutter);
v_wind_intensity = gust_mask;
// APPLY DISPLACEMENT
float height_factor = 1.0 - UV.y;
float bend_strength = pow(height_factor, 2.0);
vec3 total_offset = vec3(0.0);

// Wind displacement
vec3 world_wind_dir = vec3(wind_direction.x, 0.0, wind_direction.y);
vec3 local_wind_dir = mat3(inverse(MODEL_MATRIX)) * world_wind_dir;
if (billboard_mode) {
	total_offset += object_right_vector * (idle_sway + gust_push) * bend_strength;
} else {
	total_offset += object_right_vector * idle_sway * bend_strength;
	total_offset += local_wind_dir * gust_push * bend_strength;
}

// INTERACTION
vec3 diff_vec = world_pos - player_position; // Get full 3D difference
// Calculate the 3D distance
float dist_3d = length(diff_vec);
if (dist_3d < interaction_radius) {
	// Calculate intensity based on true 3D distance
	float push_strength = smoothstep(interaction_radius, 0.0, dist_3d);
	// For the DIRECTION, we still only want to push on X/Z (horizontal)
	// otherwise the grass would be pushed down into the dirt or pulled up.
	vec3 push_dir_flat = diff_vec;
	push_dir_flat.y = 0.0;
	push_dir_flat = normalize(push_dir_flat);
	// Always transform to local space
	push_dir_flat = mat3(inverse(MODEL_MATRIX)) * push_dir_flat;
	total_offset += push_dir_flat * push_strength * interaction_push * bend_strength;
}
// Static blade bend
vertex_pos += object_forward_vector * blade_bend * bend_strength;
// VOLUME PRESERVATION
float dist_moved = length(total_offset.xz);
float y_drop = dist_moved * 0.2 * bend_strength;
VERTEX = vertex_pos + total_offset;
VERTEX.y -= y_drop;
}

void fragment() {
// SHAPE
float center_dist = abs(UV.x - 0.5) * 2.0;
float shape_mask = pow(UV.y, 1.0 / blade_height_taper);
if (center_dist > shape_mask * blade_width) discard;

// COLOR
vec3 gradient = mix(color_top.rgb, color_bottom.rgb, UV.y);
vec3 wind_highlight = color_top.rgb * 1.5;
vec3 varied_color = mix(gradient, color_variation, v_patch * 0.3);
vec3 final_color = mix(varied_color, wind_highlight, v_wind_intensity * 0.4);
ALBEDO = final_color;

// IMPROVED SHADING
if (!FRONT_FACING) {
	NORMAL = -NORMAL;
}

float bottom_to_top = v_height; // 0 at tip, 1 at base? Wait, UV.y 0 bottom, 1 top
AO = bottom_to_top + v_wind_intensity * 0.3;
AO = clamp(AO, 0.0, 1.0);
AO_LIGHT_AFFECT = 1.0;

vec3 world_up_view = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
NORMAL = mix(NORMAL, world_up_view, bottom_to_top * 0.5);

ROUGHNESS = 0.8;
SPECULAR = 0.2;

BACKLIGHT = ALBEDO * 0.3;
}