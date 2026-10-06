shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, ambient_light_disabled, specular_disabled;

/*
 * Avatar Figure Shader (avatar kit consumer, 2026-10-06)
 * ======================================================
 *
 * Draws every part of an avatar assembled by AvatarKit (utils/avatar_kit.gd) from figurine's
 * kit (docs/ASSET_PIPELINE.md section 10). One ShaderMaterial per part per figure, set as the
 * part's material_override: the imported StandardMaterial3D is never used (with COLOR_0
 * present Godot may turn on vertex colour as albedo there). Open cards use the double-sided
 * twin, avatar_figure_double_sided.gdshader; the body of both is avatar_figure.gdshaderinc.
 *
 * Colour. The figure's palette (AvatarPalette: 8 slot columns of shadow -> base -> highlight
 * gradients, 64 rows) is read at UV, u snapped to the column centre so the linear filter only
 * ever blends along a gradient; then the part's detail overlay (ink, trim, the hair's sheen)
 * at UV2 is composited over it by its alpha. Detail is fixed colour.
 *
 * Face. On the head (has_face), the chosen cell of each kind is composed inside face_rect in
 * the order marks, mouths, eyes, brows: face space f = (UV2 - rect.xy) / (rect.zw - rect.xy),
 * the sheet read at cell + f * cell_size, no flip. Where face_mask's R (eyes) or G (hair) is
 * above 0 the sheet's stored value (read raw, not linearised) is a palette v and that slot's
 * palette colour is mixed in by the mask weight, so irises take the eye colour and brows the
 * hair colour with their shading painted in. Each cell lays over by its alpha.
 *
 * Light (figurine's Blender material, which judged the kit): COLOR_0.R = L is the vertex's
 * light response, and the face forces it to 0. The paint shows unlit at (1 - emission_drop L),
 * and the lit share (ALBEDO = colour x L) takes a soft wrapped light term from every scene
 * light (light_strength, light_wrap) plus an ambient fill (ambient_fill). Scene shadow maps
 * are ignored for the sun: their filter stipple lands on the painted blocks (the avatar
 * probe), so shade comes instead from the per-figure `shade` instance value, one ray toward
 * the sun from the CPU at placement and on move (AvatarShade), which removes shadow_strength
 * of the sun's term and tints everything by shade_tint. Lamps keep their ATTENUATION, so a
 * torch's falloff and shadow still read. No specular and no environment ambient: the scene's
 * ambient enters through the global `figure_ambient` (LevelEnvironmentManager pushes
 * ambient_light_color x energy), as a tint on the whole figure: its hue at full strength, its
 * level against ambient_reference (the default environment's), clamped to ambient_floor so a
 * token stays readable at night or in a dungeon, mixed in by ambient_mix. So a figure sits in
 * a sunset or a dungeon even where it is unlit paint.
 *
 * Hidden from players: `hidden_fade` (instance, 0..1) discards that share of pixels in a 4 x 4
 * ordered dither, for the GM's view of a hidden token (BoardToken._set_mesh_transparency only
 * knows StandardMaterial3D).
 *
 * No outline: ink is painted into the textures. If a hull is ever added, its pixel width needs
 * abs(PROJECTION_MATRIX[1][1]) (negative under Vulkan).
 *
 * Godot skins VERTEX, NORMAL and TANGENT before vertex(); proportions live in the Skin's bind
 * matrices (AvatarProportions), so nothing here knows about them.
 */

#include "res://shaders/avatar_figure.gdshaderinc"
