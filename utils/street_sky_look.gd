class_name StreetSkyLook
extends RefCounted

## The per-biome numbers of the eye view's painted sky (shaders/street_sky.gdshader, installed by
## EyeSky), and the pure maths around them. A biome's look is a small table of shader uniforms: five
## colours (zenith, horizon haze, far ridge, near ridge, foot) and six numbers (ridge height,
## lattice seed and period, tree-crown height, crowns per turn and shape), plus a few optional
## extras. The foot colour is also the depth fog colour and the colour the ground skirt fades to,
## so each biome picks it near its own ground. "No sameness": every biome has its own seed, its
## own silhouette (rolling hills, tree-lines, cones, mesas) and its own light; a map adds its
## seed to the lattice seed so two maps of one biome do not share a skyline.
##
## Biome ids in a map document carry a season and a variant ("temperate_forest_summer_s1"), so a
## look is found by the longest table key the id starts with. A map without a biome (or one this
## table does not know) gets DEFAULT.

## Depth fog in the eye view, metres: the nearest it ever begins and ends (owner verdict,
## 2026-11-02: 25 to 85 m). The fog is scaled to the map (fog_range): it begins and ends further
## out as the map's far side does, so a small valley keeps its own detail clear and a large map is
## hazed only toward its far edge, where the ground melts into the ridge foot.
const FOG_BEGIN_M := 25.0
const FOG_END_M := 85.0
const FOG_CURVE := 1.0
## The fog's begin and end as fractions of the eye's reach (the distance to the map's farthest
## point): begin three quarters of the way out, end half as far again past the farthest edge.
const FOG_BEGIN_REACH := 0.75
const FOG_END_REACH := 1.5

const DEFAULT := "default"

## Keys every look must carry (the card's "about 11 numbers").
const REQUIRED_KEYS: Array[String] = [
	"zenith_color",
	"horizon_color",
	"far_color",
	"near_color",
	"foot_color",
	"height_deg",
	"noise_seed",
	"noise_period",
	"teeth_deg",
	"teeth_freq",
	"tree_shape",
]

## Valid ranges of the numeric keys (the shader's hints).
const RANGES := {
	"height_deg": Vector2(4.0, 45.0),
	"noise_seed": Vector2(0.0, 200.0),
	"noise_period": Vector2(2.0, 24.0),
	"teeth_deg": Vector2(0.0, 3.0),
	"teeth_freq": Vector2(8.0, 160.0),
	"tree_shape": Vector2(0.0, 1.0),
	"angular": Vector2(0.0, 1.0),
	"cloud_cover": Vector2(0.0, 1.0),
	"haze_far": Vector2(0.0, 1.0),
	"mist": Vector2(0.0, 1.0),
	"lit_amount": Vector2(0.0, 1.0),
	"warm_amount": Vector2(0.0, 1.0),
	"sun_glow": Vector2(0.0, 2.0),
	"cloud2_cover": Vector2(0.0, 1.0),
	"snow_amount": Vector2(0.0, 1.0),
}

## Shared defaults: the optional keys a look may leave out.
const COMMON := {
	"warm_color": Color(1.0, 0.85, 0.63),
	"cloud_shade": Color(0.62, 0.64, 0.88),
	"angular": 0.0,
	"cloud_cover": 0.7,
	"haze_far": 0.6,
	"mist": 0.5,
	"lit_amount": 0.5,
	"warm_amount": 0.4,
	"sun_glow": 0.6,
	"cloud2_cover": 0.45,
	"snow_amount": 0.0,
}

const LOOKS := {
	"default":
	{
		"zenith_color": Color(0.30, 0.52, 0.90),
		"horizon_color": Color(0.78, 0.89, 0.98),
		"far_color": Color(0.45, 0.60, 0.84),
		"near_color": Color(0.12, 0.45, 0.40),
		"foot_color": Color(0.38, 0.62, 0.44),
		"height_deg": 18.0,
		"noise_seed": 5.0,
		"noise_period": 5.0,
		"teeth_deg": 0.6,
		"teeth_freq": 50.0,
		"tree_shape": 0.3,
		"angular": 0.1,
	},
	"temperate_forest":
	{
		"zenith_color": Color(0.26, 0.46, 0.90),
		"horizon_color": Color(0.76, 0.88, 0.97),
		"far_color": Color(0.42, 0.58, 0.82),
		"near_color": Color(0.07, 0.38, 0.34),
		"foot_color": Color(0.30, 0.56, 0.46),
		"height_deg": 20.0,
		"noise_seed": 11.0,
		"noise_period": 5.0,
		"teeth_deg": 1.3,
		"teeth_freq": 60.0,
		"tree_shape": 0.35,
	},
	"birch_woodland":
	{
		"zenith_color": Color(0.32, 0.56, 0.93),
		"horizon_color": Color(0.82, 0.92, 0.97),
		"warm_color": Color(1.0, 0.9, 0.68),
		"far_color": Color(0.52, 0.68, 0.84),
		"near_color": Color(0.27, 0.52, 0.27),
		"foot_color": Color(0.50, 0.72, 0.38),
		"height_deg": 15.0,
		"noise_seed": 23.0,
		"noise_period": 6.0,
		"teeth_deg": 1.0,
		"teeth_freq": 80.0,
		"tree_shape": 0.0,
		"cloud_cover": 0.6,
		"lit_amount": 0.6,
	},
	"boreal_taiga":
	{
		"zenith_color": Color(0.22, 0.40, 0.78),
		"horizon_color": Color(0.72, 0.84, 0.94),
		"warm_color": Color(0.96, 0.88, 0.80),
		"far_color": Color(0.40, 0.52, 0.74),
		"near_color": Color(0.05, 0.26, 0.28),
		"foot_color": Color(0.24, 0.46, 0.44),
		"height_deg": 24.0,
		"noise_seed": 37.0,
		"noise_period": 7.0,
		"teeth_deg": 2.0,
		"teeth_freq": 90.0,
		"tree_shape": 1.0,
		"cloud_cover": 0.8,
		"mist": 0.6,
		"warm_amount": 0.25,
	},
	"burnt_forest":
	{
		"zenith_color": Color(0.40, 0.40, 0.64),
		"horizon_color": Color(0.88, 0.78, 0.76),
		"warm_color": Color(1.0, 0.70, 0.50),
		"cloud_shade": Color(0.50, 0.46, 0.62),
		"far_color": Color(0.52, 0.46, 0.64),
		"near_color": Color(0.16, 0.14, 0.18),
		"foot_color": Color(0.36, 0.34, 0.34),
		"height_deg": 17.0,
		"noise_seed": 41.0,
		"noise_period": 6.0,
		"teeth_deg": 1.8,
		"teeth_freq": 70.0,
		"tree_shape": 1.0,
		"haze_far": 0.8,
		"warm_amount": 0.6,
		"lit_amount": 0.35,
	},
	"grassland_meadow":
	{
		"zenith_color": Color(0.30, 0.56, 0.95),
		"horizon_color": Color(0.80, 0.91, 0.99),
		"far_color": Color(0.50, 0.66, 0.88),
		"near_color": Color(0.30, 0.55, 0.30),
		"foot_color": Color(0.48, 0.70, 0.38),
		"height_deg": 16.0,
		"noise_seed": 3.0,
		"noise_period": 3.0,
		"teeth_deg": 0.6,
		"teeth_freq": 40.0,
		"tree_shape": 0.0,
		"cloud_cover": 0.65,
		"cloud2_cover": 0.75,
	},
	"rocky_badlands":
	{
		"zenith_color": Color(0.30, 0.48, 0.88),
		"horizon_color": Color(0.92, 0.86, 0.84),
		"warm_color": Color(1.0, 0.78, 0.56),
		"far_color": Color(0.68, 0.46, 0.56),
		"near_color": Color(0.50, 0.30, 0.22),
		"foot_color": Color(0.62, 0.48, 0.36),
		"height_deg": 26.0,
		"noise_seed": 53.0,
		"noise_period": 5.0,
		"teeth_deg": 0.0,
		"teeth_freq": 30.0,
		"tree_shape": 0.0,
		"angular": 0.85,
		"cloud_cover": 0.35,
		"lit_amount": 0.7,
	},
	"savanna":
	{
		# A warm golden haze at the horizon, dusty violet far ridges and ochre-olive near hills with
		# sparse flat crowns: three values a step apart, so the ridges read through the warmth.
		"zenith_color": Color(0.28, 0.50, 0.92),
		"horizon_color": Color(0.99, 0.88, 0.70),
		"warm_color": Color(1.0, 0.76, 0.46),
		"far_color": Color(0.60, 0.54, 0.76),
		"near_color": Color(0.44, 0.40, 0.18),
		"foot_color": Color(0.70, 0.58, 0.36),
		"height_deg": 14.0,
		"noise_seed": 61.0,
		"noise_period": 3.0,
		"teeth_deg": 1.1,
		"teeth_freq": 26.0,
		"tree_shape": 0.0,
		"angular": 0.3,
		"cloud_cover": 0.5,
		"haze_far": 0.4,
		"warm_amount": 0.7,
	},
	"wetland_riparian":
	{
		"zenith_color": Color(0.34, 0.54, 0.86),
		"horizon_color": Color(0.84, 0.92, 0.94),
		"far_color": Color(0.52, 0.68, 0.78),
		"near_color": Color(0.20, 0.46, 0.38),
		"foot_color": Color(0.46, 0.68, 0.56),
		"height_deg": 11.0,
		"noise_seed": 71.0,
		"noise_period": 4.0,
		"teeth_deg": 0.7,
		"teeth_freq": 70.0,
		"tree_shape": 0.2,
		"cloud_cover": 0.8,
		"mist": 0.8,
		"haze_far": 0.8,
	},
	"alpine_meadow":
	{
		# Pale blue snow-capped peaks over a dark blue-green conifer line: the far, near and meadow
		# values a clear step apart (the green-on-green blobs read as one soft mass).
		"zenith_color": Color(0.20, 0.40, 0.92),
		"horizon_color": Color(0.80, 0.90, 1.0),
		"far_color": Color(0.42, 0.53, 0.86),
		"near_color": Color(0.10, 0.28, 0.34),
		"foot_color": Color(0.44, 0.64, 0.52),
		"height_deg": 34.0,
		"noise_seed": 83.0,
		"noise_period": 4.0,
		"teeth_deg": 1.2,
		"teeth_freq": 70.0,
		"tree_shape": 1.0,
		"angular": 0.9,
		"cloud_cover": 0.55,
		"haze_far": 0.2,
		"snow_amount": 1.0,
	},
}


## The look key for a biome id: the longest key the id equals or starts with (`key_`), else DEFAULT.
static func resolve(biome_id: String) -> String:
	var best := DEFAULT
	var best_len := 0
	for key: String in LOOKS:
		if key == DEFAULT:
			continue
		if (biome_id == key or biome_id.begins_with(key + "_")) and key.length() > best_len:
			best = key
			best_len = key.length()
	return best


## The complete look of `biome_id`: the shared defaults, then the biome's own numbers.
static func look_for(biome_id: String) -> Dictionary:
	var look := COMMON.duplicate()
	look.merge(LOOKS[resolve(biome_id)], true)
	return look


## The shader uniforms for `biome_id` on a map with seed `map_seed`: the look, a lattice seed
## shifted by the map's seed (the biome's character, a skyline of its own) and the sun's place in
## the sky. `sun` is x = azimuth, y = elevation in degrees (see sun_angles).
static func shader_params(biome_id: String, map_seed: int, sun: Vector2) -> Dictionary:
	var params := look_for(biome_id)
	params["noise_seed"] = float(params["noise_seed"]) + float(posmod(map_seed, 61)) * 0.31
	params["glow_az_deg"] = sun.x
	params["sun_el_deg"] = clampf(sun.y, 5.0, 85.0)
	return params


## The eye's reach on the map: the ground distance from `eye` (world x, z) to the farthest corner
## of `bounds` (the walking area). 0 for an empty box (no map). The same at every yaw, so turning
## never moves the fog.
static func map_reach(eye: Vector2, bounds: AABB) -> float:
	if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		return 0.0
	var far_x := maxf(absf(eye.x - bounds.position.x), absf(eye.x - bounds.end.x))
	var far_z := maxf(absf(eye.y - bounds.position.z), absf(eye.y - bounds.end.z))
	return Vector2(far_x, far_z).length()


## The depth fog's begin (x) and end (y) in metres for an eye whose reach is `reach` (map_reach):
## FOG_BEGIN_REACH and FOG_END_REACH of the reach, never nearer than FOG_BEGIN_M and FOG_END_M,
## and the end always at least the old 60 m ramp past the begin.
static func fog_range(reach: float) -> Vector2:
	var begin := maxf(FOG_BEGIN_M, reach * FOG_BEGIN_REACH)
	var end := maxf(maxf(FOG_END_M, reach * FOG_END_REACH), begin + (FOG_END_M - FOG_BEGIN_M))
	return Vector2(begin, end)


## The sun's azimuth (0..360, the sky shader's convention) and elevation in degrees along `to_sun`
## (world, toward the sun), seen in the sky's frame: Godot turns the view direction by the inverse
## of `sky_rotation` before the sky shader reads it.
static func sun_angles(to_sun: Vector3, sky_rotation: Vector3 = Vector3.ZERO) -> Vector2:
	var dir := (Basis.from_euler(sky_rotation).inverse() * to_sun).normalized()
	var az := fposmod(rad_to_deg(atan2(dir.x, -dir.z)) + 180.0, 360.0)
	var el := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	return Vector2(az, el)


## The biome that covers most of a map: `slots` holds a slot per sample (0 none, else index + 1
## into `ids`). With no slots the first id; with no ids "". Samples every few entries (a
## 640 x 640 grid is 400k bytes, and a near count is enough to name the biggest).
static func dominant_biome(ids: PackedStringArray, slots: PackedByteArray) -> String:
	if ids.is_empty():
		return ""
	if slots.is_empty():
		return ids[0]
	var counts := PackedInt32Array()
	counts.resize(ids.size() + 1)
	for i in range(0, slots.size(), 5):
		var slot := slots[i]
		if slot > 0 and slot <= ids.size():
			counts[slot] += 1
	var best := 0
	for slot in range(1, counts.size()):
		if counts[slot] > counts[best] or best == 0:
			best = slot
	return ids[best - 1] if counts[best] > 0 else ids[0]
