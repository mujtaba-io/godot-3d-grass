shader_type sky;

// --- COLORS ---
group_uniforms Sky_Colors;
uniform vec3 day_top_color : source_color = vec3(0.1, 0.6, 0.9); // Deep Blue
uniform vec3 day_horizon_color : source_color = vec3(0.95, 0.78, 0.55); // "Dry" Sandy Orange
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);

// --- CLOUDS ---
group_uniforms Clouds;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.8, 0.85, 0.95);
uniform float cloud_scale = 0.5; // Lower is bigger clouds
uniform float cloud_speed = 0.02;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5; // 0.0 = Clear Sky, 1.0 = Overcast
uniform float cloud_softness : hint_range(0.0, 1.0) = 0.1; // Edge hardness

// --- SUN ---
group_uniforms Sun;
uniform float sun_radius : hint_range(0.0, 1.0) = 0.05;
uniform float sun_blur : hint_range(0.0, 1.0) = 0.01;

void sky() {
	vec3 view_dir = EYEDIR;

	// 1. BACKGROUND GRADIENT
	// We map the Y direction (up/down) to mix colors
	float horizon_mix = smoothstep(-0.1, 0.3, view_dir.y);
	vec3 sky_gradient = mix(day_horizon_color, day_top_color, horizon_mix);

	// 2. SUN DISC
	// LIGHT0_DIRECTION is automatically provided by the DirectionalLight3D in the scene
	float sun_dot = dot(view_dir, LIGHT0_DIRECTION);
	float sun_mask = smoothstep(1.0 - sun_radius - sun_blur, 1.0 - sun_radius, sun_dot);

	// 3. CLOUDS
	// A. Mapping: We project the sky sphere onto a 2D plane for the texture
	// This "dome" mapping helps avoid extreme stretching at the horizon
	vec2 sky_uv = view_dir.xz / (view_dir.y + 0.5);

	// B. Animation
	float time_offset = TIME * cloud_speed;
	vec2 move_uv_1 = (sky_uv * cloud_scale) + vec2(time_offset, time_offset * 0.5);
	vec2 move_uv_2 = (sky_uv * cloud_scale * 1.5) - vec2(time_offset * 0.5, 0.0); // Secondary layer

	// C. Noise Sampling
	float noise_1 = texture(cloud_noise, move_uv_1).r;
	float noise_2 = texture(cloud_noise, move_uv_2).r;

	// Combine noises for fluffiness.
	// We emphasize noise_1 but use noise_2 to break up the shapes.
	float final_noise = mix(noise_1, noise_2, 0.5);

	// Fade clouds out near horizon to hide the UV distortion
	float horizon_fade = smoothstep(0.0, 0.2, view_dir.y);
	final_noise *= horizon_fade;

	// D. Shaping (The Cutoff)
	// We remap cloud_coverage to a threshold
	float threshold = 1.0 - cloud_coverage;
	float cloud_alpha = smoothstep(threshold, threshold + cloud_softness, final_noise);

	// 4. CLOUD LIGHTING
	// Fake "Volume": Thicker parts of the noise are darker (shadow)
	// Plus, clouds closer to the sun get a "Silver Lining" (Rim light)

	// Simple rim light based on sun position
	float rim_strength = smoothstep(0.0, 1.0, sun_dot) * 2.0;
	vec3 cloud_final_color = mix(cloud_shadow_color, cloud_color, final_noise + (rim_strength * 0.5));

	// Make clouds brighter near the sun
	cloud_final_color += sun_color * sun_mask * 0.5; // Sun blooms through clouds slightly

	// 5. COMPOSITION
	vec3 final_sky = mix(sky_gradient, cloud_final_color, cloud_alpha);

	// Add Sun on top of sky (behind clouds? No, usually sun is blindingly bright)
	// If you want sun BEHIND clouds, remove this line.
	// If you want sun IN FRONT (blinding), keep it.
	// For stylized, blending it usually looks best:
	final_sky = mix(final_sky, sun_color, sun_mask);

	COLOR = final_sky;
}