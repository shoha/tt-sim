// Bakes one biome's ground look fields for steep faces (shaders/ground_steep_zones.gdshaderinc;
// docs/ARCHITECTURE.md "Steep faces"). Runs on a ColorRect of GroundLookBake's steep SubViewport,
// one rect per look slot over a band of STEEP_LAYERS columns by two rows: column k is height layer
// k (the same fields at map-frame XZ shifted by its STEEP_SHIFT, layer 0 not shifted), row 0 holds the shape fields before their thresholds
// (zone 1, 2, 3 shapes without the ragged edge, the light's field), row 1 each zone's ragged-edge
// octave (the alpha unused). Raw 8-bit values over bake_rect, shifted by zone_seed_m like the
// look bake (ground_light_field_bake.gdshader), whose uniforms it shares.
shader_type canvas_item;
render_mode blend_disabled;

#define LIGHT_FIELD_BAKE
#include "res://shaders/ground_light_field.gdshaderinc"

uniform vec4 bake_rect = vec4(-64.0, -64.0, 128.0, 128.0);

// Columns (height layers) and rows of a slot's band; GroundSteepZones.LAYERS and ROWS.
const vec2 STEEP_BAND = vec2(3.0, 2.0);
// Height layers 1 and 2's XZ shifts (metres): far apart and off the noise lattices, so each
// layer's fields are independent of the others'.
const vec2 STEEP_SHIFT_1 = vec2(111.39, 71.13);
const vec2 STEEP_SHIFT_2 = vec2(-83.71, 129.37);

// zone_shape's two parts (keep in step with it): the warped two-octave shape, and in `rag` the
// ragged-edge octave's noise (0..1; zone_shape adds (rag - 0.5) * zone_rag).
float steep_shape(vec2 xz, float scale_m, vec2 offset, float angle, float stretch, out float rag) {
	vec2 cs = vec2(cos(angle), sin(angle));
	vec2 r = vec2(dot(xz, cs) / max(stretch, 0.1), dot(xz, vec2(-cs.y, cs.x)));
	vec2 p = r / scale_m;
	vec2 w = vec2(
		light_field_noise(p * 0.55 + offset + vec2(3.7, -1.9)),
		light_field_noise(p * 0.55 + offset + vec2(-8.3, 6.1))
	);
	p += (w - 0.5) * 2.0 * zone_warp;
	float f = light_field_noise(p + offset) * 0.7
		+ light_field_noise(p * 2.07 + offset * 1.3 + vec2(5.1, 2.2)) * 0.3;
	vec2 q = r / zone_rag_m + (w - 0.5) * 3.0;
	rag = light_field_noise(q + offset * 0.7 + vec2(-2.9, 13.3));
	return f;
}

// light_field_procedural's field before its thresholds (keep in step with it); the streaks are
// left out (the steep faces draw none).
float steep_light(vec2 xz) {
	vec2 p = xz / light_field_scale_m;
	if (light_field_stretch != 1.0) {
		vec2 along = light_field_flow(xz);
		p = vec2(dot(p, along) / light_field_stretch, dot(p, vec2(-along.y, along.x)));
	}
	vec2 warp = vec2(
		light_field_noise(p * 0.45 + vec2(3.1, -7.3)), light_field_noise(p * 0.45 + vec2(-5.7, 2.9))
	);
	p += (warp - 0.5) * 1.4;
	float f = light_field_noise(p) * 0.72 + light_field_noise(p * 2.03 + vec2(11.1, 4.7)) * 0.28;
	if (light_field_broad > 0.0) {
		float g = light_field_noise(p * 0.4 + vec2(-13.7, 6.1));
		f = mix(f, 0.5 + (f - 0.5) * 0.8 + (g - 0.5) * 0.9, light_field_broad);
	}
	return f;
}

void fragment() {
	vec2 cell = UV * STEEP_BAND;
	vec2 k = floor(cell);
	vec2 shift = k.x < 0.5 ? vec2(0.0) : (k.x < 1.5 ? STEEP_SHIFT_1 : STEEP_SHIFT_2);
	vec2 xs = bake_rect.xy + (cell - k) * bake_rect.zw + zone_seed_m + shift;
	vec3 ang = vec3(zone_angle) + zone_angle_k;
	vec3 str = vec3(zone_stretch) * zone_stretch_k;
	vec3 rag;
	float f1 = steep_shape(xs, zone_scale_m.x, vec2(17.3, -4.1), ang.x, str.x, rag.x);
	float f2 = steep_shape(xs, zone_scale_m.y, vec2(-23.9, 11.7), ang.y, str.y, rag.y);
	float f3 = f2;
	rag.z = rag.y;
	if (zone_nest < 0.5) {
		f3 = steep_shape(xs, zone_scale_m.z, vec2(7.7, 29.3), ang.z, str.z, rag.z);
	}
	vec4 c = k.y < 0.5 ? vec4(f1, f2, f3, steep_light(xs)) : vec4(rag, 1.0);
	COLOR = clamp(c, vec4(0.0), vec4(1.0));
}
