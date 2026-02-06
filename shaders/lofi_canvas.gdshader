/*
 * Lo-Fi Composite Post-Processing Shader (CanvasItem/2D Version)
 * ===============================================================
 * 
 * PURPOSE:
 * Creates a cohesive retro/lo-fi aesthetic to unify assets of varying styles
 * and quality levels. Applied as a 2D post-process effect on a SubViewport's
 * texture via SubViewportContainer or TextureRect.
 * 
 * This version processes the ENTIRE rendered scene including transparent objects,
 * since the SubViewport captures everything before this shader runs.
 * 
 * EFFECTS OVERVIEW:
 * 1. PIXELATION - Subtle resolution reduction to soften detail differences
 * 2. COLOR GRADING - Desaturation + warm tint for cohesive palette
 * 3. VIGNETTE - Edge darkening to focus attention and add warmth
 * 4. FILM GRAIN - Organic noise texture mimicking analog film stock
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
	// EFFECT 3: VIGNETTE
	// -------------------------------------------------------------------------
	vec2 center_uv = UV - 0.5;
	float dist = length(center_uv);
	float vignette = 1.0 - smoothstep(vignette_radius, vignette_radius + 0.5, dist * 2.0);
	vignette = mix(1.0, vignette, vignette_strength);
	color *= vignette;
	
	// -------------------------------------------------------------------------
	// EFFECT 4: FILM GRAIN
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
