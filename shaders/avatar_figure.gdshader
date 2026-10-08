shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

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
 * Light. L is the light response: max(COLOR_0.R, light_floor) off the face (the floor, 1.0,
 * overrides figurine's per-vertex values) and face_light on it. The paint shows as painted at
 * (1 - emission_drop L), and the handed share (ALBEDO = colour x L x emission_drop) is lit as
 * the terrain is: the engine's ambient (sky or colour, SSAO included; scene_ambient, written
 * as AO) plus a soft wrapped term from every scene light (light_strength, light_wrap). With
 * the defaults a fifth of each colour is painted and four fifths are lit, the face half and
 * half (the world-lighting pass, 2026-10-07: figurine's response left skin about 78 % and
 * faces wholly self-lit, so a figure in the canopy's shade glowed as bright as one in sun and
 * stayed cool in a sunset; the user called them stark against the terrain).
 *
 * Scene shadow maps are ignored for the sun. Sampling them (ATTENUATION) was tried twice, in
 * the first probe and again in the world-lighting pass with the figures taking most of their
 * light from the scene: the soft filter's noise, and the figure's own self-shadowing at the
 * sun's grazing angles, put a fine dot pattern over the sunlit flat colour blocks, and
 * snapping the filtered value (smoothstep) only hardened the dots. So shade comes from the
 * per-figure `shade` instance value, one ray toward the sun from the CPU at placement and on
 * move (AvatarShade), which removes shadow_strength of the sun's term and reads the paint from
 * the palette's own shadow end (each slot sampled shade_drop further down its gradient; detail
 * and face pixels darken by the same per-channel ratio), so shade keeps each colour's
 * hue-shifted shadow instead of one cool tint (the look pass, 2026-10-06: the first pass's
 * shade_tint turned skin lavender under the canopy). Lamps keep their ATTENUATION, so a
 * torch's falloff and shadow still read. No specular and no reflections.
 *
 * The painted share takes the scene's ambient through the global `figure_ambient`
 * (LevelEnvironmentManager pushes ambient_light_color x energy), as a tint: its hue mixed in
 * by ambient_hue_mix (a hint, so a blue sky does not turn warm skin pale), its level against
 * ambient_reference (the default environment's), clamped to ambient_floor so a token stays
 * readable at night or in a dungeon, mixed in by ambient_mix.
 *
 * Tonemapper. The scene's Filmic tonemapper lifts midtones and desaturates, and the world's
 * painted colours were authored through it while the palette's were not, so the paint is
 * darkened by paint_contrast (a gamma) and saturated by paint_saturation before the tonemapper
 * sees it (the look pass: figures read pale and pinkish beside the foliage without this; the
 * world-lighting pass trimmed the gamma from 1.25 to 1.15, since the lit share now darkens
 * turned-away sides on its own).
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
