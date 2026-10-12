shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

/*
 * Wind Foliage Shader -- Painted Light, No-Antialiasing Variant
 * =============================================================
 *
 * wind_foliage_painted.gdshader's plain-cutout twin (no alpha_to_coverage, no MSAA
 * dependency), as wind_foliage_no_aa.gdshader is to wind_foliage.gdshader. Swapped in by
 * VisualEffectsController when the player's Antialiasing setting is None.
 *
 * MANAGED BY: FoliageLight.get_shader_no_aa() (utils/foliage_light.gd).
 */

#define WIND_FOLIAGE_NO_AA
#define FOLIAGE_PAINTED_LIGHT
#include "res://shaders/wind_foliage_main.gdshaderinc"
