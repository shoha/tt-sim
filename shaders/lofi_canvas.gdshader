/*
 * Lo-Fi Composite Post-Processing Shader (CanvasItem/2D Version)
 * ===============================================================
 * 
 * PURPOSE:
 * Creates a cohesive retro/lo-fi aesthetic to unify assets of varying styles
 * and quality levels. Applied as a 2D post-process effect on a SubViewport's
 * texture via SubViewportContainer.
 * 
 * ARCHITECTURE:
 * The 3D scene renders to a SubViewport, then this shader processes the
 * viewport's texture via the SubViewportContainer's material. This approach
 * captures EVERYTHING including transparent objects (glass, water, particles,
 * selection glow, etc.) - unlike the old hint_screen_texture approach.
 * 
 * Scene structure in game_map.tscn:
 *   GameMap (Node3D)
 *   ├── WorldViewportLayer (CanvasLayer, layer=-1)
 *   │   └── SubViewportContainer (with this shader as material)
 *   │       └── SubViewport
 *   │           ├── CameraHolder/Camera3D
 *   │           ├── DragAndDrop3D
 *   │           └── (tokens, map, etc.)
 *   └── GameplayMenu (CanvasLayer - UI on top)
 * 
 * EFFECTS OVERVIEW:
 * 1. PIXELATION - Subtle resolution reduction to soften detail differences
 * 2. COLOR GRADING - Desaturation + warm tint for cohesive palette
 * 3. DITHERING - Color quantization with Bayer dithering for retro palette look
 * 4. VIGNETTE - Edge darkening to focus attention and add warmth
 * 5. FILM GRAIN - Organic noise texture mimicking analog film stock
 * 
 * USAGE:
 * - Toggle via GameMap.set_lofi_enabled() or the Settings menu
 * - Parameters can be adjusted in the ShaderMaterial on SubViewportContainer
 * 
 * EDITOR TWEAKING:
 * - Pixelation: Increase for more retro look, set to 0 to disable
 * - Saturation: Lower = more muted/vintage, higher = more vibrant  
 * - Color tint: Adjust RGB for different moods (warm, cool, sepia)
 * - Dithering: Lower color_levels for more retro (8-16), 256 to disable
 *   - color_levels 8 = 3-bit (8 shades per channel, very retro)
 *   - color_levels 16 = 4-bit (16 shades, classic game look)
 *   - color_levels 32 = 5-bit (32 shades, subtle but visible)
 *   - dither_strength controls how visible the Bayer pattern is
 * - Vignette: Increase strength for more dramatic framing
 * - Grain: Keep subtle (< 0.05) to avoid distraction, 0 to disable
 * 
 * NOTE: This replaced lofi_composite.gdshader which had transparency limitations.
 * See lofi_composite.gdshader header comments for migration history.
 */

shader_type canvas_item;

// Note: For SubViewportContainer, TEXTURE contains the viewport's rendered content
// We don't need a separate uniform - just use the built-in TEXTURE

// =============================================================================
// PIXELATION
// =============================================================================
group_uniforms pixelation;
uniform float pixelation : hint_range(0.0, 0.01) = 0.003;

// =============================================================================
// COLOR GRADING
// =============================================================================
group_uniforms color_grading;
uniform float saturation : hint_range(0.0, 1.5) = 0.85;
uniform vec3 color_tint : source_color = vec3(1.02, 1.0, 0.96);

// =============================================================================
// DITHERING (color quantization with ordered dithering)
// =============================================================================
group_uniforms dithering;
// Number of color levels per channel (lower = more retro, 256 = disabled)
// Common values: 8 (3-bit), 16 (4-bit), 32 (5-bit), 64 (6-bit)
uniform float color_levels : hint_range(2.0, 256.0) = 32.0;
// Dither strength - how much the Bayer pattern affects quantization
uniform float dither_strength : hint_range(0.0, 1.0) = 0.5;

// =============================================================================
// VIGNETTE
// =============================================================================
group_uniforms vignette;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_radius : hint_range(0.0, 2.0) = 0.8;

// =============================================================================
// FILM GRAIN
// =============================================================================
group_uniforms film_grain;
uniform float grain_intensity : hint_range(0.0, 0.1) = 0.025;
uniform float grain_speed : hint_range(0.0, 1.0) = 0.2;
uniform float grain_scale : hint_range(0.05, 0.5) = 0.12;
group_uniforms;

// ============================================================================
// BAYER DITHERING
// ============================================================================

// 4x4 Bayer matrix for ordered dithering (as a flat array for reliable indexing)
// Standard Bayer pattern values: 0,8,2,10 / 12,4,14,6 / 3,11,1,9 / 15,7,13,5
float get_bayer_value(int x, int y) {
	// Bayer 4x4 matrix values (0-15), computed inline to avoid matrix indexing issues
	int index = x + y * 4;
	// Row 0: 0, 8, 2, 10
	// Row 1: 12, 4, 14, 6
	// Row 2: 3, 11, 1, 9
	// Row 3: 15, 7, 13, 5
	if (index == 0) return 0.0;
	if (index == 1) return 8.0;
	if (index == 2) return 2.0;
	if (index == 3) return 10.0;
	if (index == 4) return 12.0;
	if (index == 5) return 4.0;
	if (index == 6) return 14.0;
	if (index == 7) return 6.0;
	if (index == 8) return 3.0;
	if (index == 9) return 11.0;
	if (index == 10) return 1.0;
	if (index == 11) return 9.0;
	if (index == 12) return 15.0;
	if (index == 13) return 7.0;
	if (index == 14) return 13.0;
	return 5.0; // index == 15
}

// Get Bayer threshold for a pixel position (returns -0.5 to 0.5)
float get_bayer_threshold(vec2 frag_coord) {
	int x = int(mod(frag_coord.x, 4.0));
	int y = int(mod(frag_coord.y, 4.0));
	return get_bayer_value(x, y) / 16.0 - 0.5;
}

// Quantize color with dithering
vec3 dither_quantize(vec3 color, vec2 frag_coord, float levels, float strength) {
	if (levels >= 256.0) {
		return color; // No quantization needed
	}
	
	// Simple posterization: reduce to N discrete levels per channel
	// With 8 levels, each channel can only be: 0, 0.143, 0.286, 0.429, 0.571, 0.714, 0.857, 1.0
	vec3 quantized = floor(color * levels) / levels;
	
	// Add Bayer dithering pattern
	float threshold = get_bayer_threshold(frag_coord);
	// Threshold determines if we round up to next level
	vec3 remainder = fract(color * levels);
	vec3 dither_add = step(vec3(0.5 - threshold * strength), remainder) / levels;
	quantized += dither_add;
	
	return clamp(quantized, 0.0, 1.0);
}

// ============================================================================
// NOISE FUNCTIONS
// ============================================================================

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	
	// Quintic interpolation
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float get_grain(vec2 frag_coord, float time, float speed, float scale) {
	vec2 grain_pos = frag_coord * scale;
	float t = time * speed;
	float noise_val = value_noise(grain_pos + vec2(t * 2.0, t * 1.5));
	return noise_val;
}

// ============================================================================
// BLENDING FUNCTIONS
// ============================================================================

vec3 overlay_blend(vec3 base, vec3 blend) {
	return mix(
		2.0 * base * blend,
		1.0 - 2.0 * (1.0 - base) * (1.0 - blend),
		step(0.5, base)
	);
}

float midtone_mask(float luminance) {
	return 1.0 - pow(2.0 * luminance - 1.0, 2.0);
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

void fragment() {
	vec2 uv = UV;
	
	// -------------------------------------------------------------------------
	// EFFECT 1: PIXELATION
	// -------------------------------------------------------------------------
	if (pixelation > 0.0) {
		float aspect = 16.0 / 9.0;
		vec2 pixel_size = vec2(pixelation / aspect, pixelation);
		uv = (floor(uv / pixel_size) + 0.5) * pixel_size;
		uv = clamp(uv, 0.001, 0.999);
	}
	
	// Sample the viewport texture (TEXTURE contains the SubViewport's rendered content)
	vec3 color = texture(TEXTURE, uv).rgb;
	
	// -------------------------------------------------------------------------
	// EFFECT 2: COLOR GRADING
	// -------------------------------------------------------------------------
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);
	color *= color_tint;
	
	// -------------------------------------------------------------------------
	// EFFECT 3: DITHERING (color quantization with Bayer pattern)
	// -------------------------------------------------------------------------
	color = dither_quantize(color, FRAGCOORD.xy, color_levels, dither_strength);
	
	// -------------------------------------------------------------------------
	// EFFECT 4: VIGNETTE
	// -------------------------------------------------------------------------
	vec2 center_uv = UV - 0.5;
	float dist = length(center_uv);
	float vignette = 1.0 - smoothstep(vignette_radius, vignette_radius + 0.5, dist * 2.0);
	vignette = mix(1.0, vignette, vignette_strength);
	color *= vignette;
	
	// -------------------------------------------------------------------------
	// EFFECT 5: FILM GRAIN
	// -------------------------------------------------------------------------
	float noise = get_grain(FRAGCOORD.xy, TIME, grain_speed, grain_scale);
	vec3 grain_color = vec3(noise);
	
	float pixel_luma = dot(color, vec3(0.299, 0.587, 0.114));
	float grain_mask = midtone_mask(pixel_luma);
	
	vec3 grained = overlay_blend(color, grain_color);
	color = mix(color, grained, grain_intensity * grain_mask);
	
	// -------------------------------------------------------------------------
	// OUTPUT
	// -------------------------------------------------------------------------
	color = clamp(color, 0.0, 1.0);
	COLOR = vec4(color, 1.0);
}
