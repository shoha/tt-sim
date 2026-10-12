shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

/*
 * Wind Foliage Shader -- No-Antialiasing Variant
 * ================================================
 *
 * Debug-only A/B counterpart to wind_foliage.gdshader, swapped in by
 * DebugRenderToggles' "Foliage AA" checkbox (F3 performance overlay) to test
 * whether the 4x MSAA enabled solely to support wind_foliage.gdshader's
 * alpha_to_coverage cutout antialiasing is worth its viewport-wide rendering cost.
 * See docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
 *
 * Identical wind-sway/PBR/occlusion-fade logic to wind_foliage.gdshader (shared via
 * wind_foliage_include.gdshaderinc, so the two can't drift out of sync) -- the only
 * difference is a plain ALPHA_SCISSOR cutout with a hard edge: no alpha_to_coverage
 * render mode, no antialiasing-edge built-ins, no MSAA dependency.
 *
 * MANAGED BY: WindFoliage.get_shader_no_aa() (utils/wind_foliage.gd) loads this once
 * and reuses the compiled Shader resource, mirroring get_shader()'s own caching.
 * Used for real (not only the debug toggle) when the player's Antialiasing setting is None:
 * VisualEffectsController.apply_foliage_antialiasing().
 *
 * BODY: wind_foliage_main.gdshaderinc, with WIND_FOLIAGE_NO_AA dropping the edge built-ins.
 */

#define WIND_FOLIAGE_NO_AA
#include "res://shaders/wind_foliage_main.gdshaderinc"
