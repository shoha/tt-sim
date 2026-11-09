shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, alpha_to_coverage;

/*
 * Wind Foliage Shader -- Ground Cover
 * ===================================
 *
 * The ground cover's lean light with the antialiased (alpha-to-coverage) cutout, as
 * wind_foliage.gdshader is to wind_foliage_no_aa.gdshader; see wind_foliage_ground_no_aa.gdshader
 * for the model. Used while MSAA is on (an Antialiasing setting, or the eye view's 4x).
 *
 * MANAGED BY: WindFoliage.get_shader_ground() (utils/wind_foliage.gd).
 */

#define FOLIAGE_GROUND_LEAN
#include "res://shaders/wind_foliage_main.gdshaderinc"
