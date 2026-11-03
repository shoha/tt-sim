class_name AuthoredSettlements
extends Node3D

## The furnishings of the document's dressed streets (Settlement) as nodes: a derived layer, so
## nothing here is saved or sent; every peer derives the same list (SettlementPlan) from the record
## and the street's lots. The placements are stood on the ground (a placement on water or on a
## steep bank is skipped), grouped into cells of CELL_M metres and each cell baked into ONE
## MeshInstance3D with one surface per material (SettlementBake), so a 150 m street is a few
## draws. No collision: furnishings are walk-through (docs/systems/villages.md "Collision").
##
## A cell is keyed by its placements, the ground heights under them and the variants they use; a
## refresh rebuilds only the cells whose key moved, so moving one house re-bakes the cell of its
## frontage. The prop variants (four draws of each prop, StructureGeometry.build_one) are built
## once, one per frame budget step, and kept for every map. Summary: docs/systems/settlements.md.

const NODE_NAME := "AuthoredSettlements"
const CELL_M := 48.0
## Wall-clock budget of the work _process does in a frame (a variant build or a cell bake each).
const INSTALL_BUDGET_MS := 3.0
## Sample offset for the slope test, and the steepest rise over its 2x run that holds a prop.
const SLOPE_STEP_M := 0.6
const SLOPE_LIMIT := 0.8
## Props stand this far into the ground (metres).
const SINK_M := 0.03
const META := &"tt_settlement"

## ref -> {"surfaces": [...]} of the built variants (shared by every map: a library's recipes
## do not change under a running game; tests clear it).
static var _variants: Dictionary = {}
static var _flat: MapDocument = null

var version: int = 0
## Cells rebuilt by the last refresh() or flush().
var last_rebuilt: int = 0
var builds: int = 0
## Placements the last refresh dropped for water or a steep bank, and for a missing prop.
var skipped_ground: int = 0
var skipped_missing: int = 0
## Placements standing (all cells).
var placed: int = 0
## Microseconds the last refresh() took (plans and keys, not the bakes).
var last_refresh_usec: int = 0

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _materials: Dictionary = {}
## Cell node name -> key it was built from.
var _keys: Dictionary = {}
## Settlement id -> {"sig": String, "items": Array[Dictionary]} (the plan of the last refresh).
var _plans: Dictionary = {}
## Cells still to bake: node name -> {"key", "settlement", "items": [{"item", "y", "ref"}]}.
var _todo: Dictionary = {}
## Variant refs still to build, with the prop (name, seed) each is.
var _missing: Dictionary = {}


static func of_map(root: Node3D) -> AuthoredSettlements:
	var layer := root.get_node_or_null(NODE_NAME) as AuthoredSettlements
	if layer == null:
		layer = AuthoredSettlements.new()
		layer.name = NODE_NAME
		root.add_child(layer)
	return layer


## The layer under map root `root`, created if missing, brought up to `doc`. Nothing is created
## for a document with no settlement. The fields' plants (AuthoredFieldPlants) and the villages'
## stone boundaries (AuthoredBoundaries) follow with it.
static func refresh_map(root: Node3D, doc: MapDocument) -> AuthoredSettlements:
	AuthoredFieldPlants.refresh_map(root, doc)
	AuthoredBoundaries.refresh_boundaries(root, doc)
	var layer := root.get_node_or_null(NODE_NAME) as AuthoredSettlements
	if layer == null:
		if doc.settlements.is_empty():
			return null
		layer = of_map(root)
	layer.refresh(doc)
	return layer


## Forgets the built variants (a library changed, or a test wants a cold start).
static func clear_variants() -> void:
	_variants.clear()


## Brings the cells up to `doc`: plans every settlement again when its record or its lots moved,
## drops the cells that are gone and queues those whose key moved. The bakes happen in _process
## (INSTALL_BUDGET_MS a frame) or at once in flush().
func refresh(doc: MapDocument) -> void:
	var started := Time.get_ticks_usec()
	StructureRecipes.ensure_served()
	skipped_ground = 0
	skipped_missing = 0
	var wanted := {}
	var live := {}
	# One fingerprint of the ground for every settlement (it is read twice per street otherwise).
	var ground_print := 0
	if not doc.settlements.is_empty():
		ground_print = StructureGeometry.ground_fingerprint(doc)
	for settlement in doc.settlements:
		live[settlement.id] = true
		for cell: Dictionary in cells_of(doc, settlement, ground_print):
			wanted[cell["name"]] = true
			if (
				_keys.get(cell["name"]) == cell["key"]
				and get_node_or_null(NodePath(cell["name"])) != null
			):
				_todo.erase(cell["name"])
				continue
			if _todo.has(cell["name"]) and _todo[cell["name"]]["key"] == cell["key"]:
				continue
			_todo[cell["name"]] = cell
			for entry: Dictionary in cell["items"]:
				if not _variants.has(entry["ref"]):
					_missing[entry["ref"]] = true
	for id: int in _plans.keys():
		if not live.has(id):
			_plans.erase(id)
	for child in get_children():
		if not wanted.has(String(child.name)):
			_free_cell(String(child.name))
	for name_key: String in _todo.keys():
		if not wanted.has(name_key):
			_todo.erase(name_key)
	placed = 0
	for plan: Dictionary in _plans.values():
		placed += (plan["items"] as Array).size()
	set_process(not _todo.is_empty())
	last_refresh_usec = Time.get_ticks_usec() - started
	version += 1


## Bakes everything queued now: how many cells were made.
func flush() -> int:
	var made := 0
	while not _todo.is_empty() or not _missing.is_empty():
		made += _step(INF)
	last_rebuilt = made
	return made


## Cells still waiting for their bake.
func pending_count() -> int:
	return _todo.size()


## The names of the baked cells, sorted.
func cell_names() -> PackedStringArray:
	var out := PackedStringArray()
	for child in get_children():
		out.append(String(child.name))
	out.sort()
	return out


## The key of the baked cell `cell_name` ("" when none).
func key_of_cell(cell_name: String) -> String:
	return String(_keys.get(cell_name, ""))


## The standing placements of settlement `settlement_id` ({"item", "y", "ref"} rows, ground
## applied), or [] before its first refresh.
func standing(settlement_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var plan: Dictionary = _plans.get(settlement_id, {})
	for row: Dictionary in plan.get("rows", []):
		out.append(row)
	return out


## The built surfaces of prop variant `ref` ({"surfaces": [{"key", "role", "kind", "arrays"}]}),
## built now if it is not yet.
func variant(ref: String) -> Dictionary:
	_build_variant(ref)
	return _variants.get(ref, {})


func _process(_delta: float) -> void:
	_step(INSTALL_BUDGET_MS)
	if _todo.is_empty() and _missing.is_empty():
		set_process(false)


## One batch of work within `budget_ms`: variants first, then cells. Returns the cells made.
func _step(budget_ms: float) -> int:
	var started := Time.get_ticks_usec()
	var made := 0
	for ref: String in _missing.keys():
		_build_variant(ref)
		_missing.erase(ref)
		if (Time.get_ticks_usec() - started) / 1000.0 >= budget_ms:
			return made
	for name_key: String in _todo.keys():
		_bake_cell(_todo[name_key])
		_todo.erase(name_key)
		made += 1
		builds += 1
		if (Time.get_ticks_usec() - started) / 1000.0 >= budget_ms:
			break
	if made > 0:
		version += 1
	return made


# --- planning -----------------------------------------------------------------------------


## The cells of `settlement` as {"name", "key", "settlement", "items": [{"item", "y", "ref"}]},
## from its placements with the ground applied. Pure of the node tree (the layer's counters
## aside); the plan is cached per record and lots, and its rows are stood on the ground again only
## when the ground moved (`ground_print`: StructureGeometry.ground_fingerprint(doc), made once by
## refresh; 0 reads it here).
func cells_of(
	doc: MapDocument, settlement: Settlement, ground_print: int = 0
) -> Array[Dictionary]:
	var frontages := SettlementPlan.frontages_of(doc, settlement)
	var sig := settlement.fingerprint()
	for frontage in frontages:
		sig += "|" + JSON.stringify(frontage.to_dict(), "", true, true).md5_text()
	# The crossings keep props off their landings (_stand): a bridge laid or moved stands them again.
	var spans: Array = []
	for crossing in doc.crossings:
		spans.append([crossing.start, crossing.end, crossing.width_m])
	if not spans.is_empty():
		sig += "|%d" % hash(spans)
	var plan: Dictionary = _plans.get(settlement.id, {})
	var ground := ground_print if ground_print != 0 else StructureGeometry.ground_fingerprint(doc)
	if plan.get("sig", "") != sig:
		plan = {"sig": sig, "items": SettlementPlan.place(settlement, frontages)}
		_stand_plan(doc, plan, ground)
		_plans[settlement.id] = plan
	elif plan.get("ground") == ground and int(plan.get("missing", 0)) == 0:
		# The ground and the lots are as the rows were stood on: they stand as they did.
		skipped_ground += int(plan.get("skipped", 0))
	else:
		_stand_plan(doc, plan, ground)
	var by_cell := {}
	for row: Dictionary in plan["rows"]:
		var at: Vector2 = row["item"]["position"]
		var cell := Vector2i(floori(at.x / CELL_M), floori(at.y / CELL_M))
		if not by_cell.has(cell):
			by_cell[cell] = []
		(by_cell[cell] as Array).append(row)
	var out: Array[Dictionary] = []
	for cell: Vector2i in by_cell:
		var rows: Array = by_cell[cell]
		var lines := PackedStringArray()
		for row: Dictionary in rows:
			var item: Dictionary = row["item"]
			var at: Vector2 = item["position"]
			(
				lines
				. append(
					(
						"%s %s %d %d %d %d %d %d %d"
						% [
							item["slot"],
							row["ref"],
							roundi(at.x * 100.0),
							roundi(at.y * 100.0),
							roundi(float(item["yaw"]) * 1000.0),
							roundi(float(item["scale"]) * 100.0),
							roundi(float(row["y"]) * 1000.0),
								roundi((row["normal"] as Vector3).x * 100.0),
								roundi((row["normal"] as Vector3).z * 100.0),
						]
					)
				)
			)
		(
			out
			. append(
				{
					"name": "S%d_%d_%d" % [settlement.id, cell.x, cell.y],
					"key": "\n".join(lines).md5_text(),
					"settlement": settlement.id,
					"items": rows,
				}
			)
		)
	return out


## The rows of `items` that stand on dry, gentle ground: {"item", "y", "ref"}. A prop the library
## does not serve is left out.
func _stand(doc: MapDocument, items: Array[Dictionary]) -> Array[Dictionary]:
	var points := PackedVector2Array()
	var reaches := PackedFloat32Array()
	for item in items:
		var at: Vector2 = item["position"]
		var reach := footprint_reach(str(item["prop"]), SettlementBake.visual_scale(item))
		reaches.append(reach)
		points.append(at)
		points.append(at + Vector2(reach, 0.0))
		points.append(at - Vector2(reach, 0.0))
		points.append(at + Vector2(0.0, reach))
		points.append(at - Vector2(0.0, reach))
	var heights := WaterGeometry.grounds_at(doc, points)
	# A prop stands clear of the water under its whole drawn footprint and a strip of bank
	# (VillageDryGround.prop_ring: a log pile half in a stream beside a plank bridge, bridges_look3),
	# and of every bridge's deck and landings (a crate at the end of a plank bridge, a cart on an
	# arch's ramp).
	var wet := PackedByteArray()
	var corridors: Array[Dictionary] = VillageDryGround.crossing_corridors(doc)
	if VillageDryGround.has_water(doc) and not points.is_empty():
		var ring := PackedVector2Array()
		for k in items.size():
			ring.append_array(VillageDryGround.prop_ring(points[k * 5], reaches[k]))
		var near := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			near = near.expand(p)
		wet = VillageDryGround.wet_flags(doc, ring, near.grow(1.0))
	var rows: Array[Dictionary] = []
	for k in items.size():
		var item := items[k]
		var at: Vector2 = item["position"]
		var base := k * 5
		var reach := reaches[k]
		var run := reach * 2.0
		var rise := maxf(
			absf(heights[base + 1] - heights[base + 2]), absf(heights[base + 3] - heights[base + 4])
		)
		var soaked := false
		if not wet.is_empty():
			var first := k * VillageDryGround.PROP_RING_POINTS
			for i in range(first, first + VillageDryGround.PROP_RING_POINTS):
				soaked = soaked or wet[i] != 0
		if (
			rise / run > SLOPE_LIMIT
			or soaked
			or VillageDryGround.in_corridors(at, corridors, reach)
		):
			skipped_ground += 1
			continue
		var row := LibraryStructureStore.prop(str(item["prop"]), int(item["seed"]))
		if row.is_empty():
			skipped_missing += 1
			continue
		var five := PackedFloat32Array(
			[heights[base], heights[base + 1], heights[base + 2], heights[base + 3], heights[base + 4]]
		)
		rows.append(
			{
				"item": item,
				"y": ground_under(five) - SINK_M,
				"normal": ground_normal(five, reach),
				"ref": String(row["ref"]),
			}
		)
	return rows


## How far from a prop's origin the ground is read: 0.8 of its drawn radius, within 0.3 to 1.6 m.
static func footprint_reach(prop: String, drawn_scale: float) -> float:
	return clampf(ProcgenPropStyles.radius_of(prop) * drawn_scale * 0.8, 0.3, 1.6)


## The lowest of the five ground heights read under a prop (centre, +x, -x, +z, -z).
static func ground_under(five: PackedFloat32Array) -> float:
	var low := five[0]
	for h in five:
		low = minf(low, h)
	return low


## The ground's normal from the five heights read `reach` metres from the centre.
static func ground_normal(five: PackedFloat32Array, reach: float) -> Vector3:
	return Vector3(five[2] - five[1], reach * 2.0, five[4] - five[3]).normalized()


## The rows of a cached plan with the ground read again (a sculpt moved it; the plan did not).
func _stand_plan(doc: MapDocument, plan: Dictionary, ground: int) -> void:
	var items: Array[Dictionary] = []
	items.assign(plan["items"])
	var ground_before := skipped_ground
	var missing_before := skipped_missing
	plan["rows"] = _stand(doc, items)
	plan["ground"] = ground
	plan["skipped"] = skipped_ground - ground_before
	plan["missing"] = skipped_missing - missing_before


# --- building -----------------------------------------------------------------------------


func _build_variant(ref: String) -> void:
	if _variants.has(ref):
		return
	if _flat == null:
		_flat = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var surfaces: Array = []
	var size := _default_size(ref)
	var parts := StructureGeometry.build_one(
		_flat, Structure.make(1, ref, ProcgenProps.footprint(size), 5)
	)
	for mesh: Dictionary in parts.get("meshes", []):
		(
			surfaces
			. append(
				{
					"key": "%s:%s" % [mesh["role"], mesh["kind"]],
					"role": mesh["role"],
					"kind": mesh["kind"],
					"arrays": mesh["arrays"],
				}
			)
		)
	for mesh: Dictionary in parts.get("glow", []):
		surfaces.append(
			{
				"key": "%s:%s" % [mesh["role"], mesh["kind"]],
				"role": mesh["role"],
				"kind": mesh["kind"],
				"arrays": mesh["arrays"],
			}
		)
	_variants[ref] = {"surfaces": surfaces}


## The default footprint of the prop `ref` (its index entry's default_size_m).
static func _default_size(ref: String) -> Vector2:
	var row := LibraryStructureStore.structure(ref)
	var size: Array = row.get("default_size_m", [1.0, 1.0])
	return Vector2(float(size[0]), float(size[1]))


func _bake_cell(cell: Dictionary) -> void:
	var cell_name: String = cell["name"]
	_free_cell(cell_name)
	var placed_items: Array[Dictionary] = []
	for row: Dictionary in cell["items"]:
		if not _variants.has(row["ref"]):
			_build_variant(String(row["ref"]))
		(
			placed_items
			. append(
				{
					"variant": row["ref"],
					"transform": SettlementBake.transform_of(row["item"], float(row["y"]), row["normal"]),
				}
			)
		)
	var surfaces := SettlementBake.bake(placed_items, _variants)
	var node := MeshInstance3D.new()
	node.name = cell_name
	var mesh := ArrayMesh.new()
	var has_glow := false
	for surface in surfaces:
		has_glow = has_glow or String(surface["kind"]) == StructureGlow.KIND
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface["arrays"])
		mesh.surface_set_material(
			mesh.get_surface_count() - 1,
			_material(String(surface["kind"]), String(surface["role"]))
		)
	node.mesh = mesh
	if has_glow:
		node.extra_cull_margin = StructureGlow.CULL_MARGIN_M
	node.set_meta(META, int(cell["settlement"]))
	add_child(node)
	_keys[cell_name] = cell["key"]


## A one-piece node drawing the placement `row` ({"item", "y", "normal", "ref"} as `standing`
## gives them) with its own materials, faded to `transparency`, for the Village tool to carry at the
## pointer while a piece is dragged (it is not part of any cell and is the caller's to free).
func ghost_of(row: Dictionary, transparency: float) -> MeshInstance3D:
	var built := variant(String(row["ref"]))
	var mesh := ArrayMesh.new()
	for surface: Dictionary in built.get("surfaces", []):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface["arrays"])
		mesh.surface_set_material(
			mesh.get_surface_count() - 1,
			_material(String(surface["kind"]), String(surface["role"]))
		)
	var node := MeshInstance3D.new()
	node.name = "PieceGhost"
	node.mesh = mesh
	node.transparency = transparency
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = SettlementBake.transform_of(row["item"], float(row["y"]), row["normal"])
	return node


func _free_cell(cell_name: String) -> void:
	var node := get_node_or_null(NodePath(cell_name))
	if node != null:
		remove_child(node)
		node.free()
	_keys.erase(cell_name)


func _material(kind: String, role: String) -> Material:
	var key := "%s:%s" % [role, kind]
	if not _materials.has(key):
		_materials[key] = StructureMaterials.make(kind, role, "", _palette_root)
	return _materials[key]
