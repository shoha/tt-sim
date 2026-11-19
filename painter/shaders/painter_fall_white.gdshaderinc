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

// The brink: white from FW_BRINK_UP_M upstream to FW_BRINK_DOWN_M over the curtain (soft edges),
// wobbled across by FW_WOBBLE, out to FW_BRINK_SIDE half-widths.
const float FW_BRINK_UP_M = 0.55;
const float FW_BRINK_UP_SOFT_M = 0.08;
const float FW_BRINK_DOWN_M = 0.2;
const float FW_BRINK_DOWN_SOFT_M = 0.45;
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
// The brink's edge is softer: the river whitens over about 0.25 m as it speeds up to the lip (a
// crisp edge there read as a white bar laid across the river, and drew the largest colour step of
// the lip in the continuity probe, painter-fall-frame-foam round 2).
const float FW_BRINK_EDGE_LOW = 0.25;
const float FW_BRINK_EDGE_HIGH = 0.75;
// The halo: the plunge's aerated water past the foot white on the pool, one more bold shape
// FW_HALO_REACH times the foot's reach and out to FW_HALO_SIDE half-widths, so the foam steps down
// to the wash through a pale tone instead of jumping from white to the deep band.
const float FW_HALO_REACH = 1.9;
const float FW_HALO_SIDE = 1.2;
const float FW_HALO_SIDE_SOFT = 1.7;


// The foot's reach past the pool point for a fall `drop` high (metres of arc).
float fall_foot_reach(float drop) {
	return clamp(FW_REACH_BASE_M + FW_REACH_PER_DROP * drop, FW_REACH_MIN_M, FW_REACH_MAX_M);
}


// The white at pseudo-arc `a` of a fall `drop` high meeting its pool at `a_pool`, `across` metres
// off the course where the water is `half_w` wide on that side: 0..1.
float fall_white_arc(float a, float a_pool, float drop, float across, float half_w) {
	float q = abs(across) / max(half_w, 0.05);
	float t_step = floor(TIME * FW_STEP_HZ);
	float n = be_n2(vec2(across * 2.3 + 1.7, t_step * 0.37));
	float wob = FW_WOBBLE * (n - 0.5);
	float brink = smoothstep(-FW_BRINK_UP_M, -FW_BRINK_UP_SOFT_M, a + wob)
		* (1.0 - smoothstep(FW_BRINK_DOWN_M, FW_BRINK_DOWN_SOFT_M, a + wob));
	brink *= 1.0 - smoothstep(FW_BRINK_SIDE, FW_BRINK_SIDE_SOFT, q);
	float reach = fall_foot_reach(drop);
	float churn = be_n2(vec2(across * 1.6 + 4.1, (a - a_pool) * 2.2 - t_step * 0.6));
	float foot = 1.0 - smoothstep(0.0, reach, a - a_pool + FW_CHURN * (churn - 0.5) * reach);
	foot *= smoothstep(a_pool - FW_FOOT_BEFORE_M, a_pool - FW_FOOT_BEFORE_SOFT_M, a);
	foot *= 1.0 - smoothstep(FW_FOOT_SIDE, FW_FOOT_SIDE_SOFT, q);
	return max(
		smoothstep(FW_BRINK_EDGE_LOW, FW_BRINK_EDGE_HIGH, brink),
		smoothstep(FW_EDGE_LOW, FW_EDGE_HIGH, foot)
	);
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
	float a = fp.x < 0.0 ? fp.x : fp.x + f1.w;
	return fall_white_arc(a, f1.z + f1.w, f1.w, fp.y, fp.z);
}


// The halo of the pool at map point `p` (see FW_HALO_REACH): 0..1, 0 upstream of the lip and with
// no frame.
float fall_halo_water(vec4 f0, vec4 f1, vec2 p) {
	if (dot(f0.zw, f0.zw) < 0.25) {
		return 0.0;
	}
	vec3 fp = fall_frame_point(f0, f1, p);
	if (fp.x < 0.0) {
		return 0.0;
	}
	float a = fp.x + f1.w;
	float a_pool = f1.z + f1.w;
	float q = abs(fp.y) / max(fp.z, 0.05);
	float t_step = floor(TIME * FW_STEP_HZ);
	float reach = fall_foot_reach(f1.w) * FW_HALO_REACH;
	float churn = be_n2(vec2(fp.y * 1.1 + 9.3, (a - a_pool) * 1.4 - t_step * 0.4));
	float h = 1.0 - smoothstep(0.0, reach, a - a_pool + FW_CHURN * (churn - 0.5) * reach);
	h *= smoothstep(a_pool - FW_FOOT_BEFORE_M, a_pool - FW_FOOT_BEFORE_SOFT_M, a);
	h *= 1.0 - smoothstep(FW_HALO_SIDE, FW_HALO_SIDE_SOFT, q);
	return smoothstep(FW_EDGE_LOW, FW_EDGE_HIGH, h);
}


// The white of the curtain at map point `p`, `fallen` metres under the lip (0 with no frame).
float fall_white_curtain(vec4 f0, vec4 f1, vec2 p, float fallen) {
	if (dot(f0.zw, f0.zw) < 0.25) {
		return 0.0;
	}
	vec3 fp = fall_frame_point(f0, f1, p);
	return fall_white_arc(max(fp.x, 0.0) + fallen, f1.z + f1.w, f1.w, fp.y, fp.z);
}
