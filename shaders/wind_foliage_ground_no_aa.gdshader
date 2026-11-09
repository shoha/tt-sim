shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

/*
 * Wind Foliage Shader -- Ground Cover, No-Antialiasing Variant
 * ============================================================
 *
 * The ground cover's lean light (card foliagelight, docs/PERFORMANCE.md "Ground-cover
 * lighting"): grass cards, sprig clumps and litter (the wind category "grass", flowers
 * excepted) draw on this instead of wind_foliage_no_aa.gdshader. Lambert with no specular lobe,
 * no ORM or normal map fetch, no backlight and none of the canopy fades' inputs; the sun, its
 * cast shadow, the ambient, the base darkening, the ground look's tuft colour and the eye
 * view's near grass are kept. A card's normals all point up, so the dropped terms gave it
 * nothing to show: 0.27 ms less GPU at home and 0.52 ms at zoom 20 on a filled 320 ft map.
 *
 * MANAGED BY: WindFoliage.get_shader_ground_no_aa() (utils/wind_foliage.gd), swapped in by
 * VisualEffectsController when the player's Antialiasing setting is None.
 */

#define WIND_FOLIAGE_NO_AA
#define FOLIAGE_GROUND_LEAN
#include "res://shaders/wind_foliage_main.gdshaderinc"
