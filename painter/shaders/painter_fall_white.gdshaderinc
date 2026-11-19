// The fall white (card painter-fall-frame-foam): one foam over a waterfall's brink, its curtain and
// its foot, drawn by the painted water (painter_water.gdshader) and the painted curtain
// (painter_waterfall.gdshader) from the same frame and the same function, so the white is one shape
// across both joins instead of a lip roll on the curtain and a ring of its own on the pool.
//
// The frame is WaterFallFrames' vertex contract (utils/water_fall_frames.gd): CUSTOM0 = (lip x,
// lip z, dir x, dir z), CUSTOM1 = (left half-width, right half-width, x_pool, drop), map space,
// all zeros for no fall. The caller passes them through FLAT varyings and the fragment's map XZ.
// Its pseudo-arc is metres along the water from the lip, upstream negative: on the river and the
// pool `along` upstream of the lip and along + drop past it, on the curtain max(along, 0) + metres
// fallen; 0 at the lip on both sides and x_pool + drop where the curtain's middle meets the pool.
// Include after painter_noise.gdshaderinc (be_n2).

// The brink: a gradient, not a shape. The river whitens over its last FW_BRINK_UP_M to full white
// at the lip, holds it FW_BRINK_DOWN_M down the curtain and gives it back to the curtain's own
// streaks by FW_BRINK_DOWN_END_M, wobbled across by FW_WOBBLE, out to FW_BRINK_SIDE half-widths.
// Round 2's two-valued band starting 0.55 m upstream read as a white bar laid across the river and
// drew the lip's largest colour step (dL 12 against main's 7 to 10, painter-fall-frame-foam).
const float FW_BRINK_UP_M = 0.7;
const float FW_BRINK_DOWN_M = 0.1;
const float FW_BRINK_DOWN_END_M = 0.8;
const float FW_BRINK_SIDE = 0.85;
const float FW_BRINK_SIDE_SOFT = 1.05;
const float FW_WOBBLE = 0.18;
// The foot: white from FW_FOOT_BEFORE_M up the curtain to a reach past the pool point that grows
// with the drop (FW_REACH_*), churned by a noise of FW_CHURN of the reach, out to FW_FOOT_SIDE
// half-widths.
const float FW_FOOT_BEFORE_M = 0.35;
const float FW_FOOT_BEFORE_SOFT_M = 0.1;
const float FW_REACH_BASE_M = 0.5;
const float FW_REACH_PER_DROP = 0.35;
const float FW_REACH_MIN_M = 0.6;
const float FW_REACH_MAX_M = 1.5;
const float FW_CHURN = 0.45;
const float FW_FOOT_SIDE = 1.0;
const float FW_FOOT_SIDE_SOFT = 1.45;
// Two values, the white and none, with a soft edge between; the shapes change FW_STEP_HZ times
// a second (stepped, nothing slides).
const float FW_EDGE_LOW = 0.42;
const float FW_EDGE_HIGH = 0.58;
const float FW_STEP_HZ = 2.0;
// The halo: the plunge's aerated water past the foot white on the pool, a gradient of the same foam
// out of the white's own edge (the same churned distance, full where the white ends) to the pool's
// wash over FW_HALO_LEN_M, out to FW_HALO_SIDE half-widths. Round 2's halo was a second
// two-valued shape in a fixed pale turquoise with its own churn: it read as a stripe with a wavy
// top under the white, and where its churn dropped out the deep pool showed as a dark sliver right
// under the white. The gradient ends inside the frame's window (WaterFallFrames.WINDOW_DOWN_M,
// WINDOW_SIDE), so no triangle cuts it off.
const float FW_HALO_START = 0.4;
const float FW_HALO_LEN_M = 1.0;
const float FW_HALO_SIDE = 1.1;
const float FW_HALO_SIDE_SOFT = 1.5;


// The foot's reach past the pool point for a fall `drop` high (metres of arc).
float fall_foot_reach(float drop) {
	return clamp(FW_REACH_BASE_M + FW_REACH_PER_DROP * drop, FW_REACH_MIN_M, FW_REACH_MAX_M);
}


// How far past the foot's pool point pseudo-arc `a` lies, in reaches of the foot white, churned
// across and stepped in time (`t_step`): the white ends at about 0.5, the halo starts there.
float fall_foot_distance(float a, float a_pool, float drop, float across, float t_step) {
	float reach = fall_foot_reach(drop);
	float churn = be_n2(vec2(across * 1.6 + 4.1, (a - a_pool) * 2.2 - t_step * 0.6));
	return (a - a_pool) / reach + FW_CHURN * (churn - 0.5);
}


// The white at pseudo-arc `a` of a fall `drop` high meeting its pool at `a_pool`, `across` metres
// off the course where the water is `half_w` wide on that side: 0..1.
float fall_white_arc(float a, float a_pool, float drop, float across, float half_w) {
	float q = abs(across) / max(half_w, 0.05);
	float t_step = floor(TIME * FW_STEP_HZ);
	float n = be_n2(vec2(across * 2.3 + 1.7, t_step * 0.37));
	float wob = FW_WOBBLE * (n - 0.5);
	float brink = smoothstep(-FW_BRINK_UP_M, 0.0, a + wob)
		* (1.0 - smoothstep(FW_BRINK_DOWN_M, FW_BRINK_DOWN_END_M, a + wob));
	brink *= 1.0 - smoothstep(FW_BRINK_SIDE, FW_BRINK_SIDE_SOFT, q);
	float foot = 1.0 - smoothstep(0.0, 1.0, fall_foot_distance(a, a_pool, drop, across, t_step));
	foot *= smoothstep(a_pool - FW_FOOT_BEFORE_M, a_pool - FW_FOOT_BEFORE_SOFT_M, a);
	foot *= 1.0 - smoothstep(FW_FOOT_SIDE, FW_FOOT_SIDE_SOFT, q);
	return max(brink, smoothstep(FW_EDGE_LOW, FW_EDGE_HIGH, foot));
}


// The halo at pseudo-arc `a` on the pool (arguments as fall_white_arc): 1 where the foot white
// ends, falling smoothly to 0 over FW_HALO_LEN_M; the caller takes the max with the white.
float fall_halo_arc(float a, float a_pool, float drop, float across, float half_w) {
	float q = abs(across) / max(half_w, 0.05);
	float reach = fall_foot_reach(drop);
	float d = fall_foot_distance(a, a_pool, drop, across, floor(TIME * FW_STEP_HZ));
	float h = 1.0 - smoothstep(FW_HALO_START, FW_HALO_START + FW_HALO_LEN_M / reach, d);
	h *= smoothstep(a_pool - FW_FOOT_BEFORE_M, a_pool - FW_FOOT_BEFORE_SOFT_M, a);
	return h * (1.0 - smoothstep(FW_HALO_SIDE, FW_HALO_SIDE_SOFT, q));
}


// Along (x) and across (y) of map point `p` in frame `f0`, and the half-width on its side.
vec3 fall_frame_point(vec4 f0, vec4 f1, vec2 p) {
	vec2 d = p - f0.xy;
	float across = dot(d, vec2(f0.w, -f0.z));
	return vec3(dot(d, f0.zw), across, across < 0.0 ? f1.x : f1.y);
}


// The white of the river or the pool at map point `p` (0 with no frame).
float fall_white_water(vec4 f0, vec4 f1, vec2 p) {
	if (dot(f0.zw, f0.zw) < 0.25) {
		return 0.0;
	}
	vec3 fp = fall_frame_point(f0, f1, p);
	if (fp.x < 0.0) {
		return fall_white_arc(fp.x, f1.z + f1.w, f1.w, fp.y, fp.z);
	}
	float a = fp.x + f1.w;
	float a_pool = f1.z + f1.w;
	float white = fall_white_arc(a, a_pool, f1.w, fp.y, fp.z);
	return max(white, fall_halo_arc(a, a_pool, f1.w, fp.y, fp.z));
}


// The white of the curtain at map point `p`, `fallen` metres under the lip (0 with no frame).
float fall_white_curtain(vec4 f0, vec4 f1, vec2 p, float fallen) {
	if (dot(f0.zw, f0.zw) < 0.25) {
		return 0.0;
	}
	vec3 fp = fall_frame_point(f0, f1, p);
	return fall_white_arc(max(fp.x, 0.0) + fallen, f1.z + f1.w, f1.w, fp.y, fp.z);
}
