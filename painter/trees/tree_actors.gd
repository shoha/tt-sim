class_name PainterTreeActors
extends RefCounted
## What a terrain event does with a painted tree (card painter-fire; docs/systems/painter.md "Fire
## and events"): static functions over a PainterTrees host, split out of it to keep that file small.
##
## The model. A painted tree is a few instances in its cell's five MultiMeshInstance3D nodes, so an
## event cannot move or burn it in place without rebuilding the pack. take() lifts the one tree out:
## the cell is rebuilt without it (one cell, five small buffers) and the tree is drawn by its own
## five nodes under a pivot Node3D the event moves, which is how ForestFall topples a tree and
## FireSweep burns one. A burning actor draws with the burn variants of the tree shaders (an
## `instance uniform float burn`), so the cell's own materials never carry the burn code. The host
## remembers held keys: its sync() leaves them alone while an event plays and drop_all() settles
## them (a tree whose row left the scatter meanwhile is erased then, else it stands in its cell
## again).


## The actor for the tree at `position` or {} (see PainterTrees.take).
static func take(
	host: PainterTrees, position: Vector3, parent: Node3D, burning: bool
) -> Dictionary:
	var key := PainterTreeSpecies.key_of(position)
	if host._map == null or host._root == null or not host.trees.has(key) or host._held.has(key):
		return {}
	var t: Dictionary = host.trees[key]
	var set_of := host._materials
	if burning:
		if host._burn_materials.is_empty():
			make_burn_materials(host)
		set_of = host._burn_materials
	var pivot := Node3D.new()
	pivot.name = "PainterEventTree"
	pivot.position = t["pos"]
	var nodes := host._make_nodes([key], t["bush"], true, set_of, "PainterEvent")
	for node: Node in nodes:
		if node != null:
			pivot.add_child(node)
	var actor := {"key": key, "pivot": pivot, "nodes": nodes, "burning": burning}
	host._held[key] = actor
	parent.add_child(pivot)
	host._rebuild_cell(host.bush_cells if t["bush"] else host.cells, t["cell"], t["bush"])
	return actor


## Sets a burning actor's `burn` (see PainterTrees.set_burn).
static func set_burn(actor: Dictionary, value: float) -> void:
	if not actor.get("burning", false):
		return
	for node: Node in actor["nodes"]:
		if node != null and is_instance_valid(node):
			(node as GeometryInstance3D).set_instance_shader_parameter(&"burn", value)


## Lets every actor of `actors` go with one rebuild of the tables (see PainterTrees.drop_all).
static func drop_all(host: PainterTrees, actors: Array) -> void:
	var dirty := {}
	for actor: Dictionary in actors:
		var key: Vector3i = actor["key"]
		if not host._held.has(key):
			continue
		host._held.erase(key)
		var pivot: Node = actor["pivot"]
		if is_instance_valid(pivot):
			if pivot.get_parent() != null:
				pivot.get_parent().remove_child(pivot)
			pivot.queue_free()
		if not host.trees.has(key):
			continue
		var t: Dictionary = host.trees[key]
		if host._map != null and not host._want.has(key) and not host._pending.has(key):
			host._erase_tree(key, dirty)
		else:
			dirty[PainterTrees._dirty_key(t["cell"], t["bush"])] = true
	if not dirty.is_empty():
		host._rebuild(dirty)


## The host's burn material set: a copy of each of its five with the burn variant of the shader.
static func make_burn_materials(host: PainterTrees) -> void:
	for k in host._materials.size():
		var source := host._materials[k]
		var m := source.duplicate() as ShaderMaterial
		m.shader = load(PainterTrees.shader_path(k < 2, host._bare, true)) as Shader
		for meta: StringName in source.get_meta_list():
			m.set_meta(meta, source.get_meta(meta))
		host._burn_materials.append(m)
