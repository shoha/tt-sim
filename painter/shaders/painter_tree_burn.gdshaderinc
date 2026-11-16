// A painted tree an event burns (TREE_BURN; card painter-fire; docs/systems/painter.md "Fire and
// events"). Included by the stroke and block-in bodies only in their *_burn variants, so a tree
// that burns nothing runs none of this and costs what it did.
//
// The burn is one number a tree, an instance uniform on the five nodes of its pivot
// (PainterTrees.set_burn), on FireSweep.burn_progress's scale: 0 green, BURN_RATE 1.7 at the end of
// the tree's burn. Each mark (a stroke or a piece of a block-in mass) catches at BURN_UP of its
// height up the tree plus BURN_NOISE of its own draw, the same moments FireSweep's crown tongues
// are timed to (CATCH_HEIGHT, CATCH_NOISE), so a flame rises where the paint is hot. Then the mark
// is drawn in three flat bands, never a ramp (a painter's flame: a cream-yellow core, amber, a deep
// red ember), goes to charcoal and a leaf mark is gone BURN_LEAF_GONE later (wood stays: the
// charred trunk and limbs are the snag). A few char marks keep a red ember for a while.

instance uniform float burn : hint_range(0.0, 3.0) = 0.0;

// FireSweep.CATCH_HEIGHT and CATCH_NOISE: when a mark at `up` (0 foot .. 1 top) and draw `r` catches.
const float BURN_UP = 0.55;
const float BURN_NOISE = 0.25;
// How long a mark is in its ember bands, and when a leaf mark is gone after catching.
const float BURN_EMBER = 0.3;
const float BURN_LEAF_GONE = 0.62;

// How far past catching a mark at `up` with draw `r` is (negative: not yet).
float burn_since(float up, float r) {
	return burn - (BURN_UP * up + BURN_NOISE * r);
}

// A leaf mark's end: gone, a little later where its draw is high, so the crown goes in patches.
bool burn_gone(float s, float r, bool leaf) {
	return leaf && s > BURN_LEAF_GONE + 0.16 * r;
}

// The mark `s` past catching, in the painted fire's colours (linear), and how much of it glows
// (`heat`, 0..1, the emission's share of the colour).
vec3 burn_paint(vec3 col, float s, float r, out float heat) {
	heat = 0.0;
	if (s <= 0.0) {
		return col;
	}
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 char_c = mix(vec3(0.03, 0.022, 0.02), vec3(0.075, 0.052, 0.04), r) + vec3(lum * 0.06);
	float e = s / BURN_EMBER;
	if (e < 1.0) {
		if (e < 0.22) {
			// A warm gold, not cream: a cream mark tonemaps to white and reads as confetti.
			heat = 0.75;
			return vec3(1.0, 0.64, 0.14);
		}
		if (e < 0.55) {
			heat = 0.7;
			return vec3(1.0, 0.4, 0.06);
		}
		heat = 0.55;
		return vec3(0.62, 0.14, 0.05);
	}
	float keep = step(0.86, r) * (1.0 - smoothstep(1.0, 2.6, e));
	heat = keep * 0.35;
	return mix(char_c, vec3(0.5, 0.11, 0.03), keep);
}
