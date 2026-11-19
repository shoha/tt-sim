class_name PainterGlbRoles
extends RefCounted

## How the painted look reads the nodes of a GLB map (docs/systems/painter.md "GLB maps"): the
## pure functions behind PainterGlbMap. A Blender-made map.glb usually has no role data, so the
## rules read what every file carries: node and material names, the mesh's own shape and its
## materials' colours. The optional extras tt_paint_role and tt_ground (ASSET_PIPELINE.md "Painter
## roles", read here and nowhere else) state a role outright and win over those rules: explicit
## extra, then name and material, then shape and colour. Every function is pure and answers "leave
## it as authored" ("" or false) when it cannot tell (the one side effect: a warning line, once, for
## an unknown extras value).

## [sheet role, words], first match wins (substrings of the lower-case material name, then node
## name). The roles are sheet colour roles (PainterSheet.COLOR_ROLES), toned with
## PainterTones.ramp.
const PROP_WORDS: Array = [
	["roof-slate", ["slate"]],
	["roof-thatch", ["thatch"]],
	["roof-shingle", ["shingle"]],
	["roof-turf", ["turf", "sod_roof"]],
	["roof-clay", ["roof", "tile", "terracotta"]],
	["leaf", ["leaf", "leaves", "foliage", "hedge", "ivy", "moss", "canopy"]],
	[
		"bark",
		[
			"wood",
			"plank",
			"timber",
			"beam",
			"board",
			"door",
			"barrel",
			"crate",
			"fence",
			"log",
			"bark",
			"cart",
			"wagon",
			"chest",
			"bench",
			"post",
			"trunk"
		]
	],
	[
		"stone",
		[
			"stone",
			"brick",
			"rock",
			"cobble",
			"masonry",
			"wall",
			"plaster",
			"mortar",
			"concrete",
			"marble",
			"column",
			"pillar",
			"stair",
			"well",
			"ruin"
		]
	],
]
## Words of a surface the painted look leaves as authored: lights and ironwork, as the buildings do
## (painter-coverage: panes, lantern glass, glow and metal are Classic by decision), and water.
const KEEP_WORDS: Array[String] = [
	"glass",
	"window",
	"pane",
	"lantern",
	"lamp",
	"glow",
	"flame",
	"fire",
	"emit",
	"water",
	"lava",
	"metal",
	"iron",
	"gold",
	"brass",
	"steel",
]
## [species words, a species-table asset group] of a tree the painted look grows, for a GLB tree
## whose name is not treecube's (Tree_Oak ...): a token of the name that is, or starts with, a
## word.
const TREE_WORDS: Array = [
	["oak", "Tree_Oak"],
	["birch", "Tree_Birch"],
	["poplar", "Tree_Poplar"],
	["willow", "Tree_Willow"],
	["spruce", "Tree_Spruce"],
	["pine", "Tree_Pine"],
	["conifer", "Tree_Spruce"],
	["fir", "Tree_Spruce"],
]
## The height (m) of the core library's tree of each species the painted look grows (its asset's
## dimensions_m), the size a row of scale 1 is drawn at: a GLB tree's rows are scaled by its
## mesh's height over this, so a painted tree stands as tall as the tree it replaces.
const NOMINAL_HEIGHT := {
	"oak": 9.3,
	"birch": 12.5,
	"lime": 7.8,
	"poplar": 12.6,
	"willow": 7.8,
	"spruce": 12.0,
	"rowan": 5.0,
}
const DEFAULT_NOMINAL_HEIGHT := 9.0
## The scale a GLB tree's rows are limited to (its mesh height over the nominal).
const TREE_SCALE_RANGE := Vector2(0.2, 4.0)
## A ground mesh is at least this wide (m) on its longer side and half of it on its shorter, rises
## at most this fraction of its width, and faces up over this share of its sampled vertices.
const GROUND_MIN_M := 6.0
const GROUND_RELIEF := 0.6
const GROUND_UP_SHARE := 0.5
## The vertices a mesh is sampled at (an evenly strided subset of at most this many).
const SAMPLES := 4096
## A planar UV fit is accepted when no sampled vertex is off by more than this in UV units.
const UV_TOLERANCE := 0.02
## The optional painter-role extras (ASSET_PIPELINE.md "Painter roles"): glTF extras on a node, its
## mesh or a material, which the loader leaves as "extras" metadata.
const ROLE_KEY := "tt_paint_role"
const GROUND_KEY := "tt_ground"
const EXTRAS_META := &"extras"
## tt_paint_role value -> the sheet role a prop surface is painted in ("" keeps it as authored).
const EXTRA_PROP_ROLES := {
	"roof": "roof-clay", "bark": "bark", "stone": "stone", "leaf": "leaf", "keep": "",
}
## tt_paint_role value -> the ground zone a terrain mesh is painted as.
const EXTRA_GROUND_ZONES := {
	"ground-meadow": "meadow", "ground-path": "path", "ground-rock": "rock",
}
## The colour (sRGB) of a one-texel stand-in albedo that the ground shader's zone read
## (glb_classify) sorts into a zone: warm is path, neutral grey is rock. Meadow needs none
## (base_meadow).
const ZONE_SWATCH := {"path": Color(0.72, 0.56, 0.36), "rock": Color(0.55, 0.55, 0.55)}

## The extras values already warned about this session ("key=value"): one warning line each.
static var _unknown_logged: Dictionary = {}


## The painted tree species of a GLB tree source named `source_name` ("" when the painted look does
## not grow it: the mesh stays and is painted by surface instead). treecube's names resolve through
## the species table directly; other names by their words (an oak is an oak).
static func tree_species(source_name: String) -> String:
	var direct := PainterTreeSpecies.species_for(source_name)
	if direct != "" and not PainterTreeSpecies.is_bush(direct):
		return direct
	var tokens := _tokens(source_name)
	for pair: Array in TREE_WORDS:
		var word: String = pair[0]
		for token: String in tokens:
			if token == word or (word.length() >= 3 and word != "fir" and token.begins_with(word)):
				return PainterTreeSpecies.species_for(str(pair[1]))
			if word.length() >= 4 and token.contains(word):
				return PainterTreeSpecies.species_for(str(pair[1]))
	return ""


## The factor a GLB tree of `species` and mesh height `height` (m) multiplies its rows' scale by.
static func tree_scale(species: String, height: float) -> float:
	var nominal := float(NOMINAL_HEIGHT.get(species, DEFAULT_NOMINAL_HEIGHT))
	return clampf(height / nominal, TREE_SCALE_RANGE.x, TREE_SCALE_RANGE.y)


## The painter-role extras that apply to a surface of `node` (null for none), `mesh` and `material`
## (null for none): the keys tt_paint_role and tt_ground from each one's "extras" metadata, the
## most specific winning per key (material over node over mesh). {} when none is there.
static func extras_of(node: Object, mesh: Object = null, material: Object = null) -> Dictionary:
	var out := {}
	for source: Object in [mesh, node, material]:
		if source == null or not source.has_meta(EXTRAS_META):
			continue
		var extras: Variant = source.get_meta(EXTRAS_META)
		if not extras is Dictionary:
			continue
		for key: String in [ROLE_KEY, GROUND_KEY]:
			if (extras as Dictionary).has(key):
				out[key] = (extras as Dictionary)[key]
	return out


## The tt_paint_role of `extras` (extras_of) when it is one of the contract's values (lower-case,
## trimmed); "" when absent or unknown (an unknown value is ignored, with one warning line).
static func extra_role(extras: Dictionary) -> String:
	if not extras.has(ROLE_KEY):
		return ""
	var raw: Variant = extras[ROLE_KEY]
	var value := str(raw).strip_edges().to_lower() if raw is String else ""
	if EXTRA_PROP_ROLES.has(value) or EXTRA_GROUND_ZONES.has(value):
		return value
	_warn_unknown(ROLE_KEY, raw)
	return ""


## Whether `extras` mark a mesh as ground: 1 for tt_ground true or a ground-* role, -1 for tt_ground
## false or the keep role (never ground), 0 when they say nothing (the shape rule decides).
static func ground_mark(extras: Dictionary) -> int:
	var role := extra_role(extras)
	if EXTRA_GROUND_ZONES.has(role):
		return 1
	if role == "keep":
		return -1
	if not extras.has(GROUND_KEY):
		return 0
	var flag := _flag_of(extras[GROUND_KEY])
	if flag == 0:
		_warn_unknown(GROUND_KEY, extras[GROUND_KEY])
	return flag


## The ground zone a ground-* role forces ("meadow", "path" or "rock"), "" when `extras` name none
## (the zones are then read from the mesh's baked albedo).
static func ground_zone(extras: Dictionary) -> String:
	return str(EXTRA_GROUND_ZONES.get(extra_role(extras), ""))


## The extras values warned about so far, "key=value" (tests).
static func unknown_logged() -> Array:
	return _unknown_logged.keys()


## Forgets the warned values, so the next unknown one warns again (tests).
static func forget_unknown() -> void:
	_unknown_logged.clear()


## The sheet role a prop surface is painted in: the tt_paint_role in `extras` when it names one
## (keep gives ""), else from its material's name, then the node's, then the material's own colour
## when it has no texture; "" leaves the surface as authored (a light, a pane, ironwork, water, or a
## textured surface whose name says nothing: its colour lives in a picture the painted look does not
## read).
static func prop_role(
	material_name: String,
	node_name: String,
	color: Color,
	textured: bool,
	extras: Dictionary = {}
) -> String:
	var given := extra_role(extras)
	if EXTRA_PROP_ROLES.has(given):
		return str(EXTRA_PROP_ROLES[given])
	var names := [material_name.to_lower(), node_name.to_lower()]
	for text: String in names:
		for word in KEEP_WORDS:
			if text.contains(word):
				return ""
	for text: String in names:
		for rule: Array in PROP_WORDS:
			for word: String in rule[1]:
				if text.contains(word):
					return str(rule[0])
	if textured:
		return ""
	return role_of_color(color)


## The role of a flat colour: greens are leaves, dark browns wood, reds clay roofs, dark greys
## slate, everything else stone.
static func role_of_color(color: Color) -> String:
	var s := color.s
	var v := color.v
	var hue := color.h * 360.0
	if s < 0.15:
		return "roof-slate" if v < 0.28 else "stone"
	if hue >= 70.0 and hue < 170.0:
		return "leaf"
	if (hue < 22.0 or hue >= 340.0) and s > 0.4 and v > 0.3:
		return "roof-clay"
	if hue >= 12.0 and hue < 65.0 and v < 0.62:
		return "bark"
	return "stone"


## Whether a mesh reads as ground: wide, shallow and mostly facing up. `size` is its AABB size,
## `up_share` the share of its sampled vertex normals pointing up (up_share_of).
static func is_ground(size: Vector3, up_share: float) -> bool:
	var wide := maxf(size.x, size.z)
	var narrow := minf(size.x, size.z)
	return (
		wide >= GROUND_MIN_M
		and narrow >= GROUND_MIN_M * 0.5
		and size.y <= wide * GROUND_RELIEF
		and up_share >= GROUND_UP_SHARE
	)


## The share of an evenly strided sample of `normals` (at most SAMPLES) that points up (y over
## 0.6).
static func up_share_of(normals: PackedVector3Array) -> float:
	if normals.is_empty():
		return 0.0
	var stride := maxi(normals.size() / SAMPLES, 1)
	var up := 0
	var count := 0
	for i in range(0, normals.size(), stride):
		count += 1
		if normals[i].y > 0.6:
			up += 1
	return float(up) / float(count)


## The planar mapping from the map's XZ to a mesh's UV: {"ok", "uv" (Vector4: the 2 x 2 matrix's
## columns, as the ground shader's glb_uv), "b" (Vector2), "scale" (the larger UV per metre)} from
## `xz` (the vertices' world XZ) and `uvs`, the same length. "ok" is false when the vertices are
## not one affine map (a mesh unwrapped in pieces, or one with no area).
static func uv_affine(xz: PackedVector2Array, uvs: PackedVector2Array) -> Dictionary:
	var fail := {"ok": false}
	if xz.size() < 3 or xz.size() != uvs.size():
		return fail
	var stride := maxi(xz.size() / SAMPLES, 1)
	var i0 := 0
	var i1 := 0
	var far := 0.0
	for i in range(0, xz.size(), stride):
		var d := xz[i].distance_squared_to(xz[i0])
		if d > far:
			far = d
			i1 = i
	if far <= 0.0:
		return fail
	var d1 := xz[i1] - xz[i0]
	var i2 := 0
	var best := 0.0
	for i in range(0, xz.size(), stride):
		var area := absf(d1.cross(xz[i] - xz[i0]))
		if area > best:
			best = area
			i2 = i
	if best <= 0.0001 * far:
		return fail
	var d2 := xz[i2] - xz[i0]
	var det := d1.x * d2.y - d2.x * d1.y
	var u1 := uvs[i1] - uvs[i0]
	var u2 := uvs[i2] - uvs[i0]
	var m00 := (u1.x * d2.y - u2.x * d1.y) / det
	var m01 := (-u1.x * d2.x + u2.x * d1.x) / det
	var m10 := (u1.y * d2.y - u2.y * d1.y) / det
	var m11 := (-u1.y * d2.x + u2.y * d1.x) / det
	var offset := (
		uvs[i0] - Vector2(m00 * xz[i0].x + m01 * xz[i0].y, m10 * xz[i0].x + m11 * xz[i0].y)
	)
	for i in range(0, xz.size(), stride):
		var uv := Vector2(m00 * xz[i].x + m01 * xz[i].y, m10 * xz[i].x + m11 * xz[i].y) + offset
		if uv.distance_to(uvs[i]) > UV_TOLERANCE:
			return fail
	return {
		"ok": true,
		"uv": Vector4(m00, m10, m01, m11),
		"b": offset,
		"scale": maxf(Vector2(m00, m10).length(), Vector2(m01, m11).length()),
	}


## 1 for true, a non-zero number or "true"; -1 for false, zero or "false"; 0 for anything else.
static func _flag_of(value: Variant) -> int:
	if value is bool:
		return 1 if value else -1
	if value is int or value is float:
		return 1 if float(value) != 0.0 else -1
	if value is String:
		var text := (value as String).strip_edges().to_lower()
		if text == "true":
			return 1
		if text == "false":
			return -1
	return 0


## Logs one warning line per distinct unknown extras value.
static func _warn_unknown(key: String, value: Variant) -> void:
	var tag := "%s=%s" % [key, str(value)]
	if _unknown_logged.has(tag):
		return
	_unknown_logged[tag] = true
	push_warning("PainterGlbRoles: ignoring the unknown painter extra %s (ASSET_PIPELINE.md)" % tag)


## The lower-case letter runs of `text` ("Tree_Oak.003" gives tree, oak).
static func _tokens(text: String) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	for ch in text.to_lower():
		if ch >= "a" and ch <= "z":
			current += ch
		elif current != "":
			out.append(current)
			current = ""
	if current != "":
		out.append(current)
	return out
