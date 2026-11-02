class_name StreetSpeciesInfo
extends RefCounted
## What the Street tool shows for each species of street (Wall.preset): its tile id, plain name,
## icon and tooltip. The species themselves and their order are procgen's
## (ProcgenStreetSpecies.NAMES: a `Wall.preset` is an index into it), so the list here is built
## from that, not written twice: a species procgen adds later appears with a name made from its
## own and no tooltip detail until a line is added to INFO.
##
## Numbering (saved maps store the index, so it never changes): 0 mixed, 1 terrace, 2 guild
## houses, 3 village, 4 cottages (the first five), then 5 pueblo village, 6 villa street, 7 alpine
## hamlet, 8 canal row, 9 tudor lane, 10 minka village, 11 modern row (the modern town's).
##
## Setback: a species may name the setback a new street of it starts at (`setback_m`, how far back
## its buildings stand, the Wall row's height); the rest take the Street brush's default
## (Wall.DEFAULT_HEIGHT_M, 3 m). The modern row stands back 3.6 m, a 2.7 m frontage strip against
## 2.25 m (SettlementFrontage: 0.75 of the setback), room for its parked cars at the kerb. The
## Street brush moves to it
## when its tile is picked, unless the author has set the setback since (WallBrush.pick_preset).
## Pure data in, data out.

## Per procgen species name: the tile's id, label, icon (a Tabler name) and tooltip, and an
## optional `setback_m`.
const INFO: Dictionary = {
	"mixed":
	{
		"id": &"street_mixed",
		"label": "Mixed",
		"icon": "street",
		"tooltip": "A bit of everything: houses of different sizes, a gap here and there",
	},
	"terrace":
	{
		"id": &"street_terrace",
		"label": "Terrace",
		"icon": "grid-dots",
		"tooltip": "A terrace: tall narrow houses wall to wall, no yards",
	},
	"guild_houses":
	{
		"id": &"street_guild",
		"label": "Guild",
		"icon": "chess",
		"tooltip": "Guild houses: wide, tall, gable-fronted, almost touching",
	},
	"village":
	{
		"id": &"street_village",
		"label": "Village",
		"icon": "fence",
		"tooltip": "A village: houses with fenced yards, gates to the street, gaps between",
	},
	"cottages":
	{
		"id": &"street_cottages",
		"label": "Cottages",
		"icon": "home",
		"tooltip": "Cottages: small low houses far apart, each with a low stone-walled yard",
	},
	"pueblo_village":
	{
		"id": &"street_pueblo",
		"label": "Pueblo",
		"icon": "sun",
		"tooltip": "A desert pueblo: flat-roofed adobe houses packed close, no yards",
	},
	"villa_street":
	{
		"id": &"street_villa",
		"label": "Villas",
		"icon": "sunrise",
		"tooltip": "Mediterranean villas: wide shuttered houses under hipped roofs, low walled gardens",
	},
	"alpine_hamlet":
	{
		"id": &"street_alpine",
		"label": "Alpine",
		"icon": "mountain",
		"tooltip": "An alpine hamlet: timber chalets and the odd barn, wide gaps, fenced yards",
	},
	"canal_row":
	{
		"id": &"street_canal",
		"label": "Canal",
		"icon": "ripple",
		"tooltip": "A canal row: tall narrow gabled houses wall to wall, Dutch style",
	},
	"tudor_lane":
	{
		"id": &"street_tudor",
		"label": "Tudor",
		"icon": "walk",
		"tooltip": "A Tudor lane: timber-framed townhouses leaning close, small gaps",
	},
	"minka_village":
	{
		"id": &"street_minka",
		"label": "Minka",
		"icon": "leaf",
		"tooltip": "A minka village: low thatched farmhouses set far apart, fenced yards",
	},
	"modern_row":
	{
		"id": &"street_modern",
		"label": "Modern",
		"icon": "stairs-up",
		"tooltip": "A mid-century high street: flat-roofed shops, terraces and bungalows in pastel",
		"setback_m": 3.6,
	},
}


## How many species there are (ProcgenStreetSpecies.NAMES).
static func count() -> int:
	return ProcgenStreetSpecies.NAMES.size()


## The tiles, one per species in preset order: {"preset" (int), "id" (StringName), "label",
## "icon", "tooltip"}.
static func tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for preset in count():
		var species_name: String = ProcgenStreetSpecies.NAMES[preset]
		var info: Dictionary = INFO.get(species_name, {})
		out.append(
			{
				"preset": preset,
				"id": StringName(info.get("id", "street_%s" % species_name)),
				"label": String(info.get("label", _plain(species_name))),
				"icon": String(info.get("icon", "street")),
				"tooltip": String(info.get("tooltip", "A street of %s." % _plain(species_name))),
			}
		)
	return out


## The setback (metres) a new street of species `preset` starts at: its own `setback_m`, else the
## Street brush's default. An unknown preset gets the default.
static func setback_m(preset: int) -> float:
	var fallback: float = Wall.DEFAULT_HEIGHT_M[Wall.Kind.ROW]
	if preset < 0 or preset >= count():
		return fallback
	var info: Dictionary = INFO.get(ProcgenStreetSpecies.NAMES[preset], {})
	return float(info.get("setback_m", fallback))


## The readout name of species `preset` (clamped into range): "Mixed", "Guild houses"...
static func readout_name(preset: int) -> String:
	return _plain(ProcgenStreetSpecies.NAMES[clampi(preset, 0, count() - 1)])


## "guild_houses" as "Guild houses".
static func _plain(species_name: String) -> String:
	var spaced := species_name.replace("_", " ")
	return spaced.substr(0, 1).to_upper() + spaced.substr(1)


## The region tags procgen gives species `preset` (what StreetSplit favours when the biome names
## none); empty for an unknown preset.
static func regions(preset: int) -> Array[String]:
	var out: Array[String] = []
	if preset < 0 or preset >= count():
		return out
	var species := ProcgenStreetSpecies.named(ProcgenStreetSpecies.NAMES[preset])
	for tag: Variant in species.get("region", []):
		out.append(String(tag))
	return out
