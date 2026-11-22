/*
 * The snow law (card snow-one-law, 2026-11-21; ported from spike 1's painter-snow-spike1-law with
 * the structure snow's switch in place of its amount): the one rule that says which faces hold
 * snow and how the cover's edge looks, for every painted face that has no snow body of its own.
 * Owner: "a unifying system for determining coverage and accumulation for snow", so a boulder, a
 * wall's coping, a bench and a roof answer the same question the same way. Its users:
 * painter_snow.gdshaderinc (included by the street lots' and the hand-drawn houses' structure
 * shaders and the village props', which paint the layer and give it a body),
 * painter_yard.gdshader (a yard's shrubs, boulders, lids and steps) and
 * painter_selector.gdshaderinc (the scatter's rocks, logs, leaf masses, bushes and a wall's ivy,
 * in painter_plant and painter_solid). Each family keeps its own paint: the law decides the cover,
 * the family paints it. Not its users: snow bodies and the cells on a record (their own mesh), the
 * crowns and conifers (their deposit and needle-snow rules), grass tufts (their bury line and dab
 * caps) and the ground (its palette).
 *
 * The law. Snow is on or off (`on`, the shader's `snow`: 1 in winter, 0 else; no amount since card
 * snow-tops-builder, PainterBuildings.snow_switch). Then:
 *   the hold     which faces hold it, by the face's normal's up alone (snow_hold): none steeper
 *                than about 78 degrees, all of it from about 64 degrees and flatter, the same
 *                curve for a roof, a lid, a coping, a boulder's shoulder and a bush's lobe (a box
 *                piece asks with its face's own normal, not a smoothed one, so a jamb holds none);
 *   the edge     where a face holds only part, which part keeps it. A face that knows its top (a
 *                roof's h, 0 at the eave to 1 at the tip or ridge) keeps it at the top: a spire
 *                wears a cap of a few uneven drifts down from its tip, each facet its own share and
 *                the side facing the sun nearly bare (snow_cap_edge). Any other face keeps it in a
 *                few bold soft shapes of one broad world noise (about two metres across), so a
 *                boulder's shoulder and a barrel's bevel break the same way and never in a stipple
 *                or a hard frost line;
 *   the rim      where the layer turns away from the sky (a rounded top's shoulder) or ends at its
 *                own soft edge, its paint rounds into the shade (snow_turn and the edge's inside);
 *   the ledge    a structure's level face narrower than a ledge holds none (snow_ledge, from the
 *                face's width the mesh carries: UV2.y on a street lot, CUSTOM1 on a hand-drawn
 *                house): a shutter's batten tops and a casing's jamb ends drew white ladders.
 * The edge is soft in metres (about 0.15 m on the broad shapes, 2.5 percent of a roof's run on a
 * cap). Needs painter_noise.gdshaderinc first (p_noise, p_n2). No texture reads, no derivatives
 * (callers branch around it per fragment).
 */

#ifndef PAINTER_SNOW_LAW
#define PAINTER_SNOW_LAW

// The face's up (its normal's Y) where the hold starts and where it is whole: the roofs' curve
// (a steeper start, 0.3 to 0.55, left a spire's cap at its tip alone: card snow-one-law round 1).
const float SNOW_HOLD_LO = 0.2;
const float SNOW_HOLD_HI = 0.44;
// A face that knows its top holds a cap down to this up (near upright: a spire's run, a finial).
const float SNOW_STAND_LO = 0.08;
const float SNOW_STAND_HI = 0.16;
// `top` for a face that does not know where its top is.
const float SNOW_NO_TOP = -1.0;
// The size of the broad shapes' noise (1/m): about two metres across.
const float SNOW_EDGE_FREQ = 0.55;

// The direction toward the sun (xyz) and its weight (FoliageLight): a cap thins on the side facing
// it (snow_cap_edge).
global uniform vec4 foliage_sun;

// How much snow a face whose normal's up is `up` holds (0 to 1), with the snow on (`on` 1) or off.
float snow_hold(float on, float up) {
	return clamp(on, 0.0, 1.0) * smoothstep(SNOW_HOLD_LO, SNOW_HOLD_HI, up);
}

// The ledge (card snow-one-law rounds 3 and 4): a level face narrower than SNOW_LEDGE_LO metres
// holds no snow, one from SNOW_LEDGE_HI holds it all. A shutter's batten tops (5 to 7.7 cm), a
// window casing's jamb end (7.8 cm), a door case's head (6.5 cm) and a thin timber's top fall under
// it; a frame head (15 cm), a lintel (16 cm) and a sill (19 cm) keep their snow.
const float SNOW_LEDGE_LO = 0.08;
const float SNOW_LEDGE_HI = 0.12;

// The share of the law's cover a structure's non-roof face keeps for its level face's `width`
// (StructureGeometry.with_ledges; 0: wide, or no level face).
float snow_ledge(float width) {
	return width > 0.0 ? smoothstep(SNOW_LEDGE_LO, SNOW_LEDGE_HI, width) : 1.0;
}

// Where a rounded form turns away from the sky (0 to 1), just above the whole hold: there a cap's
// paint rounds into its shade (a barrel's rim, a haystack's or a boulder's shoulder).
float snow_turn(float up) {
	return 1.0 - smoothstep(0.5, 0.85, up);
}

// The lower edge of a cap on a face that knows its top (in `top`'s units: below it the face is
// bare), for a face holding `hold` (snow_hold with the snow on), at `along` metres along its eave,
// with normal `n`, of a building whose seed is `seed`. Past the eave where the face holds it all,
// wandering in a few broad soft tongues along it; on a steep face a cap of a few uneven drifts
// (card painter-roof-round5, owner on one regular cap: "Rework"): each facet its own share (a slow
// noise of its facing, continuous round a cone and one value per face of a Taper roof), the side
// facing the sun nearly bare, so the roof's own colour shows below an edge broken round the roof.
float snow_cap_edge(float hold, float along, vec3 n, float seed) {
	float tongue = p_n2(vec2(along * 1.3, 5.0), 173.0);
	float sway = p_n2(vec2(along * 0.4, 9.0), 174.0);
	float edge = mix(0.55, -0.3, hold) + ((tongue - 0.5) * 0.12 + (sway - 0.5) * 0.1) * hold;
	vec2 face = n.xz / max(length(n.xz), 1e-4);
	float facet = p_n2(face * 1.2 + vec2(seed, seed * 0.7), 191.0);
	vec2 sun = foliage_sun.xz;
	float sunward = length(sun) > 0.01 ? dot(face, normalize(sun)) : 0.0;
	float e1 = p_n2(face * 3.0 + vec2(along * 0.9, seed), 193.0);
	float e2 = p_n2(face * 7.0 + vec2(along * 1.7, seed + 3.0), 194.0);
	float drifts = (facet - 0.5) * 0.45 + 0.3 * smoothstep(0.0, 0.85, sunward)
		+ (e1 - 0.5) * 0.28 + (e2 - 0.5) * 0.12;
	return edge + (1.0 - hold) * drifts;
}

// The law at world point `wp` on a face whose normal is `n` (`up` the up the caller asks with:
// n.y, or a form's or a lobe's up), with the snow on (`on` 1) or off, at `top` up the face (0 to 1)
// where the face knows its top, else SNOW_NO_TOP; `seed` a building's (the cap's drifts). x the
// cover (0 to 1), y the hold before the edge, z the rim (1 where the layer turns from the sky or
// near its own edge), w the cap's lower edge in `top`'s units (0 on a face with no top).
vec4 snow_law(float on, float up, vec3 wp, vec3 n, float top, float seed) {
	float hold = snow_hold(on, up);
	if (top >= 0.0) {
		vec2 flat_n = n.xz;
		float flat_len = length(flat_n);
		vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
		float along = dot(wp.xz, vec2(-down.y, down.x));
		float edge = snow_cap_edge(smoothstep(SNOW_HOLD_LO, SNOW_HOLD_HI, up), along, n, seed);
		float cover = clamp(on, 0.0, 1.0) * smoothstep(SNOW_STAND_LO, SNOW_STAND_HI, up)
			* smoothstep(edge - 0.025, edge + 0.025, top);
		return vec4(cover, hold, 0.0, edge);
	}
	float broad = p_noise(wp * SNOW_EDGE_FREQ + 3.0);
	// The edge moves far where the face holds little and barely where it holds it all.
	float x = hold + (broad - 0.5) * 1.2 * (1.0 - 0.75 * hold);
	float cover = smoothstep(0.45, 0.55, x) * smoothstep(0.0, 0.1, hold);
	float rim = cover * max(1.0 - smoothstep(0.55, 0.8, x), snow_turn(up));
	return vec4(cover, hold, rim, 0.0);
}

#endif
