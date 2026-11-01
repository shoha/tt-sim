class_name VillageCrops
extends RefCounted

## How a crop field looks (topic fields, round 5; docs/systems/villages.md section 11): the paint
## strokes and plants VillageFields lays for a field of kind "crops". Round 4's dark peat furrows
## under pale gold rows read as "a striped chocolate desert" (the user, 2026-10-31), so round 5
## builds three genuinely different looks over a light warm earth and compares them at home zoom
## (`LOOKS`, `look`):
##
## - rows: broad soft crop rows over the earth with narrow furrows between, low contrast; each
##   field one crop tone (young green, barley gold-green, ripe gold or a fallow ploughed field).
## - patchwork: each field a few broad flat strips of different tones (medieval strip fields),
##   with only a faint hint of row direction across them.
## - plants: rows of real plants from the core library: tall meadow grass (barley on the earth,
##   a young crop on green), golden savanna grass (ripe wheat) or daisies on green (a flowering
##   buckwheat field).
##
## Round 5's verdict (job `fields_crops`, sheet_crops): only the plants look reads as farmland at
## home zoom; the painted looks read as sand discs (rows) or washed-out lawn and sand (patchwork),
## the light earth winning over thin painted rows. The plants look is the default; the painted
## looks stay behind the switch for the comparison job.
##
## Neighbouring fields take different tones: a field's tone comes from the cell of a CELL_M
## lattice its centre falls in, coloured so that cells touching on a side or a corner never share
## a tone ((x + 2 z) mod 4), plus the settlement's seed so a re-dress repaints the quilt. Pure:
## a function of the record and the seed, like everything in VillageFields.

const LOOKS: Array[String] = ["rows", "patchwork", "plants"]
## Light warm earth: the ploughed ground under every look and the fallow field's whole face.
const EARTH := "dirt_opening"
## A shade darker, laid thinly: furrow lines on fallow ground and the patchwork's row hint.
const FURROW := "dirt_road_packed"
const GREEN := "grass_alpine"
const GOLD := "grass_savanna"
## The four tones a field (or a patchwork strip) takes: the crop surface of the painted looks, an
## optional overlay laid thinly over it (barley: gold over green; no rows: fallow earth), and for
## the plants look the plant rows and the ground under them (the earth, or green under a young
## crop and a flowering one, so the gaps between rows are not sand).
const TONES: Array[Dictionary] = [
	{"name": "barley", "rows": GREEN, "over": GOLD, "plant": "grass", "ground": ""},
	{"name": "young", "rows": GREEN, "over": "", "plant": "grass", "ground": GREEN},
	{"name": "buckwheat", "rows": "", "over": "", "plant": "flower", "ground": GREEN},
	{"name": "ripe", "rows": GOLD, "over": "", "plant": "gold", "ground": ""},
]
const CELL_M := 16.0
const SECONDS := 1.2
## A thin coat: the barley overlay and the furrow lines, so they tint rather than cover.
const THIN_SECONDS := 0.3
const HINT_SECONDS := 0.15
## The rows look: rows this far apart at this brush radius (a broad band of crop with a narrow
## soft furrow between), stopping this share of the half chord short of the rim.
const ROW_PITCH_M := 2.2
const ROW_RADIUS_M := 0.95
const ROW_REACH := 0.86
## The patchwork: this many strips across a field, and hint lines this far apart and this thin.
const STRIPS := 3
const HINT_PITCH_M := 2.4
const HINT_RADIUS_M := 0.3
## The plants look: rows of tall grass this far apart, a plant this often along a row, at this
## scale (the grass is about 0.55 m tall at 1.0).
const PLANT_PITCH_M := 1.15
const PLANT_STEP_M := 0.55
const PLANT_SCALE := Vector2(1.3, 1.7)
const PLANT_ASSETS := {
	"flower":
	[
		"grassland_meadow_summer_s1/Flower_Daisy_v0_grassland_meadow",
		"grassland_meadow_summer_s1/Flower_Daisy_v1_grassland_meadow",
	],
	"grass":
	[
		"grassland_meadow_summer_s1/Grass_Grass_v3_grassland_meadow",
		"grassland_meadow_summer_s1/Grass_Grass_v4_grassland_meadow",
		"grassland_meadow_summer_s1/Grass_Grass_v5_grassland_meadow",
	],
	"gold":
	[
		"savanna_summer_s1/Grass_Grass_v3_savanna",
		"savanna_summer_s1/Grass_Grass_v4_savanna",
		"savanna_summer_s1/Grass_Grass_v5_savanna",
	],
}

## The look every crop field takes (one of LOOKS): a switch for the comparison job, never saved or
## sent, so every peer plans the default.
static var look: String = "plants"


## The tone index (into TONES) of a field at `at` with seed `seed_value`; `shift` moves it along
## (a patchwork strip's place in its field).
static func tone_of(at: Vector2, seed_value: int, shift: int = 0) -> int:
	var cell := Vector2i(floori(at.x / CELL_M), floori(at.y / CELL_M))
	return posmod(cell.x + 2 * cell.y + absi(seed_value) % 4 + shift, TONES.size())


## The paint strokes of crop field `field` ({"at", "radius"}) for seed `seed_value`, turned to
## `turn` radians, over the earth disc VillageFields lays first. Unsnapped capsules {"surface",
## "from", "to", "radius", "seconds"}.
static func strokes_of(field: Dictionary, seed_value: int, turn: float) -> Array[Dictionary]:
	var at: Vector2 = field["at"]
	var radius := float(field["radius"])
	var along := Vector2.from_angle(turn)
	var across := Vector2(-along.y, along.x)
	var out: Array[Dictionary] = []
	match look:
		"patchwork":
			var width := 2.0 * radius / STRIPS
			for k in STRIPS:
				var tone: Dictionary = TONES[tone_of(at, seed_value, k)]
				var offset := -radius + (k + 0.5) * width
				var half := maxf(_chord(radius, offset) - 0.5 * width, 0.3)
				var mid := at + across * offset
				_tone_strokes(out, tone, mid - along * half, mid + along * half, 0.5 * width)
			# A faint hint of row direction across every strip.
			for offset in _offsets(radius * 0.9, HINT_PITCH_M):
				var half := _chord(radius, offset) * 0.86 - HINT_RADIUS_M
				if half > 0.5:
					var mid := at + across * offset
					out.append(
						_cap(FURROW, mid - along * half, mid + along * half, HINT_RADIUS_M, HINT_SECONDS)
					)
		"plants":
			# The tone's ground, then faint furrows under the plant rows; the plants carry the colour.
			var tone: Dictionary = TONES[tone_of(at, seed_value)]
			if str(tone["ground"]) != "":
				out.append(_cap(str(tone["ground"]), at, at, radius * 0.97, SECONDS))
			for offset in _offsets(radius * ROW_REACH, PLANT_PITCH_M):
				var half := _chord(radius, offset) * ROW_REACH - HINT_RADIUS_M
				if half > 0.5:
					var mid := at + across * offset
					out.append(
						_cap(FURROW, mid - along * half, mid + along * half, HINT_RADIUS_M, THIN_SECONDS)
					)
		_:
			var tone: Dictionary = TONES[tone_of(at, seed_value)]
			for offset in _offsets(radius * ROW_REACH, ROW_PITCH_M):
				var half := _chord(radius, offset) * ROW_REACH - ROW_RADIUS_M
				if half > 0.5:
					var mid := at + across * offset
					if str(tone["rows"]) == "":
						out.append(
							_cap(FURROW, mid - along * half, mid + along * half, 0.4, THIN_SECONDS)
						)
					else:
						_tone_strokes(out, tone, mid - along * half, mid + along * half, ROW_RADIUS_M)
	return out


## The plants of crop field `field` for seed `seed_value` turned to `turn` ([] unless the look
## is "plants"): {"asset", "at", "yaw", "scale"} along the furrow rows, the tone's plant.
static func plants_of(field: Dictionary, seed_value: int, turn: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if look != "plants":
		return out
	var at: Vector2 = field["at"]
	var radius := float(field["radius"])
	var tone: Dictionary = TONES[tone_of(at, seed_value)]
	if str(tone["plant"]) == "":
		return out
	var assets: Array = PLANT_ASSETS[str(tone["plant"])]
	var along := Vector2.from_angle(turn)
	var across := Vector2(-along.y, along.x)
	for offset in _offsets(radius * ROW_REACH, PLANT_PITCH_M):
		var half := _chord(radius, offset) * ROW_REACH - HINT_RADIUS_M
		if half <= 0.5:
			continue
		var count := floori(2.0 * half / PLANT_STEP_M)
		for n in count + 1:
			var spot := at + across * offset + along * lerpf(-half, half, float(n) / maxf(count, 1))
			var h := absi(hash([seed_value, roundi(spot.x * 100.0), roundi(spot.y * 100.0), "crop"]))
			out.append(
				{
					"asset": assets[h % assets.size()],
					"at": spot,
					"yaw": float((h >> 4) % 6283) / 1000.0,
					"scale": lerpf(PLANT_SCALE.x, PLANT_SCALE.y, float((h >> 14) % 101) / 100.0),
				}
			)
	return out


## The surfaces every crop look may paint (the disc's EARTH included).
static func surfaces() -> Array[String]:
	return [EARTH, FURROW, GREEN, GOLD]


static func _tone_strokes(
	out: Array[Dictionary], tone: Dictionary, from: Vector2, to: Vector2, radius: float
) -> void:
	var rows := str(tone["rows"])
	if rows == "":
		out.append(_cap(FURROW, from, to, radius * 0.5, THIN_SECONDS))
		return
	out.append(_cap(rows, from, to, radius, SECONDS))
	if str(tone["over"]) != "":
		out.append(_cap(str(tone["over"]), from, to, radius * 0.9, THIN_SECONDS))


static func _chord(radius: float, offset: float) -> float:
	return sqrt(maxf(radius * radius - offset * offset, 0.0))


static func _offsets(reach: float, pitch: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := floori(2.0 * reach / pitch) + 1
	var start := -0.5 * pitch * (count - 1)
	for n in count:
		out.append(start + n * pitch)
	return out


static func _cap(
	surface: String, from: Vector2, to: Vector2, radius: float, seconds: float
) -> Dictionary:
	return {"surface": surface, "from": from, "to": to, "radius": radius, "seconds": seconds}
