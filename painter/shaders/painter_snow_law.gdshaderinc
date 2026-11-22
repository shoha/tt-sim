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
 *                curve for a lid, a coping, a boulder's shoulder and a bush's lobe (a box piece
 *                asks with its face's own normal, not a smoothed one, so a jamb holds none). A roof
 *                sheds sooner (snow_shed, card snow-steep-roofs): a long smooth slope of tile or
 *                slate holds none steeper than 60 degrees and all of it from about 52, so a spire,
 *                a tower's pointed hat and the steep part of a bell roof read clean in their own
 *                colour, while a cottage's roof (36 to 50 degrees) keeps its whole layer. (The
 *                small rounded forms keep the steeper curve: a cap on a boulder's shoulder or a
 *                barrel's bevel is how snow sits on them; one curve for both no longer fits.)
 *                procgen declares no snow body for a cone steeper than the same 60 degrees
 *                (ProcgenSnowTops.CONE_UP_MIN 0.5);
 *   the edge     where a face holds only part, which part keeps it: a few bold soft shapes of one
 *                broad world noise (about two metres across), so a boulder's shoulder, a barrel's
 *                bevel and a bell roof's flare break the same way and never in a stipple or a hard
 *                frost line (the painted cap a spire wore down from its tip, card snow-one-law, read
 *                as a smudge: owner, 2026-11-22);
 *   the rim      where the layer turns away from the sky (a rounded top's shoulder, not a roof) or
 *                ends at its own soft edge, its paint rounds into the shade (snow_turn and the
 *                edge's inside);
 *   the ledge    a structure's level face narrower than a ledge holds none (snow_ledge, from the
 *                face's width the mesh carries: UV2.y on a street lot, CUSTOM1 on a hand-drawn
 *                house): a shutter's batten tops and a casing's jamb ends drew white ladders.
 * The edge is soft in metres (about 0.15 m on the broad shapes). Needs painter_noise.gdshaderinc
 * first (p_noise). No texture reads, no derivatives (callers branch around it per fragment).
 */

#ifndef PAINTER_SNOW_LAW
#define PAINTER_SNOW_LAW

// The face's up (its normal's Y) where the hold starts and where it is whole, on every face but a
// roof's (78 and 64 degrees from flat).
const float SNOW_HOLD_LO = 0.2;
const float SNOW_HOLD_HI = 0.44;
// The same on a roof (snow_shed): 60 and about 52 degrees from flat.
const float SNOW_SHED_LO = 0.5;
const float SNOW_SHED_HI = 0.62;
// The size of the broad shapes' noise (1/m): about two metres across.
const float SNOW_EDGE_FREQ = 0.55;

// The direction toward the sun (xyz) and its weight (FoliageLight), for the law's includers (the
// snow paint and the grass marks; declared once, here).
global uniform vec4 foliage_sun;

// How much snow a face whose normal's up is `up` holds (0 to 1), with the snow on (`on` 1) or off.
float snow_hold(float on, float up) {
	return clamp(on, 0.0, 1.0) * smoothstep(SNOW_HOLD_LO, SNOW_HOLD_HI, up);
}

// How much snow a roof face whose normal's up is `up` holds (0 to 1): a long smooth slope sheds
// what a small rounded form would hold, so a roof steeper than 60 degrees holds none.
float snow_shed(float on, float up) {
	return clamp(on, 0.0, 1.0) * smoothstep(SNOW_SHED_LO, SNOW_SHED_HI, up);
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

// The law at world point `wp` on a face whose up is `up` (the caller's: its normal's y, a box
// piece's flat face's, or a form's or a lobe's), with the snow on (`on` 1) or off, on a roof
// (`roof`: snow_shed) or any other face (snow_hold). x the cover (0 to 1), y the hold before the
// edge, z the rim (1 where the layer turns from the sky or near its own edge).
vec3 snow_law(float on, float up, vec3 wp, bool roof) {
	float hold = roof ? snow_shed(on, up) : snow_hold(on, up);
	float broad = p_noise(wp * SNOW_EDGE_FREQ + 3.0);
	// The edge moves far where the face holds little and barely where it holds it all.
	float x = hold + (broad - 0.5) * 1.2 * (1.0 - 0.75 * hold);
	float cover = smoothstep(0.45, 0.55, x) * smoothstep(0.0, 0.1, hold);
	// A roof's slope is no rounded top: it rims only at its own edge.
	float rim = cover * max(1.0 - smoothstep(0.55, 0.8, x), roof ? 0.0 : snow_turn(up));
	return vec3(cover, hold, rim);
}

#endif
