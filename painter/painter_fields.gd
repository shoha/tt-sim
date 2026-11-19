class_name PainterFields
extends RefCounted

## The painted village fields (card painter-fields; docs/systems/painter.md "Fields"). Under
## Classic a crop field is its earth surfaces and rows of real crop plants (VillageCrops) ringed
## by a hedge of meadow bushes; under Painted the earth's surface (`dirt_opening`) sorted into the
## forest floor's moss green, the crops were thinned and toned as the meadow's grass and drawn as
## its round dab mounds, and the hedge bushes took the light bush green, so every field but a
## flowering one melted into the meadow. This gives a field its own painted form:
##
## - The ground (painter_field.gdshaderinc, in the painted ground's block-in): a tilled soil bed in
##   a warm earth tone derived from the mood's path (`soil-hue`, `-chroma`, `-lift`), and over it
##   the crop's rows as long brush strokes in the crop's own tone, laid exactly under the plant
##   rows VillageCrops plants, with a darker furrow line between each pair; a headland of bare soil
##   where the rows stop short of the rim. A garden's beds (VillageFields) are soil masses under
##   their flowers. The disc's rim is brushed by the ground's noise. In winter the rows lie under
##   snow (`field-snow`) and the furrows show through as dark lines.
## - The crop's tone is the crop plant's OWN colour (its texture's mean, read once): the sheet's
##   `grass` moved by how far the plant stands from the meadow grass (`crop-own`), a step richer
##   and lighter (`crop-chroma`, `crop-lift`), so ripe wheat is gold, a young crop a fresh green and
##   barley, whose rows Classic coats in gold, between; every mood and sun still moves it.
## - The crop plants (AuthoredFieldPlants marks them `crop`): never thinned, toned the crop's own
##   tone and cut by their texture's blades (`tuft_blades`), not the meadow's dab mounds, so at the
##   eye a row reads as a standing crop, not shrubs.
## - The hedges (AuthoredFieldPlants keys their rows HEDGE_KEY + asset): the painted bush species
##   `bush_hedge`, a deeper, cooler green than the meadow's bushes (tree_roles.json), so the ring
##   reads as a hedge against the meadow.
##
## Data: a field map (R8, one texel per height sample, nearest: the index of the field whose disc
## covers the sample, NONE outside) and per field two vec4 (centre, radius, row angle; the first
## row's offset, the row count, the pitch, the style) and an int (style * 4 + crop). At most
## MAX_FIELDS fields are painted (the rest keep the plain ground). Pure statics but the measured
## colour cache (`_own`, cleared by PainterStateReset).

## The most fields the ground shader takes (its uniform arrays' size).
const MAX_FIELDS := 32
const NONE := 255
## The field map covers this much past a field's radius (the brushed rim and the soil disc's
## VillageFields.DISC_FACTOR).
const COVER := 1.15
## Field styles: crop rows over soil, a garden's soil beds.
const STYLE_CROPS := 0
const STYLE_GARDEN := 1
## The crop plants' own colour when it cannot be read (OKLCH), per VillageCrops.TONES plant.
const OWN_FALLBACK := {
	"grass": Vector3(0.62, 0.12, 132.0),
	"gold": Vector3(0.74, 0.11, 88.0),
	"flower": Vector3(0.62, 0.12, 132.0),
}
## How much of the gold coat barley's rows take (VillageCrops.TONES "over").
const OVER_SHARE := 0.5
## Lightness and chroma shares of a crop's own colour against the meadow grass (hue moves whole).
const OWN_L := 0.7
const OWN_C_POW := 0.8
const OWN_C := Vector2(0.5, 2.5)
## A crop takes its own hue fully while the mood's grass is the meadow's green (GREEN_HUE, OKLCH
## degrees), and none once the grass is GREEN_SPAN degrees off it (winter's straw at 72).
const GREEN_HUE := 135.0
const GREEN_SPAN := 55.0
## The samples a texture is read at, per side.
const SAMPLES := 24

## The A/B switch for measurement and before frames: false paints fields as before the card (no
## field map, crops as meadow grass, hedges in the bush tone). Read at paint time, so release and
## paint again (PainterStateReset puts it back).
static var enabled := true
## asset id -> its measured colour (OKLCH; x -1 when it has none).
static var _own: Dictionary = {}


## The painted fields of `doc`, in order: {"at", "radius", "angle", "start", "count", "pitch",
## "style", "crop"} (crop a VillageCrops.TONES index, -1 for a garden). Orchards paint nothing here.
static func fields_of(doc: MapDocument) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled:
		return out
	for settlement in doc.settlements:
		for field in settlement.fields:
			var kind := str(field["kind"])
			if kind != "crops" and kind != "garden":
				continue
			var at: Vector2 = field["at"]
			var radius := float(field["radius"])
			var seed_value := settlement.seed_value
			var crops := kind == "crops"
			var reach := radius * (VillageCrops.ROW_REACH if crops else 0.62)
			var pitch := VillageCrops.PLANT_PITCH_M if crops else VillageFields.BED_PITCH_M
			var count := floori(2.0 * reach / pitch) + 1
			out.append(
				{
					"at": at,
					"radius": radius,
					"angle": VillageFields.angle_of(field, seed_value),
					"start": -0.5 * pitch * (count - 1),
					"count": count,
					"pitch": pitch,
					"style": STYLE_CROPS if crops else STYLE_GARDEN,
					"crop": VillageCrops.tone_of(at, seed_value) if crops else -1,
				}
			)
			if out.size() == MAX_FIELDS:
				return out
	return out


## The field map of `fields` (fields_of) over `doc`'s height samples: R8, each sample the index of
## the field whose disc (radius times COVER) holds it nearest its centre (relative to its radius),
## NONE outside every field; null when there is no field. Pure.
static func field_image(doc: MapDocument, fields: Array[Dictionary]) -> Image:
	if fields.is_empty():
		return null
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var step := doc.sample_step()
	var origin := -doc.extent_m() * 0.5
	var bytes := PackedByteArray()
	bytes.resize(sx * sz)
	bytes.fill(NONE)
	var best := PackedFloat32Array()
	best.resize(sx * sz)
	best.fill(INF)
	for k in fields.size():
		var at: Vector2 = fields[k]["at"]
		var reach := float(fields[k]["radius"]) * COVER + step.length()
		var lo := ((at - Vector2(reach, reach) - origin) / step).floor()
		var hi := ((at + Vector2(reach, reach) - origin) / step).ceil()
		for z in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, sz)):
			for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, sx)):
				var p := origin + Vector2(x, z) * step
				var d := p.distance_to(at) / reach
				var i := z * sx + x
				if d <= 1.0 and d < best[i]:
					best[i] = d
					bytes[i] = k
	return Image.create_from_data(sx, sz, false, Image.FORMAT_R8, bytes)


## Sets the field map and the fields' geometry of `doc` on the ground `materials`.
static func bind(materials: Array, doc: MapDocument) -> void:
	var fields := fields_of(doc)
	var image := field_image(doc, fields)
	var texture: ImageTexture = null if image == null else ImageTexture.create_from_image(image)
	var geo := PackedVector4Array()
	var rows := PackedVector4Array()
	var kinds := PackedInt32Array()
	geo.resize(MAX_FIELDS)
	rows.resize(MAX_FIELDS)
	kinds.resize(MAX_FIELDS)
	for k in fields.size():
		var f := fields[k]
		var at: Vector2 = f["at"]
		geo[k] = Vector4(at.x, at.y, float(f["radius"]), float(f["angle"]))
		rows[k] = Vector4(float(f["start"]), float(f["count"]), float(f["pitch"]), 0.0)
		kinds[k] = int(f["style"]) * 4 + maxi(int(f["crop"]), 0)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"field_map", texture)
		material.set_shader_parameter(&"field_present", texture != null)
		material.set_shader_parameter(&"f_geo", geo)
		material.set_shader_parameter(&"f_row", rows)
		material.set_shader_parameter(&"f_kind", kinds)


## The fields' tones in `mood` at `elevation`, keyed by the ground shader's uniform names: the
## soil's two lit and two shade variants (`f_soil`: lit0, lit1, shade0, shade1), each crop's
## (`f_crop_lit`, `f_crop_shd`: two a VillageCrops.TONES entry) and the snow over the rows.
static func tones(sheet: Dictionary, mood: String, elevation: float) -> Dictionary:
	var soil := PainterTones.ramp(
		sheet, mood, "path", elevation, "ground-", soil_lch(sheet, mood, elevation)
	)
	var crop_lit := PackedVector3Array()
	var crop_shd := PackedVector3Array()
	for k in VillageCrops.TONES.size():
		var mid := crop_lch(sheet, mood, elevation, crop_own(k))
		var ramp := PainterTones.ramp(sheet, mood, "grass", elevation, "ground-", mid)
		crop_lit.append_array([PainterTones.linear(ramp[2]), PainterTones.linear(ramp[5])])
		crop_shd.append_array([PainterTones.linear(ramp[0]), PainterTones.linear(ramp[3])])
	return {
		&"f_soil":
		PackedVector3Array(
			[
				PainterTones.linear(soil[2]),
				PainterTones.linear(soil[5]),
				PainterTones.linear(soil[0]),
				PainterTones.linear(soil[3]),
			]
		),
		&"f_crop_lit": crop_lit,
		&"f_crop_shd": crop_shd,
		&"f_snow": PainterSheet.number(sheet, mood, "field-snow", elevation),
	}


## The tilled soil's middle tone (OKLCH): the mood's path turned to `soil-hue`, its chroma times
## `soil-chroma` and its lightness moved by `soil-lift`. Pure.
static func soil_lch(sheet: Dictionary, mood: String, elevation: float) -> Vector3:
	var path := PainterSheet.tone_lch(sheet, mood, "path", elevation)
	var num := func(prop: String) -> float: return PainterSheet.number(sheet, mood, prop, elevation)
	return Vector3(
		clampf(path.x + float(num.call("soil-lift")), 0.05, 0.95),
		path.y * float(num.call("soil-chroma")),
		float(num.call("soil-hue"))
	)


## A crop's middle tone (OKLCH) for a plant of measured colour `own` (OKLCH; x < 0 for none): the
## sheet's `grass` moved by `crop-own` of the way `own` stands from the meadow grass's measured
## colour (hue whole, lightness OWN_L, chroma by its ratio to OWN_C_POW), then `crop-lift` lighter
## and `crop-chroma` richer. Pure but for the measured meadow grass (cached).
static func crop_lch(sheet: Dictionary, mood: String, elevation: float, own: Vector3) -> Vector3:
	var base := PainterSheet.tone_lch(sheet, mood, "grass", elevation)
	var num := func(prop: String) -> float: return PainterSheet.number(sheet, mood, prop, elevation)
	var ref := own_of_asset(str(VillageCrops.PLANT_ASSETS["grass"][0]))
	if ref.x < 0.0:
		ref = OWN_FALLBACK["grass"]
	var mid := base
	if own.x >= 0.0:
		var share := float(num.call("crop-own"))
		# The hue moves only as far as the mood's grass is still the meadow's green: winter's straw
		# grass is every crop's straw (round 1: a full move turned ripe wheat salmon over snow).
		var off_green := absf(fposmod(base.z - GREEN_HUE + 180.0, 360.0) - 180.0)
		var green := 1.0 - clampf(off_green / GREEN_SPAN, 0.0, 1.0)
		var hue_k := clampf((own.y - 0.01) / 0.03, 0.0, 1.0) * green
		var dh := fposmod(own.z - ref.z + 180.0, 360.0) - 180.0
		var ratio := clampf(own.y / maxf(ref.y, 0.001), OWN_C.x, OWN_C.y)
		mid = Vector3(
			base.x + (own.x - ref.x) * OWN_L * share,
			base.y * pow(ratio, OWN_C_POW * share),
			fposmod(base.z + dh * hue_k * share, 360.0)
		)
	return Vector3(
		clampf(mid.x + float(num.call("crop-lift")), 0.05, 0.95),
		mid.y * float(num.call("crop-chroma")),
		mid.z
	)


## The measured colour (OKLCH) of VillageCrops.TONES entry `k`'s crop: its plant's own colour,
## barley's moved OVER_SHARE toward its gold coat's surface colour.
static func crop_own(k: int) -> Vector3:
	var tone: Dictionary = VillageCrops.TONES[k]
	var plant := str(tone["plant"])
	var own := own_of_asset(str(VillageCrops.PLANT_ASSETS[plant][0]))
	if own.x < 0.0:
		own = OWN_FALLBACK.get(plant, OWN_FALLBACK["grass"])
	var over := str(tone["over"])
	if over != "":
		var coat := PainterGroundPaths.own_lch(PaletteLibrary.surfaces().get(over, {}))
		if coat.x >= 0.0:
			own = PainterSheet.lerp_lch(own, coat, OVER_SHARE)
	return own


## The measured colour (OKLCH) of library asset `asset_id`'s first leaf surface (its texture's mean
## over its opaque texels), cached; x -1 when the asset or its texture cannot be read.
static func own_of_asset(asset_id: String) -> Vector3:
	if _own.has(asset_id):
		return _own[asset_id]
	var own := Vector3(-1.0, 0.0, 0.0)
	var mesh := PaletteLibrary.resolve(asset_id).get("mesh") as Mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			own = own_of_material(mesh.surface_get_material(i))
			if own.x >= 0.0:
				break
	_own[asset_id] = own
	return own


## The mean colour (OKLCH) of `material`'s albedo texture over its opaque texels, times its albedo
## colour; x -1 when it has no readable texture. A bloom surface (PainterFlowerHue.BLOOM_WORDS) is
## not a crop's colour and is skipped.
static func own_of_material(material: Material) -> Vector3:
	if material == null:
		return Vector3(-1.0, 0.0, 0.0)
	var word := material.resource_name.to_lower().get_slice("_", material.resource_name.count("_"))
	if word in PainterFlowerHue.BLOOM_WORDS:
		return Vector3(-1.0, 0.0, 0.0)
	var texture: Texture2D = null
	var tint := Color.WHITE
	if material is BaseMaterial3D:
		texture = (material as BaseMaterial3D).albedo_texture
		tint = (material as BaseMaterial3D).albedo_color
	elif material is ShaderMaterial:
		texture = (material as ShaderMaterial).get_shader_parameter(&"albedo_texture") as Texture2D
	if texture == null:
		return Vector3(-1.0, 0.0, 0.0)
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Vector3(-1.0, 0.0, 0.0)
	if image.is_compressed():
		image = image.duplicate() as Image
		image.decompress()
	var sum := Vector3.ZERO
	var n := 0
	for y in SAMPLES:
		for x in SAMPLES:
			var c := image.get_pixel(
				int((x + 0.5) * image.get_width() / SAMPLES),
				int((y + 0.5) * image.get_height() / SAMPLES)
			)
			if c.a > 0.5:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	if n == 0:
		return Vector3(-1.0, 0.0, 0.0)
	sum /= n
	return PainterSheet.lch_of_color(Color(sum.x * tint.r, sum.y * tint.g, sum.z * tint.b))


## `entry` (PainterPlantRoles.of) for a plant source's species record `record` (a scatter's or the
## field plants' resolved_species entry): a field's crop (`crop` in the record) carries `crop` and
## its measured colour `own`, read from `mesh`'s surfaces; any other entry is returned as it is.
static func plant_entry(entry: Dictionary, record: Dictionary) -> Dictionary:
	if entry.is_empty() or not enabled or not bool(record.get("crop", false)):
		return entry
	var out := entry.duplicate()
	out["crop"] = true
	var own := Vector3(-1.0, 0.0, 0.0)
	var mesh := record.get("mesh") as Mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			own = own_of_material(mesh.surface_get_material(i))
			if own.x >= 0.0:
				break
	out["own"] = own
	return out


## Clears the measured colours (PainterStateReset: a fresh process's state).
static func reset() -> void:
	_own.clear()
