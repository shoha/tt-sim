shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, world_vertex_coords;

/*
 * The painted terrain's shadow caster (the back-face twin of each terrain chunk)
 * ==============================================================================
 *
 * Drawn in shadow passes only (the twin is SHADOWS_ONLY), with the front faces culled: the shadow
 * map holds the far side of each hill, so ground that faces the sun is never shadowed by its own
 * surface (docs/systems/painter.md "Ground shading field").
 * A back face is a surface that things stand right in front of: a waterfall's sheet centimetres
 * off the cliff behind it, water at a bank, grass on a slope turned from the sun. Such a receiver
 * is in the terrain's shadow by the width of the engine's shadow bias or less, and the bias then
 * lights it in stripes (the fall's diagonal hatch, card painter-ground-robust-finish). So the
 * caster is moved `push_m` toward the light, in depth only: whatever stands at or behind a face
 * turned from the light is inside its shadow by at least that margin. In a shadow pass the view is
 * the light's: a directional light's rays run along the view's own axis, a point or spot light's
 * come from the view's origin, so the silhouette the light sees does not move.
 * The price is at a crest, where a back face moved toward the light can pass in front of the lit
 * ground just before it (where the hill is thinner along the ray than the margin less the bias).
 * Measured on the falls map at sun elevations 10 and 48: with no push the fall is hatched, and at
 * a low sun mostly lit; 0.05 and 0.1 m still hatch it; 0.3 m is clean at every hour, and no
 * crest took a dark line.
 *
 * MANAGED BY: TerrainBackCaster (utils/terrain/terrain_back_caster.gd).
 */

// Metres the caster moves toward the light.
uniform float push_m = 0.3;

void vertex() {
	if (PROJECTION_MATRIX[3][3] == 1.0) {
		// An orthographic pass (the sun): toward the light is the view's +z.
		VERTEX += normalize(INV_VIEW_MATRIX[2].xyz) * push_m;
	} else {
		vec3 to_light = INV_VIEW_MATRIX[3].xyz - VERTEX;
		float d = length(to_light);
		VERTEX += to_light / max(d, 0.0001) * min(push_m, d * 0.5);
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
}
