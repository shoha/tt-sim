// Shared wind-sway vertex offset and PBR/occlusion-fade fragment logic for both
// wind_foliage.gdshader (alpha_to_coverage antialiased cutout, 4x MSAA) and
// wind_foliage_no_aa.gdshader (plain cutout, no MSAA dependency) -- the two are A/B
// tested against each other by DebugRenderToggles' "Foliage AA" checkbox (F3
// overlay) to measure whether alpha_to_coverage's viewport-wide MSAA cost is worth
// its softened cutout edges. See
// docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
//
// Godot's shader compiler has a real limitation: fragment stage output built-ins
// (ALBEDO, ROUGHNESS, METALLIC, AO, etc.) can only be assigned directly inside
// vertex()/fragment(), not from any called function. To share the complete PBR and
// occlusion-fade logic without code duplication (which would let the two variants
// drift out of sync), apply_wind_foliage_pbr() uses out-parameters: the function
// computes all PBR values and passes them back to the caller, which then assigns them
// to the built-ins. Functions like wind_sway_vertex_offset take stage built-ins as
// explicit parameters rather than reading them directly, matching the pattern already
// used in occlusion_fade_include.gdshaderinc.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool has_normal_texture = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float specular_reflectance : hint_range(0.0, 1.0) = 0.2;

// Per-category wind tuning (set once per species at construction from a preset --
// see WindFoliage.PRESETS -- never authored per-map).
uniform float sway_speed : hint_range(0.0, 5.0) = 1.0;
uniform float sway_amplitude : hint_range(0.0, 1.0) = 0.05;
uniform float sway_frequency : hint_range(0.05, 2.0) = 0.3;

// Authored wind weights in the vertex colour (treecube's convention, see that repo's
// docs/tt-sim-wind-weights.md): R = whole-plant sway weight (0 root .. 1 top),
// G = flutter weight (branch tips, leaf cards, blade tips), B = phase (0..1) so
// neighbouring limbs and cards desync. Godot gives COLOR = white when a surface has
// no colour array, which would mean full sway everywhere, so this switch is set
// explicitly by WindFoliage.apply_material from the surface format rather than
// inferred from the colour itself. Off (the default), the sway weight falls back to
// the unnormalized local height every pre-treecube asset relies on.
uniform bool use_vertex_wind = false;
// Mesh AABB height in metres: the authored R weight is 0..1, the legacy height weight
// is metres, so R is scaled by this to keep the per-category amplitude presets
// meaning the same thing for both kinds of asset.
uniform float mesh_height : hint_range(0.0, 100.0) = 1.0;
// Secondary flutter driven by G and phased by B: faster and smaller than the sway.
// treecube grades G across each leaf card away from its twig (0.35 at the near
// corners, 1 at the far ones), so a card rustles about its attachment instead of
// hopping as a rigid quad. Kept small: at tt-sim's home zoom a 3 cm hop of every card
// read as a shimmer over the whole canopy, not as leaves moving.
uniform float flutter_amplitude : hint_range(0.0, 0.5) = 0.012;
uniform float flutter_speed : hint_range(0.0, 20.0) = 3.0;

// Gust field: a slow envelope that travels across the map along wind_direction (two
// wavelengths, 12 m and 19 m, so it never repeats cleanly) and modulates the sway.
// During a gust every plant leans over in the wind direction in proportion to its
// sway weight and springs back as the front passes, so neighbouring trees bend
// together and the eye reads wind moving across the forest rather than each tree
// rocking on its own. gust_strength 0 disables it (the sway is then the pure
// per-vertex oscillation it was before); gust_speed is the front's travel speed in
// metres per second. Per-category value from WindFoliage.PRESETS, not per-level.
uniform vec2 wind_direction = vec2(0.857, 0.514);
uniform float gust_strength : hint_range(0.0, 1.0) = 0.6;
uniform float gust_speed : hint_range(0.0, 20.0) = 3.0;

// Base-dark/tip-light gradient, grass-category only (see WindFoliage.apply_material) --
// replaces the contact-darkening a real shadow would have given grass now that it no
// longer casts one (ScatterGlbUtils._build_multimesh_from_transforms' SHADOW_CASTING_SETTING_OFF).
// blade_height is the mesh's own local-space AABB height in world units; left at its 0.0
// default for every other category (e.g. "tree", which still casts a real shadow), which
// apply_wind_foliage_pbr below treats as "no gradient" rather than dividing by zero.
uniform float blade_height : hint_range(0.0, 10.0) = 0.0;
uniform float base_darken : hint_range(0.0, 1.0) = 0.55;

// How much of the baked ORM red (occlusion) channel reaches Godot's AO built-in.
// 0.0 (default) ignores it entirely: terrain-paint's per-asset foliage bake used to
// ray-trace each asset against its own intersecting cutout cards (opaque to the AO
// rays) and wrote ~0 into this channel -- measured 0.008-0.18 on grass and 0.03-0.10
// on tree leaves in Sandy Clearing -- and since Godot scales every ambient/sky
// contribution by AO, that made foliage a black silhouette regardless of environment.
// Newer terrain-paint exports write 1.0 here, so ignoring the channel is harmless for
// them too. DebugRenderToggles' "Baked foliage AO" checkbox sets 1.0 for A/B.
uniform float baked_ao_strength : hint_range(0.0, 1.0) = 0.0;

// Thin-surface translucency: written to Godot's BACKLIGHT built-in by both real shader
// variants so light hitting the far side of a leaf or blade wraps through instead of
// leaving cull_disabled back faces flat. Per-category value from WindFoliage.PRESETS;
// 0.0 disables the term. Measured cost recorded in docs/PERFORMANCE.md.
uniform float backlight : hint_range(0.0, 1.0) = 0.0;

// Object-space (local) vertex height, captured by each variant's vertex() before
// wind_sway_vertex_offset is added (that offset never touches VERTEX.y, so capturing
// before vs. after would be equivalent regardless -- captured before purely to read as
// "the unswayed height"). Needed because VERTEX in fragment() is view-space, not
// object-space -- see wind_sway_vertex_offset's own vertex-stage VERTEX parameter for
// contrast. Deliberately a SEPARATE value from wind_sway_vertex_offset's own
// height_weight (object-space too, but intentionally unnormalized for sway falloff --
// see that function's comment): do not conflate the two or reuse one for the other.
varying float local_vertex_y;

// Occlusion fade: lets a token show through tree foliage the same way it shows
// through map geometry. See occlusion_fade_include.gdshaderinc.
#include "res://shaders/occlusion_fade_include.gdshaderinc"


// Gust envelope in 0..1 at a world XZ position: two sines travelling along the wind
// direction, softly thresholded so gusts arrive as bursts with calm between them
// rather than as a constant rocking. A little cross-wind term breaks the fronts up so
// they are not straight lines across the map.
float wind_gust(vec2 world_xz, float time) {
	vec2 dir = normalize(wind_direction);
	float along = dot(world_xz, dir);
	float across = dot(world_xz, vec2(-dir.y, dir.x));
	float k1 = 6.2831853 / 12.0;
	float k2 = 6.2831853 / 19.0;
	float wave = 0.55 * sin(along * k1 - time * gust_speed * k1)
		+ 0.45 * sin(along * k2 + across * 0.25 - time * gust_speed * 0.8 * k2 + 1.7);
	return smoothstep(-0.2, 0.9, wave);
}


// Wind-sway offset to add to VERTEX. [param vertex] is the un-swayed object-space
// VERTEX built-in; [param color] is the vertex() stage's COLOR built-in (the authored
// wind weights when use_vertex_wind is on, ignored otherwise); [param model_matrix]/
// [param time] are the vertex() stage's MODEL_MATRIX/TIME built-ins, passed in
// explicitly (see file header).
vec3 wind_sway_vertex_offset(vec3 vertex, vec4 color, mat4 model_matrix, float time) {
	// Phase derived from world-space XZ position (not a per-instance uniform) so every
	// MultiMesh instance -- each with its own MODEL_MATRIX -- naturally desyncs from
	// its neighbors with no extra per-instance data needed, same idiom water.gdshader's
	// own vertex() already uses for its bob.
	vec3 world_pos = (model_matrix * vec4(vertex, 1.0)).xyz;
	float phase = (world_pos.x + world_pos.z) * sway_frequency;
	float t = time * sway_speed + phase;
	float sway = sin(t) * sway_amplitude;
	// Local (object-space) height weights the sway so a card's base -- assumed to sit
	// at/near the mesh's local Y origin, the standard authoring convention for
	// grass/foliage cards -- barely moves while its tip sways the most. Deliberately
	// unnormalized (not divided by the mesh's own bounding height): a taller mesh
	// naturally accumulates more absolute sway at its tip than a short one, which is
	// the correct visual whether the current species preset is "grass" or "tree".
	// With authored weights the same metres-scaled quantity comes from R x mesh height,
	// so a stiff lower trunk (authored R near 0) stays still where the height rule
	// would already have it moving.
	float height_weight = use_vertex_wind ? color.r * mesh_height : max(vertex.y, 0.0);
	// Gust: the oscillation grows a little inside a gust, and on top of it the plant
	// leans over along the wind while the gust passes (1.5x the amplitude at full
	// strength, weighted by the same height/sway weight so a stiff trunk stays put).
	float gust = gust_strength > 0.0 ? wind_gust(world_pos.xz, time) : 0.0;
	sway *= 1.0 + gust_strength * (gust - 0.4);
	vec2 dir = normalize(wind_direction);
	float lean = sway_amplitude * gust_strength * gust * 1.5 * height_weight;
	vec3 offset = vec3(sway * height_weight + lean * dir.x, 0.0, sway * height_weight * 0.6 + lean * dir.y);
	if (use_vertex_wind) {
		// Flutter: small, quick, per-limb/card phase from B, graded across each card
		// by G; leaves rustle more inside a gust.
		float flutter = sin(time * flutter_speed + color.b * 6.2831853 + phase) * flutter_amplitude * color.g * (0.6 + 0.8 * gust);
		offset += vec3(flutter, flutter * 0.4, -flutter * 0.5);
	}
	// Bend, not translate: a vertex swung sideways on a stalk of its own height drops
	// by about d^2 / (2h), so the crown follows an arc instead of stretching the tree.
	float horizontal_sq = offset.x * offset.x + offset.z * offset.z;
	offset.y -= horizontal_sq / (2.0 * max(vertex.y, 0.3));
	return offset;
}


// Undoes Godot's back-face normal flip on thin double-sided foliage. Every wind
// variant is cull_disabled, and Godot negates NORMAL on back faces before fragment()
// runs, so a blade whose authored normal is biased upward, or a leaf card carrying its
// canopy's outward volume normal, shades from a downward/inward normal whenever its
// back faces the camera and goes black under a low sun. Treecube's Blender materials
// apply the identical mix(N, -N, Backfacing) correction, so both tools agree.
vec3 two_sided_foliage_normal(vec3 normal, bool front_facing) {
	return front_facing ? normal : -normal;
}


// Computes PBR and occlusion-fade fragment values. Uses out-parameters to pass
// results back to the caller (which then assigns them to built-ins) -- a workaround
// for Godot's limitation that output built-ins can only be assigned directly inside
// fragment(), not from a called function. Samples textures, unpacks ORM, applies
// normal mapping, and calls apply_occlusion_fade() to determine final alpha values.
// Caller is responsible for assigning the out-parameters to their corresponding
// built-ins and setting variant-specific ALPHA_SCISSOR_THRESHOLD/antialiasing values.
void apply_wind_foliage_pbr(
	vec2 uv,
	mat4 inv_view_matrix,
	vec3 normal,
	vec3 vertex_view,
	mat4 view_matrix,
	vec2 frag_coord,
	vec2 viewport_size,
	float vertex_local_y,
	out vec3 out_albedo,
	out float out_alpha,
	out float out_ao,
	out float out_roughness,
	out float out_metallic,
	out vec3 out_normal_map
) {
	vec4 albedo_sample = texture(albedo_texture, uv);
	out_albedo = albedo_sample.rgb;
	out_alpha = albedo_sample.a;

	// Normalized (0 at base, 1 at tip) height for the base-dark/tip-light gradient --
	// guarded against blade_height == 0.0 (trees, or a degenerate/flat mesh) so this
	// never divides by zero: h resolves to 1.0 in that case, and mix(base_darken, 1.0,
	// 1.0) == 1.0, a pure no-op on out_albedo.
	float h = blade_height > 0.0 ? clamp(vertex_local_y / blade_height, 0.0, 1.0) : 1.0;
	out_albedo *= mix(base_darken, 1.0, h);

	vec3 orm = texture(orm_texture, uv).rgb;
	out_ao = mix(1.0, orm.r, baked_ao_strength);
	out_roughness = orm.g;
	out_metallic = orm.b;

	if (has_normal_texture) {
		out_normal_map = texture(normal_texture, uv).rgb;
	} else {
		out_normal_map = vec3(0.0);
	}

	vec3 world_normal = mat3(inv_view_matrix) * normal;
	apply_occlusion_fade(world_normal, vertex_view, view_matrix, frag_coord, viewport_size);
}
