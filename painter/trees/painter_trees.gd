class_name PainterTrees
extends RefCounted
## The painted trees (docs/systems/painter.md "Trees"): while a level is drawn Painted, every
## scatter tree row of a mapped species (PainterTreeSpecies) is drawn as a tree the painted look
## grows itself, and that species' GLB chunk nodes are hidden; release() frees every painted
## node and shows exactly the GLB nodes it hid. PainterSurfaces owns one (made by path on the
## first painted map, so neither the start-up nor a Classic level compiles it) and drives it from
## the events it already follows: paint() with the map, sync() on the scatter's cells_applied and
## species_added, retone() on a new mood or sun, release() when the look leaves Painted. It never
## polls the rows.
##
## The draw. A tree is its packed masses (PainterTreePack) in the mass texture (layers of 256 x
## 256 RGBA float texels, a tree in one layer), one row of the tree table (tree_tex), one line of
## the row map (its nine roles' style rows and its eight nearest crowns within NEAR_M) and one
## column of the occluder table (its first crown form). Trees are grouped in cells of CELL_M; a
## cell has five MultiMeshInstance3D sharing the meshes of PainterTreeMeshes: the block-in's
## ellipsoids and limb ribbons (cast the sun's shadow) and stroke levels 0, 1 and 2 (cast none).
## A level shows while |clamp(lod, 0, 2) - level| < 0.999, lod = 1 - log2(camera size /
## HOME_SIZE); the camera's size is the one value read each frame (no zoom signal exists), and the
## level nodes and the uniform change only when it does.
##
## Growing. New rows grow on the WorkerThreadPool in chunks of GROW_CHUNK (nearest the camera
## first) and are installed on the main thread a few at a time, INSTALL_MS a frame, by one-shot
## process_frame callbacks while work is pending; an erased row frees its tree row at once.
##
## Every value of a tree is its row's (PainterTreeSpecies: species, age, openness from the
## document's biome density at the row, seed), so a peer grows the same tree. Colours are
## PainterTreeTones' (the sheet's, following the mood and the sun); the sun's direction is the
## foliage_sun global the shaders read, the wind tt-sim's globals.
##
## Bushes (painter-bushes). A row of a card-built bush (PainterTreeSpecies.BUSH) is drawn here too,
## as a crown with no skeleton: PainterTreeBush lays a few leaf pads in the asset mesh's box at the
## row's scale (no box until the asset has resolved, so no bush until then), and its GLB chunks hide
## as a tree's do. A bush's strokes and pads are a crown's, in a row of its own (the tree table's
## texel 3 w is 2: the token window thins it stroke by stroke but never takes it whole). Bushes sit
## in cells of their own, BUSH_CELL_M wide, whose nodes instance smaller blocks (BUSH_ELL_PER_INST
## spheres, BUSH_SLOT_PER_INST stroke slots), so a bush does not pay for a tree's 64 slots; and no
## tree lists a bush among its neighbouring forms.

const STROKE_SHADER := "res://painter/shaders/painter_tree_stroke.gdshader"
const BLOCKIN_SHADER := "res://painter/shaders/painter_tree_blockin.gdshader"
## The same bodies with TREE_BARE: a bare season's leaf drop (retone swaps them in), so a tree in
## leaf runs none of its code.
const STROKE_BARE_SHADER := "res://painter/shaders/painter_tree_stroke_bare.gdshader"
const BLOCKIN_BARE_SHADER := "res://painter/shaders/painter_tree_blockin_bare.gdshader"
const UNIFORMS := "res://painter/trees/tree_uniforms.json"
const ROOT_NAME := "PainterTrees"
## Metadata on every material and node this draws with.
const META := &"painter_tree"
const CELL_M := 5.0
const GROW_CHUNK := 12
const INSTALL_MS := 2.0
const HOME_SIZE := 13.85
const MAP_W := 17
const NEAR_M := 18.0
const BOUND_GROW := 2.5
const LEVELS := 3
## The cast shadow's tint on the block-in's limbs (the crowns keep the shader's cool default): a
## near-neutral step, so a stem in its crown's shadow stays its own brown (painter-a2a4: a red-heavy
## 0.6/0.55/0.55 read dark chocolate under every crown).
const BARK_CAST_TINT := Vector3(0.66, 0.66, 0.68)
## A bush cell's width (metres) and its nodes' instance blocks (a bush is at most four pads and,
## but for a very large one, sixteen slots of two roots: PainterTreeBush; painter-look-bushes).
const BUSH_CELL_M := 15.0
const BUSH_ELL_PER_INST := 4
const BUSH_SLOT_PER_INST := 16

## key (PainterTreeSpecies.key_of) -> {"row", "d", "pos", "cell", "species", "bush"} for every tree
## and bush drawn.
var trees: Dictionary = {}
## cell -> {"keys": {key: true}, "nodes": [5 MultiMeshInstance3D]}.
var cells: Dictionary = {}
## The bushes' cells (BUSH_CELL_M), as `cells`.
var bush_cells: Dictionary = {}

var _map: Node3D = null
var _scatters: Array[AuthoredScatter] = []
var _doc: MapDocument = null
var _root: Node3D = null
## 0 block ellipsoids, 1 block limbs, 2..4 stroke levels 0..2.
var _materials: Array[ShaderMaterial] = []
## tree_uniforms.json: "block" and "stroke" (in leaf), "bare" (what a bare season sets instead).
var _uniforms: Dictionary = {}
var _hidden: Dictionary = {}
var _free_rows: Array[int] = []
var _rows: Array[Dictionary] = []
var _tree_cap := 256
var _tree_data := PackedFloat32Array()
var _tree_tex: ImageTexture = null
var _tree_dirty := false
var _layers: Array[Dictionary] = []
var _dirty_layers: Dictionary = {}
var _mass_tex: Texture2DArray = null
var _tex_layers := 0
## The growth in flight, oldest first: {"keys", "jobs", "out", "groups", "waited", "next"}.
var _batches: Array[Dictionary] = []
## Keys queued in a batch and not installed yet.
var _pending: Dictionary = {}
## The rows of the last sync (wanted()).
var _want: Dictionary = {}
var _step_queued := false
var _watching := false
var _lod := -99.0
## Whether the last retone chose a bare season's shader variants (every slot of a tree is drawn
## then; in leaf only its live prefix, d "n_live": PainterTreeBurial).
var _bare := false
## False draws every slot in leaf too (the painter-perf-buried A/B; set_live_counts).
var _live_counts := true


## Draws the mapped tree rows of `scatters` under `map` in `state` ({"sheet", "mood",
## "elevation"}); `doc` (may be null) gives the biome density for each tree's openness.
func paint(
	map: Node3D, scatters: Array[AuthoredScatter], doc: MapDocument, state: Dictionary
) -> void:
	if map != _map:
		release()
	if map == null:
		return
	_map = map
	_scatters = scatters
	_doc = doc
	if _materials.is_empty():
		_make_materials()
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = ROOT_NAME
		_root.set_meta(META, true)
		_map.add_child(_root)
	for scatter in _scatters:
		if not scatter.child_entered_tree.is_connected(_on_scatter_child):
			scatter.child_entered_tree.connect(_on_scatter_child)
	retone(PainterSheet.load_sheet(str(state["sheet"])), str(state["mood"]), float(state["elevation"]))
	sync()
	_watch()


## Puts the tones of `mood` at sun `elevation` on every tree material.
func retone(sheet: Dictionary, mood: String, elevation: float) -> void:
	if _materials.is_empty() or sheet.is_empty():
		return
	var baked := PainterTreeTones.bake(sheet, mood, elevation)
	var palette := ImageTexture.create_from_image(baked["palette"])
	var params := ImageTexture.create_from_image(baked["params"])
	# A bare season's broadleaf crowns shade nothing as whole forms (form_occ skips them): the
	# clumps they keep and the limbs under them are lit.
	var crown_occ := 1.0 if PainterSheet.number(sheet, mood, "leaf-keep", elevation) >= 0.999 else 0.0
	# Its leaf drop in the bare shader variants, its limbs drawn finer and snowy (tree_uniforms.json
	# "bare"); in leaf the plain variants and the leaf values, so a summer or autumn tree costs what
	# it did before the bare season (painter-winter-trees2). A variant is swapped only when the
	# season changes (a shader swap compiles).
	var bare: Dictionary = _uniforms.get("bare", {})
	var is_bare := crown_occ < 0.5
	for i in _materials.size():
		var m := _materials[i]
		var want := shader_path(i < 2, is_bare)
		if m.shader == null or m.shader.resource_path != want:
			m.shader = load(want) as Shader
		var own: Dictionary = _uniforms.get("block" if i < 2 else "stroke", {})
		for uniform_name: String in bare:
			var v: String = bare[uniform_name] if is_bare else own.get(uniform_name, "0.0")
			m.set_shader_parameter(uniform_name, str_to_var(v))
	if is_bare != _bare:
		# The slots a tree draws change with the variant: its stroke instances are made again.
		_bare = is_bare
		_restroke()
	for m in _materials:
		m.set_shader_parameter(&"crown_occ", crown_occ)
		m.set_shader_parameter(&"leaf_fall", 1.0 - crown_occ)
		m.set_shader_parameter(&"palette", palette)
		m.set_shader_parameter(&"role_params", params)
		m.set_shader_parameter(&"tone_lo", PainterSheet.number(sheet, mood, "tone-lo", elevation))
		m.set_shader_parameter(&"tone_hi", PainterSheet.number(sheet, mood, "tone-hi", elevation))
		m.set_shader_parameter(&"cut_amp", PainterSheet.number(sheet, mood, "cut", elevation))
		m.set_shader_parameter(&"cast_amount", PainterSheet.number(sheet, mood, "tree-cast", elevation))
		m.set_shader_parameter(&"deposit", PainterSheet.number(sheet, mood, "crown-deposit", elevation))


## The tree shader a material draws with: the block-in's (`block`) or the strokes', in leaf or in
## a bare season (`is_bare`).
static func shader_path(block: bool, is_bare: bool) -> String:
	if block:
		return BLOCKIN_BARE_SHADER if is_bare else BLOCKIN_SHADER
	return STROKE_BARE_SHADER if is_bare else STROKE_SHADER


## Brings the painted trees in line with the scatters' rows: grows the new, frees the gone.
func sync() -> void:
	if _map == null:
		return
	_hide_glb()
	_copy_occlusion()
	_want = wanted(_scatters, _doc)
	var dirty := {}
	for key: Vector3i in trees.keys():
		if not _want.has(key):
			_erase_tree(key, dirty)
	var todo: Array = []
	for key: Vector3i in _want:
		if not trees.has(key) and not _pending.has(key):
			todo.append(key)
	_rebuild(dirty)
	if not todo.is_empty():
		_grow(todo, _want)


## Frees every painted node, shows the GLB nodes it hid and forgets the map.
func release() -> void:
	_wait_all()
	_batches.clear()
	_pending.clear()
	_want = {}
	for scatter in _scatters:
		if is_instance_valid(scatter) and scatter.child_entered_tree.is_connected(_on_scatter_child):
			scatter.child_entered_tree.disconnect(_on_scatter_child)
	for id: int in _hidden:
		var node: Variant = _hidden[id]
		if is_instance_valid(node):
			(node as Node3D).visible = true
			(node as Node3D).remove_meta(OcclusionFadeManager.KEEP_HIDDEN_META)
	_hidden.clear()
	if _root != null and is_instance_valid(_root):
		# Out of the map at once, so a paint in the same frame makes a fresh root of the same name.
		if _root.get_parent() != null:
			_root.get_parent().remove_child(_root)
		_root.queue_free()
	_root = null
	trees.clear()
	cells.clear()
	bush_cells.clear()
	_rows.clear()
	_free_rows.clear()
	_layers.clear()
	_dirty_layers.clear()
	_mass_tex = null
	_tex_layers = 0
	_map = null
	_doc = null
	_scatters = []
	_lod = -99.0


## Whether trees are being drawn.
func is_active() -> bool:
	return _map != null


## Whether rows are still growing or waiting to be installed.
func is_growing() -> bool:
	return not _batches.is_empty()


## Grows and installs everything pending at once (tests and render jobs).
func complete() -> void:
	_wait_all()
	_install_some(INF)
	if _map != null:
		_copy_occlusion()


## The materials every cell node draws with (0, 1 block-in; 2..4 the stroke levels).
func materials() -> Array[ShaderMaterial]:
	return _materials


## The GLB chunk nodes hidden now.
func hidden_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for id: int in _hidden:
		if is_instance_valid(_hidden[id]):
			out.append(_hidden[id])
	return out


## Every mapped tree row of `scatters` as key -> {"pos", "species", "asset", "cx", "seed"}, and a
## bush's also "box" (PainterTreeBush.box_of; a bush whose asset has not resolved is left out)
## (pure in the rows, the document and the resolved meshes).
static func wanted(scatters: Array[AuthoredScatter], doc: MapDocument) -> Dictionary:
	var out := {}
	var stride := MapDocument.ROW_STRIDE
	for scatter in scatters:
		if not is_instance_valid(scatter):
			continue
		var by_asset := scatter.rows_by_asset()
		var resolved := {}
		for asset_id: String in by_asset:
			var species := PainterTreeSpecies.species_for(asset_id)
			if species == "":
				continue
			var aabb := AABB()
			if PainterTreeSpecies.is_bush(species):
				if resolved.is_empty():
					resolved = scatter.resolved_species()
				var mesh: Mesh = (resolved.get(asset_id, {}) as Dictionary).get("mesh")
				if mesh == null:
					continue
				aabb = mesh.get_aabb()
			var rows: PackedFloat32Array = by_asset[asset_id]
			for i in rows.size() / stride:
				var p := Vector3(rows[i * stride], rows[i * stride + 1], rows[i * stride + 2])
				var key := PainterTreeSpecies.key_of(p)
				var scale := rows[i * stride + PainterTreeSpecies.SCALE_AT]
				out[key] = {
					"pos": p,
					"species": species,
					"asset": asset_id,
					"cx": PainterTreeSpecies.context(asset_id, scale, p, density_at(doc, p)),
					"seed": PainterTreeSpecies.seed_of(key)
				}
				if PainterTreeSpecies.is_bush(species):
					out[key]["box"] = PainterTreeBush.box_of(aabb, scale)
	return out


## The document's biome density (0..1) at the sample nearest `p`, 0.5 without one.
static func density_at(doc: MapDocument, p: Vector3) -> float:
	if doc == null or doc.biome_density.size() != doc.sample_count():
		return 0.5
	var s := doc.world_to_sample(Vector2(p.x, p.z))
	var x := clampi(roundi(s.x), 0, doc.samples_x() - 1)
	var z := clampi(roundi(s.y), 0, doc.samples_z() - 1)
	return doc.biome_density[doc.sample_index(x, z)] / 255.0


# ---------------------------------------------------------------- materials


func _make_materials() -> void:
	var stroke := load(STROKE_SHADER) as Shader
	var block := load(BLOCKIN_SHADER) as Shader
	var values: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UNIFORMS))
	_uniforms = values
	var field := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	# Inert: a collector that ever reaches a tree material hands on this, never the tree shader.
	var placeholder := StandardMaterial3D.new()
	for k in 2 + LEVELS:
		var m := ShaderMaterial.new()
		m.shader = block if k < 2 else stroke
		var own: Dictionary = values["block" if k < 2 else "stroke"]
		for uniform_name: String in own:
			m.set_shader_parameter(uniform_name, str_to_var(own[uniform_name]))
		if k < 2:
			m.set_shader_parameter(&"kind10", float(k))
			if k == 1:
				# The limbs: a stem stands in its own crown's shadow, and the crowns' cool tint
				# turned brown bark maroon (painter-a2a3); a neutral step keeps it brown.
				m.set_shader_parameter(&"cast_tint", BARK_CAST_TINT)
		else:
			m.set_shader_parameter(&"pass10", float(k - 2))
			m.set_shader_parameter(&"brushes", PainterTreeBrushes.texture())
		# The prototype's field map (paths, patches under the crowns) has no tt-sim source yet:
		# a neutral texel, so no tree mark reads a field that is not there.
		m.set_shader_parameter(&"field16", ImageTexture.create_from_image(field))
		m.set_meta(META, true)
		m.set_meta(WindFoliage.META_STAND_IN, placeholder)
		_materials.append(m)
	_tree_data.resize(_tree_cap * PainterTreePack.TREE_W * 4)
	_tree_tex = ImageTexture.create_from_image(_tree_image())
	_set_all(&"tree_tex", _tree_tex)


func _set_all(uniform_name: StringName, value: Variant) -> void:
	for m in _materials:
		m.set_shader_parameter(uniform_name, value)


## Takes the token occlusion fade's binding from the scatter's own tree materials (the
## OcclusionFadeManager registered them), so a token under a painted crown shows as under a GLB one.
## painter-trees-fix: a level loaded Painted is painted before its fade manager registers anything,
## so this runs again when the growth has been installed (_step, complete()); with no registered
## source the window is off, never left reading an earlier table's freed token texture.
func _copy_occlusion() -> void:
	for scatter in _scatters:
		if not is_instance_valid(scatter):
			continue
		for asset_id: String in scatter.resolved_species():
			if PainterTreeSpecies.species_for(asset_id) == "":
				continue
			for source in scatter.species_materials(asset_id):
				if source.get_shader_parameter(&"enable_occlusion") != true:
					continue
				for uniform_name: StringName in [
					&"enable_occlusion",
					&"occlusion_tokens",
					&"min_alpha",
					&"lofi_pixelation",
					&"lofi_dither_scale"
				]:
					_set_all(uniform_name, source.get_shader_parameter(uniform_name))
				return
	_set_all(&"enable_occlusion", false)


# ---------------------------------------------------------------- the GLB nodes


func _hide_glb() -> void:
	for scatter in _scatters:
		if is_instance_valid(scatter):
			for child in scatter.get_children():
				_hide_node(child)


func _hide_node(node: Node) -> void:
	if not is_instance_valid(node) or not node is MultiMeshInstance3D or _map == null:
		return
	if PainterTreeSpecies.species_for(str(node.name)) == "" or not (node as Node3D).visible:
		return
	(node as Node3D).visible = false
	# The fade manager still binds this hidden node's materials (_copy_occlusion reads them).
	node.set_meta(OcclusionFadeManager.KEEP_HIDDEN_META, true)
	_hidden[node.get_instance_id()] = node


func _on_scatter_child(node: Node) -> void:
	# (A chunk node may be named after add_child: look once it is in place.)
	_hide_node.call_deferred(node)


# ---------------------------------------------------------------- growing


func _grow(keys: Array, want: Dictionary) -> void:
	var camera := _map.get_viewport().get_camera_3d() if _map.is_inside_tree() else null
	var at := Vector2(camera.global_position.x, camera.global_position.z) if camera else Vector2.ZERO
	keys.sort_custom(
		func(a: Vector3i, b: Vector3i) -> bool:
			var pa: Vector3 = want[a]["pos"]
			var pb: Vector3 = want[b]["pos"]
			return Vector2(pa.x, pa.z).distance_squared_to(at) < Vector2(pb.x, pb.z).distance_squared_to(at)
	)
	var jobs: Array = []
	for key: Vector3i in keys:
		var w: Dictionary = want[key]
		# (The architecture cache is filled here, on the main thread, before any worker reads it.)
		if not PainterTreeSpecies.is_bush(w["species"]):
			PainterTreeSpecies.architecture(w["species"])
		jobs.append(w)
		_pending[key] = true
	var out: Array = []
	out.resize(jobs.size())
	var groups: Array[int] = []
	for start in range(0, jobs.size(), GROW_CHUNK):
		var n := mini(GROW_CHUNK, jobs.size() - start)
		groups.append(WorkerThreadPool.add_group_task(_grow_job.bind(start, jobs, out), n))
	var waited: Array[bool] = []
	waited.resize(groups.size())
	_batches.append(
		{"keys": keys, "jobs": jobs, "out": out, "groups": groups, "waited": waited, "next": 0}
	)
	_queue_step()


## One tree grown and packed (a worker thread): reads only its job, writes only its slot.
static func _grow_job(i: int, start: int, jobs: Array, out: Array) -> void:
	var w: Dictionary = jobs[start + i]
	var species: String = w["species"]
	if PainterTreeSpecies.is_bush(species):
		var d := PainterTreePack.pack_bush(
			PainterTreeBush.masses(w["box"], int(w["seed"])), int(w["seed"])
		)
		d["bush"] = true
		out[start + i] = d
		return
	var masses := PainterTreeGrowth.tree(
		PainterTreeSpecies.architecture(species),
		w["cx"],
		int(w["seed"]),
		PainterTreeSpecies.is_conifer(species)
	)
	out[start + i] = PainterTreePack.pack(masses, int(w["seed"]), 3.0, PainterTreeSpecies.wide())


func _queue_step() -> void:
	if _step_queued:
		return
	_step_queued = true
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_step, CONNECT_ONE_SHOT)


func _step() -> void:
	_step_queued = false
	if _map == null:
		return
	_install_some(INSTALL_MS * 1000.0)
	if is_growing():
		_queue_step()
	else:
		_copy_occlusion()


## Installs the grown trees whose chunk has finished, nearest first, for about `budget_us` of
## this frame; a row erased or moved meanwhile (not in the last sync's rows) is dropped.
func _install_some(budget_us: float) -> void:
	var t0 := Time.get_ticks_usec()
	var dirty := {}
	while not _batches.is_empty() and Time.get_ticks_usec() - t0 < budget_us:
		var b: Dictionary = _batches[0]
		var keys: Array = b["keys"]
		var next: int = b["next"]
		if next >= keys.size():
			_batches.pop_front()
			continue
		var chunk := next / GROW_CHUNK
		if not b["waited"][chunk]:
			if not WorkerThreadPool.is_group_task_completed(b["groups"][chunk]):
				break
			WorkerThreadPool.wait_for_group_task_completion(b["groups"][chunk])
			b["waited"][chunk] = true
		var key: Vector3i = keys[next]
		_pending.erase(key)
		if _want.has(key) and not trees.has(key):
			_install_tree(key, b["jobs"][next], b["out"][next], dirty)
		b["out"][next] = null
		b["next"] = next + 1
	_rebuild(dirty)


## Waits for every chunk in flight (release() and complete()).
func _wait_all() -> void:
	for b: Dictionary in _batches:
		for k in (b["groups"] as Array).size():
			if not b["waited"][k]:
				WorkerThreadPool.wait_for_group_task_completion(b["groups"][k])
				b["waited"][k] = true


func _install_tree(key: Vector3i, w: Dictionary, d: Dictionary, dirty: Dictionary) -> void:
	var p: Vector3 = w["pos"]
	var row: int = _free_rows.pop_back() if not _free_rows.is_empty() else _new_row()
	var e := _rows[row]
	e["hue"] = (PainterTreeSpecies._vnoise(p.x / 11.0 + 40.0, p.z / 11.0 + 40.0) - 0.5) * 0.75
	e["value"] = (PainterTreeSpecies._vnoise(p.x / 11.0 + 90.0, p.z / 11.0 + 7.0) - 0.5) * 0.09
	e["moss"] = smoothstep(0.55, 1.0, float((w["cx"] as Dictionary)["age"]))
	_place(row, d)
	var bush := bool(d.get("bush", false))
	var cell_m := BUSH_CELL_M if bush else CELL_M
	var cell := Vector2i(floori(p.x / cell_m), floori(p.z / cell_m))
	var store := bush_cells if bush else cells
	if not store.has(cell):
		store[cell] = {"keys": {}, "nodes": []}
	store[cell]["keys"][key] = true
	dirty[_dirty_key(cell, bush)] = true
	trees[key] = {
		"row": row, "d": d, "pos": p, "cell": cell, "species": w["species"], "bush": bush
	}


func _erase_tree(key: Vector3i, dirty: Dictionary) -> void:
	var t: Dictionary = trees[key]
	var row: int = t["row"]
	var e := _rows[row]
	if int(e["layer"]) >= 0:
		var layer := _layers[int(e["layer"])]
		layer["used"] = int(layer["used"]) - int(e["texels"])
		(layer["rows"] as Array).erase(row)
		_dirty_layers[int(e["layer"])] = true
	e["layer"] = -1
	e["texels"] = 0
	_free_rows.append(row)
	var bush: bool = t["bush"]
	((bush_cells if bush else cells)[t["cell"]]["keys"] as Dictionary).erase(key)
	dirty[_dirty_key(t["cell"], bush)] = true
	trees.erase(key)


## A dirty set's key: a tree cell as itself, a bush cell as (x, z, 1).
static func _dirty_key(cell: Vector2i, bush: bool) -> Variant:
	return Vector3i(cell.x, cell.y, 1) if bush else cell


func _new_row() -> int:
	_rows.append({"layer": -1, "texels": 0, "base": 0})
	if _rows.size() > _tree_cap:
		_tree_cap *= 2
		_tree_data.resize(_tree_cap * PainterTreePack.TREE_W * 4)
		_tree_tex = ImageTexture.create_from_image(_tree_image())
		_set_all(&"tree_tex", _tree_tex)
	return _rows.size() - 1


## Gives a tree's texels room in a layer (the first with room, else a new one).
func _place(row: int, d: Dictionary) -> void:
	var need: int = d["texels"]
	var layer := -1
	for l in _layers.size():
		if int(_layers[l]["used"]) + need <= PainterTreePack.LAYER_TEXELS:
			layer = l
			break
	if layer < 0:
		layer = _layers.size()
		_layers.append({"used": 0, "rows": []})
	(_layers[layer]["rows"] as Array).append(row)
	_layers[layer]["used"] = int(_layers[layer]["used"]) + need
	_dirty_layers[layer] = true
	var e := _rows[row]
	e["layer"] = layer
	e["texels"] = need
	e["d"] = d


# ---------------------------------------------------------------- the tables and the cells


## Uploads the changed layers and the tree table, rebuilds the row map and the occluders, and
## rebuilds the `dirty` cells.
func _rebuild(dirty: Dictionary) -> void:
	if dirty.is_empty() and _dirty_layers.is_empty():
		return
	_flush()
	_tables()
	for k: Variant in dirty:
		if k is Vector3i:
			_rebuild_cell(bush_cells, Vector2i(k.x, k.y), true)
		else:
			_rebuild_cell(cells, k, false)


func _layer_image(l: int) -> Image:
	var buf := PackedFloat32Array()
	var base := 0
	if l < _layers.size():
		for row: int in _layers[l]["rows"]:
			var e := _rows[row]
			e["base"] = base
			buf.append_array((e["d"] as Dictionary)["data"])
			base += int(e["texels"])
			_write_row(row)
	buf.resize(PainterTreePack.LAYER_TEXELS * 4)
	return Image.create_from_data(
		PainterTreePack.W, PainterTreePack.W, false, Image.FORMAT_RGBAF, buf.to_byte_array()
	)


func _write_row(row: int) -> void:
	var e := _rows[row]
	var r := PainterTreePack.tree_row(
		e["d"], e["layer"], e["base"], row, e["hue"], e["value"], 0.0, e["moss"], _live_counts
	)
	var w := row * PainterTreePack.TREE_W * 4
	for k in r.size():
		_tree_data[w + k] = r[k]
	_tree_dirty = true


func _tree_image() -> Image:
	return Image.create_from_data(
		PainterTreePack.TREE_W, _tree_cap, false, Image.FORMAT_RGBAF, _tree_data.to_byte_array()
	)


func _flush() -> void:
	if not _dirty_layers.is_empty():
		if _layers.size() > _tex_layers or _mass_tex == null:
			_tex_layers = _layers.size() + maxi(2, _layers.size() / 4)
			var images: Array[Image] = []
			for l in _tex_layers:
				images.append(_layer_image(l))
			_mass_tex = Texture2DArray.new()
			_mass_tex.create_from_images(images)
			_set_all(&"mass_tex", _mass_tex)
		else:
			for l: int in _dirty_layers:
				_mass_tex.update_layer(_layer_image(l), l)
		_dirty_layers.clear()
	if _tree_dirty:
		_tree_tex.update(_tree_image())
		_tree_dirty = false


## The row map (each tree's role rows and its eight nearest crowns) and the occluder table.
func _tables() -> void:
	var lines := maxi(_tree_cap, _rows.size())
	var rows := PackedFloat32Array()
	rows.resize(MAP_W * lines)
	rows.fill(-1.0)
	var occ := PackedFloat32Array()
	occ.resize(lines * 8)
	var grid := {}
	for key: Vector3i in trees:
		var t: Dictionary = trees[key]
		if t["bush"]:
			# (A bush is no tree's neighbouring form: the eight a tree lists stay its trees.)
			continue
		var gc := Vector2i(floori(t["pos"].x / 9.0), floori(t["pos"].z / 9.0))
		if not grid.has(gc):
			grid[gc] = []
		grid[gc].append(t)
	for key: Vector3i in trees:
		var t: Dictionary = trees[key]
		var p: Vector3 = t["pos"]
		var row: int = t["row"]
		var line := PainterTreeTones.role_rows(t["species"])
		for r in line.size():
			rows[row * MAP_W + r] = float(line[r])
		var near: Array = []
		var gc := Vector2i(floori(p.x / 9.0), floori(p.z / 9.0))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for q: Dictionary in grid.get(gc + Vector2i(dx, dz), []):
					var dist := (q["pos"] as Vector3).distance_to(p)
					if q != t and dist < NEAR_M:
						near.append(Vector2(dist, float(q["row"])))
		near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for k in mini(near.size(), 8):
			rows[row * MAP_W + 9 + k] = (near[k] as Vector2).y
		_occluder(occ, lines, row, p, (t["d"] as Dictionary)["forms"])
	var map_image := Image.create_from_data(MAP_W, lines, false, Image.FORMAT_RF, rows.to_byte_array())
	_set_all(&"row_map", ImageTexture.create_from_image(map_image))
	var occ_image := Image.create_from_data(lines, 2, false, Image.FORMAT_RGBAF, occ.to_byte_array())
	_set_all(&"occ_tex", ImageTexture.create_from_image(occ_image))


static func _occluder(
	occ: PackedFloat32Array, lines: int, row: int, p: Vector3, forms: Array
) -> void:
	var ow := row * 4
	if forms.is_empty():
		occ[ow] = p.x
		occ[ow + 1] = -50.0
		occ[ow + 2] = p.z
		occ[ow + 3] = 1.0
		for k in 3:
			occ[lines * 4 + ow + k] = 0.1
		return
	var form: Dictionary = forms[0]
	var c: Vector3 = form["c"]
	var r: Vector3 = (form["r"] as Vector3) * 0.85
	occ[ow] = p.x + c.x
	occ[ow + 1] = p.y + c.y
	occ[ow + 2] = p.z + c.z
	occ[ow + 3] = float(form["kind"])
	occ[lines * 4 + ow] = r.x
	occ[lines * 4 + ow + 1] = r.y
	occ[lines * 4 + ow + 2] = r.z


## The slots of tree data `d` a stroke node runs now: every slot in a bare season (or with
## live counts off), else the live prefix (the rest are roots the shader's burial test kills).
func _slot_units(d: Dictionary) -> int:
	return int(d["n_live"]) if _live_counts and not _bare else int(d["n_slots"])


## Draws every slot in leaf too (false), or only the live prefix (true, the shipped state): the
## painter-perf-buried A/B in one run. Rewrites the tree rows' bound and the stroke instances.
func set_live_counts(on: bool) -> void:
	if on == _live_counts:
		return
	_live_counts = on
	for row in _rows.size():
		if int(_rows[row]["layer"]) >= 0:
			_write_row(row)
	_flush()
	_restroke()


## Makes the stroke levels' instances of every cell again (the slot counts changed, not the trees).
func _restroke() -> void:
	for bush in [false, true]:
		var store: Dictionary = bush_cells if bush else cells
		var per_slot := BUSH_SLOT_PER_INST if bush else PainterTreePack.SLOT_PER_INST
		for cell: Vector2i in store:
			var c: Dictionary = store[cell]
			var nodes: Array = c["nodes"]
			if nodes.size() < 5:
				continue
			var buf := PackedFloat32Array()
			for key: Vector3i in c["keys"]:
				var t: Dictionary = trees[key]
				var xf := Transform3D(Basis.IDENTITY, t["pos"])
				PainterTreePack.add_instances(buf, xf, t["row"], _slot_units(t["d"]), per_slot)
			for k in range(2, 5):
				if nodes[k] != null and is_instance_valid(nodes[k]):
					var mm: MultiMesh = (nodes[k] as MultiMeshInstance3D).multimesh
					mm.instance_count = buf.size() / 16
					if not buf.is_empty():
						mm.buffer = buf


## Rebuilds the nodes of `cell` in `store` (cells, or bush_cells when `bush`: smaller blocks, no
## limb ribbon, its slot left null).
func _rebuild_cell(store: Dictionary, cell: Vector2i, bush: bool) -> void:
	var c: Dictionary = store.get(cell, {})
	if c.is_empty():
		return
	for node: Node in c["nodes"]:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	c["nodes"] = []
	var keys: Dictionary = c["keys"]
	if keys.is_empty() or _root == null:
		store.erase(cell)
		return
	var per_ell := BUSH_ELL_PER_INST if bush else PainterTreePack.ELL_PER_INST
	var per_slot := BUSH_SLOT_PER_INST if bush else PainterTreePack.SLOT_PER_INST
	var bufs: Array[PackedFloat32Array] = [
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()
	]
	var box := AABB()
	var first := true
	for key: Vector3i in keys:
		var t: Dictionary = trees[key]
		var d: Dictionary = t["d"]
		var xf := Transform3D(Basis.IDENTITY, t["pos"])
		var row: int = t["row"]
		PainterTreePack.add_instances(bufs[0], xf, row, int(d["n_ell"]), per_ell)
		PainterTreePack.add_instances(bufs[1], xf, row, int(d["n_seg"]), PainterTreePack.SEG_PER_INST)
		PainterTreePack.add_instances(bufs[2], xf, row, _slot_units(d), per_slot)
		var b: AABB = d["aabb"]
		b.position += t["pos"]
		box = b if first else box.merge(b)
		first = false
	var meshes: Array[Mesh] = [
		PainterTreeMeshes.block(per_ell, bush),
		null if bush else PainterTreeMeshes.ribbon(),
		PainterTreeMeshes.strokes(0, per_slot),
		PainterTreeMeshes.strokes(1, per_slot),
		PainterTreeMeshes.strokes(2, per_slot)
	]
	var nodes: Array = []
	for k in meshes.size():
		if meshes[k] == null:
			nodes.append(null)
			continue
		var node := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[k]
		var buf: PackedFloat32Array = bufs[mini(k, 2)]
		mm.instance_count = buf.size() / 16
		if not buf.is_empty():
			mm.buffer = buf
		node.multimesh = mm
		node.material_override = _materials[k]
		node.custom_aabb = box.grow(BOUND_GROW)
		node.name = "%s_%d_%d_%d" % ["PainterBush" if bush else "PainterTree", cell.x, cell.y, k]
		node.set_meta(META, true)
		node.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if k < 2
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		if k >= 2:
			node.visible = level_shown(_lod_now(), k - 2)
		_root.add_child(node)
		nodes.append(node)
	c["nodes"] = nodes


# ---------------------------------------------------------------- stroke levels


## Whether stroke level `level` shows at `lod` (the spike's rule).
static func level_shown(lod: float, level: int) -> bool:
	return absf(clampf(lod, 0.0, 2.0) - float(level)) < 0.999


## The stroke level for an orthographic camera of `size` metres.
static func lod_for(size: float) -> float:
	return 1.0 - log(maxf(size, 0.01) / HOME_SIZE) / log(2.0)


func _lod_now() -> float:
	if _map == null or not _map.is_inside_tree():
		return 1.0
	var camera := _map.get_viewport().get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return 1.0
	return lod_for(camera.size)


func _watch() -> void:
	if _watching:
		return
	_watching = true
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _map == null:
		_watching = false
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_on_frame)
		return
	var lod := _lod_now()
	if is_equal_approx(lod, _lod):
		return
	_lod = lod
	for m in _materials:
		m.set_shader_parameter(&"lod_level", lod)
	for store: Dictionary in [cells, bush_cells]:
		for cell: Vector2i in store:
			var nodes: Array = store[cell]["nodes"]
			for k in range(2, nodes.size()):
				(nodes[k] as Node3D).visible = level_shown(lod, k - 2)
