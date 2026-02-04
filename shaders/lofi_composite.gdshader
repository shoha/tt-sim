/*
 * Lo-Fi Composite Post-Processing Shader
 * =======================================
 * 
 * PURPOSE:
 * Creates a cohesive retro/lo-fi aesthetic to unify assets of varying styles
 * and quality levels. Applied as a fullscreen post-process effect via a 
 * MeshInstance3D quad positioned in front of the camera.
 * 
 * EFFECTS OVERVIEW:
 * 1. PIXELATION - Subtle resolution reduction to soften detail differences
 * 2. COLOR GRADING - Desaturation + warm tint for cohesive palette
 * 3. VIGNETTE - Edge darkening to focus attention and add warmth
 * 4. FILM GRAIN - Organic noise texture mimicking analog film stock
 * 
 * SCENE SETUP:
 * - Attached to a 2x2 QuadMesh with flip_faces=true as child of Camera3D
 * - The MeshInstance3D node is named "LofiQuad" in game_map.tscn
 * - Toggle visibility via GameMap.set_lofi_enabled() or the Settings menu
 * - Shader parameters are exposed in the ShaderMaterial for editor tweaking
 * 
 * RENDER ORDER (CRITICAL):
 * This shader uses hint_screen_texture which captures the scene BEFORE 
 * transparent objects render. This has important implications:
 * 
 * 1. OPAQUE objects ARE processed by this shader (captured in screen texture)
 * 2. TRANSPARENT objects are NOT processed (render after screen capture)
 * 
 * For visual elements that MUST be processed by this shader (like drop 
 * indicators), they must use TRANSPARENCY_DISABLED to render in the opaque
 * pass. See board_token_drop_indicator_renderer.gd for an example.
 * 
 * The shader uses these render_mode flags:
 * - depth_test_disabled: Don't check depth buffer (always render)
 * - depth_draw_never: Don't write to depth buffer (don't occlude anything)
 * - cull_disabled: Render both sides of the quad
 * 
 * The ShaderMaterial uses render_priority=100 to render after most scene
 * objects but the exact priority is less important than the opaque/transparent
 * distinction described above.
 * 
 * EDITOR TWEAKING:
 * All effect parameters are exposed as uniforms with hint_range for easy
 * adjustment in the Godot editor. Select the LofiQuad node, expand the
 * mesh material, and adjust Shader Parameters.
 * 
 * ITERATION TIPS:
 * - Pixelation: Increase for more retro look, set to 0 to disable
 * - Saturation: Lower = more muted/vintage, higher = more vibrant
 * - Color tint: Adjust RGB for different moods (warm, cool, sepia)
 * - Vignette: Increase strength for more dramatic framing
 * - Grain: Keep subtle (< 0.05) to avoid distraction, 0 to disable
 */

shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// =============================================================================
// PIXELATION
// Reduces effective resolution by snapping UV coordinates to a grid.
// Value is in normalized UV units (0.003 = roughly 300 virtual pixels).
// Uses 16:9 aspect ratio assumption for consistent square pixels.
// Set to 0 to disable.
// =============================================================================
group_uniforms pixelation;
uniform float pixelation : hint_range(0.0, 0.01) = 0.003;

// =============================================================================
// COLOR GRADING
// Saturation: 1.0 = unchanged, <1.0 = desaturated, >1.0 = oversaturated
// Color tint: Multiplied with final color. Default is slightly warm.
// =============================================================================
group_uniforms color_grading;
uniform float saturation : hint_range(0.0, 1.5) = 0.85;
uniform vec3 color_tint : source_color = vec3(1.02, 1.0, 0.96);

// =============================================================================
// VIGNETTE
// Darkens screen edges using a radial gradient.
// Strength: 0 = disabled, 1 = full effect
// Radius: How far from center the darkening begins (larger = smaller dark area)
// =============================================================================
group_uniforms vignette;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_radius : hint_range(0.0, 2.0) = 0.8;

// =============================================================================
// FILM GRAIN
// Simulates analog film stock grain using value noise.
// Key characteristics that make it feel natural:
// - Uses FRAGCOORD (screen pixels) so grain is zoom-independent
// - Overlay blend mode affects mid-tones most, preserves shadows/highlights
// - Mid-tone mask further reduces grain in very dark/bright areas
// - Slow animation speed prevents distracting "crawl"
//
// Intensity: Keep low (0.02-0.05) for subtle effect
// Speed: 0 = static grain, higher = more animation (keep < 0.3 for subtlety)
// Scale: Lower = finer grain, higher = coarser (0.1-0.2 is usually good)
// =============================================================================
group_uniforms film_grain;
uniform float grain_intensity : hint_range(0.0, 0.1) = 0.025;
uniform float grain_speed : hint_range(0.0, 1.0) = 0.2;
uniform float grain_scale : hint_range(0.05, 0.5) = 0.12;
group_uniforms;

// ============================================================================
// NOISE FUNCTIONS (for film grain)
// ============================================================================

/*
 * Hash function - converts 2D position to pseudo-random value.
 * Uses the classic sin-based hash. Fast but can have precision issues
 * at very large input values.
 */
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

/*
 * Value noise - creates smooth, continuous noise.
 * Unlike Perlin noise, this interpolates random values at grid points.
 * 
 * Uses quintic interpolation (6t^5 - 15t^4 + 10t^3) instead of cubic
 * for smoother derivatives, reducing visible grid patterns.
 * 
 * Returns: Value in range [0, 1]
 */
float value_noise(vec2 p) {
	vec2 i = floor(p);  // Integer part (grid cell)
	vec2 f = fract(p);  // Fractional part (position within cell)
	
	// Quintic interpolation curve - smoother than cubic, no visible grid
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	
	// Sample random values at four corners of the grid cell
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	// Bilinear interpolation between corners
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/*
 * Film grain generator - creates zoom-independent grain pattern.
 * 
 * Uses FRAGCOORD (actual screen pixels) rather than UV coordinates
 * so the grain size remains constant regardless of camera zoom level,
 * matching real film where grain is a property of the film stock.
 * 
 * Returns: Value in range [0, 1] for use with overlay blending.
 */
float get_grain(vec2 frag_coord, float time, float speed, float scale) {
	// Scale fragment coordinates to control grain fineness
	vec2 grain_pos = frag_coord * scale;
	
	// Slow time evolution creates gentle drift without "crawling" effect
	float t = time * speed;
	
	// Single octave noise - multiple octaves look too busy for film grain
	// Offset by time in both axes with slightly different rates for organic feel
	float noise_val = value_noise(grain_pos + vec2(t * 2.0, t * 1.5));
	
	return noise_val;
}

// ============================================================================
// BLENDING FUNCTIONS
// ============================================================================

/*
 * Attempt at an overlay blend mode - standard Photoshop-style overlay.
 * 
 * Behavior:
 * - Where base < 0.5: Multiplies (darkens)
 * - Where base >= 0.5: Screens (lightens)
 * 
 * This naturally affects mid-tones most while preserving shadows and highlights,
 * making it ideal for film grain application.
 */
vec3 overlay_blend(vec3 base, vec3 blend) {
	return mix(
		2.0 * base * blend,                           // Multiply for darks
		1.0 - 2.0 * (1.0 - base) * (1.0 - blend),    // Screen for lights
		step(0.5, base)                               // Switch at 0.5
	);
}

/*
 * Mid-tone mask - returns how "mid-tone" a luminance value is.
 * 
 * Creates a bell curve: 1.0 at luminance 0.5, falls to 0.0 at 0 and 1.
 * Used to reduce grain visibility in very dark and very bright areas,
 * matching real film behavior where grain is most visible in mid-tones.
 */
float midtone_mask(float luminance) {
	return 1.0 - pow(2.0 * luminance - 1.0, 2.0);
}

// ============================================================================
// VERTEX SHADER
// ============================================================================

void vertex() {
	// Fullscreen quad positioning for Godot 4.3+
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// -------------------------------------------------------------------------
	// EFFECT 1: PIXELATION
	// -------------------------------------------------------------------------
	// Snaps UV coordinates to a grid, creating a lower-resolution look.
	// This helps unify assets by reducing fine detail differences.
	//
	// The 16:9 aspect ratio assumption ensures pixels appear square.
	// For other aspect ratios, there may be slight stretching, but it's
	// not noticeable at the subtle pixelation levels we use.
	
	if (pixelation > 0.0) {
		float aspect = 16.0 / 9.0;
		vec2 pixel_size = vec2(pixelation / aspect, pixelation);
		
		// Snap to grid center (+ 0.5) to avoid edge sampling issues
		uv = (floor(uv / pixel_size) + 0.5) * pixel_size;
		
		// Clamp to prevent sampling outside screen bounds at edges
		uv = clamp(uv, 0.001, 0.999);
	}
	
	// Sample the screen texture with potentially pixelated UVs
	vec3 color = texture(screen_texture, uv).rgb;
	
	// -------------------------------------------------------------------------
	// EFFECT 2: COLOR GRADING
	// -------------------------------------------------------------------------
	// Adjusts saturation and applies a color tint for cohesive palette.
	//
	// Luminance calculation uses Rec. 709 coefficients (standard for sRGB).
	// Desaturation mixes toward grayscale based on saturation value.
	// Color tint multiplies final color - use values near 1.0 for subtlety.
	
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);
	color *= color_tint;
	
	// -------------------------------------------------------------------------
	// EFFECT 3: VIGNETTE
	// -------------------------------------------------------------------------
	// Darkens edges of the screen with a soft radial falloff.
	// Creates a subtle "tunnel" effect that focuses attention to center.
	//
	// Uses original SCREEN_UV (not pixelated) for smooth gradient.
	// Smoothstep creates soft transition from lit center to darkened edges.
	
	vec2 center_uv = SCREEN_UV - 0.5;
	float dist = length(center_uv);
	float vignette = 1.0 - smoothstep(vignette_radius, vignette_radius + 0.5, dist * 2.0);
	vignette = mix(1.0, vignette, vignette_strength);
	color *= vignette;
	
	// -------------------------------------------------------------------------
	// EFFECT 4: FILM GRAIN
	// -------------------------------------------------------------------------
	// Adds organic noise texture mimicking analog film stock.
	//
	// Key techniques for natural-looking grain:
	// 1. FRAGCOORD-based: Grain size is constant regardless of camera zoom
	// 2. Value noise: Smooth, continuous noise without harsh transitions
	// 3. Overlay blend: Naturally affects mid-tones, preserves blacks/whites
	// 4. Mid-tone mask: Further reduces grain in very dark/bright areas
	// 5. Slow animation: Prevents distracting "crawling" static effect
	
	float noise = get_grain(FRAGCOORD.xy, TIME, grain_speed, grain_scale);
	vec3 grain_color = vec3(noise);  // Monochrome grain
	
	// Calculate mid-tone mask based on current pixel luminance
	float pixel_luma = dot(color, vec3(0.299, 0.587, 0.114));
	float grain_mask = midtone_mask(pixel_luma);
	
	// Apply grain with overlay blend, masked by intensity and mid-tone factor
	vec3 grained = overlay_blend(color, grain_color);
	color = mix(color, grained, grain_intensity * grain_mask);
	
	// -------------------------------------------------------------------------
	// OUTPUT
	// -------------------------------------------------------------------------
	
	color = clamp(color, 0.0, 1.0);
	ALBEDO = color;
}
