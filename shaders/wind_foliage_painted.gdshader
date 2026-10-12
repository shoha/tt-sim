shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

/*
 * Wind Foliage Shader -- Painted Light Variant
 * ============================================
 *
 * wind_foliage.gdshader with FOLIAGE_PAINTED_LIGHT defined: the same wind, cutout, canopy
 * and occlusion fades, plus the painted crown light (a sun-ward albedo ramp, an edge-on
 * cut, silhouette ink, a soft two-tone light() and less ambient). The terms and their
 * defaults are in wind_foliage_include.gdshaderinc's FOLIAGE_PAINTED_LIGHT blocks.
 *
 * WindFoliage.apply_material() picks it for a source material whose glTF extras carry
 * tt_foliage_light "painted" (FoliageLight.is_painted; docs/ASSET_PIPELINE.md section 6),
 * which treecube writes on the leaf material of its round 5 clump-style broadleaf trees and
 * bushes. wind_foliage_painted_no_aa.gdshader is its twin for Antialiasing None.
 *
 * MANAGED BY: FoliageLight.get_shader() (utils/foliage_light.gd).
 */

#define FOLIAGE_PAINTED_LIGHT
#include "res://shaders/wind_foliage_main.gdshaderinc"
