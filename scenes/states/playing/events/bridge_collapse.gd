class_name BridgeCollapse
extends Node3D

## A bridge collapsing (TerrainEvent.Kind.BRIDGE_COLLAPSE), played on one board. The crossing's
## own meshes are cut across the span into PIECE_M pieces (at most MAX_PIECES): each piece is
## a MeshInstance3D sharing the crossing's vertex arrays and materials with only its own
## triangles indexed, so it is the same planks, posts and stones, and the crossing's node is
## hidden behind them. The deck shudders, then breaks from the middle out: each piece tips
## toward the gap, drops under gravity, throws up a splash where it meets the water (dust on a
## dry bed) and sinks out of sight. Every peer plays it from the event alone (the seed varies
## the timing and the tumble), and the crossing removal the host makes once it has played
## (TerrainEvents) frees the hidden node; one that never comes shows it again (release()).
##
## Lives under the map root (the map frame, as AuthoredCrossings is), made by TerrainEvents.
## Cost: the cut is done once when the event starts (one pass over the crossing's triangles);
## each frame sets at most MAX_PIECES transforms and steps the puff pool.

const MAX_PIECES := 10
const PIECE_M := 1.4
## Seconds the deck shudders before it breaks, and over which the break runs from the middle
## to the banks.
const SHUDDER_S := 0.35
const BREAK_SPREAD_S := 0.55
const SHUDDER_DEG := 1.4
## Map metres a second squared.
const GRAVITY := 9.8
## How far a piece sinks below the water before it is gone, and how fast it sinks there.
const SINK_M := 1.0
const SINK_SPEED := 1.1
## Spray: cool white with the river's blue in it, a little see-through (pure white read as a
## cotton cut-out in the first look); the puff shader shades its underside pale blue. Foam:
## the ring it leaves lying on the water.
const SPLASH := Color(0.88, 0.96, 1.0, 0.85)
const FOAM := Color(0.92, 0.98, 1.0, 0.75)
const DUST := Color(0.95, 0.8, 0.56, 0.5)
## Drops are thrown up and fall back to the water (rising puffs alone read as steam).
const SPRAY_GRAVITY := 9.0
## A splash, a few bold shapes sized to the piece that makes it (SPLASH_M, metres): a crown, a
## column of water shooting up where it fell and falling back; TONGUES leaning out round it;
## DROPS flung out on arcs; and a ring of foam spreading on the water and lingering. Eight
## tongues of spray a fifth of a plank wide read as confetti at tabletop zoom (the round 3
## verdict). A splash takes 1 + TONGUES + DROPS + 1 puffs: MAX_PIECES of them fit the pool.
const SPLASH_M := Vector2(1.1, 1.8)
const TONGUES := 3
const DROPS := 3
## How far above the water the foam ring lies (clear of the surface's bob).
const FOAM_LIFT := 0.04

## The crossing it takes down, and its node (hidden while this plays).
var crossing_id: int = -1
var duration: float = 2.0
var _crossing: Crossing = null
var _node: Node3D = null
## Per piece: {"mesh": MeshInstance3D, "pivot": Vector3, "release": s, "tip": Vector3 axis,
## "spin": Vector3 axis, "tip_rate", "spin_rate", "drift": Vector3, "landed": bool}
var _pieces: Array[Dictionary] = []
var _water_y: float = 0.0
var _wet: bool = true
var _puffs: EventPuffs = null
var _rng := RandomNumberGenerator.new()


## Prepares the collapse of the crossing `event` names on `editor`'s map; false when it is not
## there or not a bridge (nothing is hidden then).
func setup(editor: AuthoringEditor, event: TerrainEvent) -> bool:
	name = "BridgeCollapse_%d" % event.crossing_id
	crossing_id = event.crossing_id
	duration = event.duration_s
	_crossing = editor.document.crossing(event.crossing_id)
	if _crossing == null or not _crossing.is_deck():
		return false
	_rng.seed = event.seed_value
	var middle := (_crossing.start + _crossing.end) * 0.5
	var level := WaterGeometry.level_at(editor.document, middle)
	_wet = level != WaterGeometry.DRY
	_water_y = level if _wet else WaterGeometry.ground_at(editor.document, middle)
	_puffs = EventPuffs.new()
	add_child(_puffs)
	var crossings := editor.map_root.get_node_or_null(NodePath(AuthoredCrossings.NODE_NAME))
	if crossings != null:
		_node = (crossings as AuthoredCrossings).get_crossing_node(crossing_id)
	if _node != null:
		_cut(_node)
		_node.visible = false
	return true


## Plays the collapse `elapsed` seconds in (after `delta` more seconds of puffs).
func step(elapsed: float, delta: float) -> void:
	for piece in _pieces:
		var mesh: MeshInstance3D = piece.mesh
		if not mesh.visible:
			continue
		mesh.transform = _piece_transform(piece, elapsed)
	_puffs.step(delta)


## True once the collapse has played and its puffs have faded.
func is_played(elapsed: float) -> bool:
	return elapsed >= duration and _puffs.is_idle()


## Whether the crossing's node is gone (the removal landed).
func is_removed() -> bool:
	return not is_instance_valid(_node)


## Shows the crossing again if it is still standing (its removal never came, or was undone
## before it was made).
func release() -> void:
	if is_instance_valid(_node):
		_node.visible = true


## A piece `elapsed` seconds into the collapse: rest, a shudder, then the tip and the fall; a
## splash as it meets the water, then it sinks and shrinks away.
func _piece_transform(piece: Dictionary, elapsed: float) -> Transform3D:
	var pivot: Vector3 = piece.pivot
	var release_s: float = piece.release
	var rotation := Basis()
	var offset := Vector3.ZERO
	if elapsed < release_s:
		var shake := deg_to_rad(SHUDDER_DEG) * minf(elapsed / SHUDDER_S, 1.0)
		rotation = Basis(piece.spin, shake * sin(elapsed * 38.0 + float(piece.phase)))
	else:
		var t := elapsed - release_s
		var drop := 0.5 * GRAVITY * t * t
		var fall_s: float = piece.fall_s
		if t > fall_s:
			# Under water: the fall slows to a sink.
			var under := t - fall_s
			drop = 0.5 * GRAVITY * fall_s * fall_s + minf(under * SINK_SPEED, SINK_M + 0.5)
			if not piece.landed:
				piece.landed = true
				_splash(pivot + Vector3(0.0, -0.5 * GRAVITY * fall_s * fall_s, 0.0), piece)
		offset = Vector3(0.0, -drop, 0.0) + (piece.drift as Vector3) * t
		var tip := float(piece.tip_rate) * t + 0.5 * float(piece.tip_rate) * 2.5 * t * t
		var spin := float(piece.spin_rate) * t
		rotation = Basis(piece.tip, minf(tip, PI * 0.6)) * Basis(piece.spin, spin)
	var scale := 1.0
	var gone_at := duration - 0.3
	if elapsed > gone_at:
		scale = maxf(1.0 - (elapsed - gone_at) / 0.3, 0.0)
	var basis := rotation.scaled(Vector3.ONE * scale)
	# Rotate and scale about the pivot, then move.
	return Transform3D(basis, pivot + offset - basis * pivot)


func _splash(at: Vector3, piece: Dictionary) -> void:
	var at_water := Vector3(at.x, _water_y, at.z)
	var size := clampf(maxf(float(piece.width), PIECE_M), SPLASH_M.x, SPLASH_M.y)
	if not _wet:
		# A dry bed: dust rolling out low from where the piece lands.
		for k in 4:
			var angle := TAU * (float(k) + _rng.randf_range(0.0, 0.6)) / 4.0
			var side := Vector3(cos(angle), 0.0, sin(angle))
			_puffs.emit(
				at_water + side * 0.2 + Vector3(0.0, 0.1, 0.0),
				side * _rng.randf_range(0.8, 1.2) + Vector3(0.0, _rng.randf_range(0.2, 0.4), 0.0),
				size * _rng.randf_range(0.6, 0.8),
				_rng.randf_range(1.0, 1.3),
				DUST,
				0.0,
				EventPuffs.SQUAT
			)
		return
	# The crown: a column of water shooting up where the piece went in, falling back.
	_puffs.emit_plume(
		at_water, size * 0.5, size * _rng.randf_range(1.15, 1.35), _rng.randf_range(1.0, 1.15), SPLASH
	)
	# Tongues leaning out round it, a little lower and quicker.
	var turn := _rng.randf_range(0.0, TAU)
	for k in TONGUES:
		var angle := turn + TAU * (float(k) + _rng.randf_range(-0.15, 0.15)) / float(TONGUES)
		var side := Vector3(cos(angle), 0.0, sin(angle))
		var lean := deg_to_rad(_rng.randf_range(28.0, 42.0))
		_puffs.emit_plume(
			at_water + side * size * 0.15,
			size * 0.32,
			size * _rng.randf_range(0.7, 0.9),
			_rng.randf_range(0.8, 0.95),
			SPLASH,
			Vector3.UP * cos(lean) + side * sin(lean)
		)
	# Drops flung out from the crown on arcs, back into the water.
	for k in DROPS:
		var angle := turn + TAU * (float(k) + 0.5 + _rng.randf_range(-0.2, 0.2)) / float(DROPS)
		var side := Vector3(cos(angle), 0.0, sin(angle))
		_puffs.emit(
			at_water + Vector3(0.0, size * 0.2, 0.0),
			side * _rng.randf_range(1.3, 1.9) + Vector3(0.0, _rng.randf_range(3.6, 4.4), 0.0),
			size * _rng.randf_range(0.28, 0.34),
			1.1,
			SPLASH,
			SPRAY_GRAVITY,
			1.3
		)
	# Foam: a ring spreading on the water where it fell, lingering once the spray is down.
	_puffs.emit_ring(
		at_water + Vector3(0.0, FOAM_LIFT, 0.0), size * 2.0, _rng.randf_range(1.4, 1.6), FOAM
	)


## Cuts the crossing node's meshes across the span into pieces (see the header).
func _cut(node: Node3D) -> void:
	var span := _crossing.span_m()
	var count := clampi(ceili(span / PIECE_M), 2, MAX_PIECES)
	# Per piece, per source surface: the triangle indices that fall in it.
	var parts: Array[Dictionary] = []
	for i in count:
		parts.append({})
	var sources: Array = []
	for child in node.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var source := sources.size()
			sources.append([arrays, instance.mesh.surface_get_material(surface)])
			_split(arrays, span, count, parts, source)
	var across := Vector3(-_crossing.direction().y, 0.0, _crossing.direction().x)
	var along := Vector3(_crossing.direction().x, 0.0, _crossing.direction().y)
	for i in count:
		var part: Dictionary = parts[i]
		if part.is_empty():
			continue
		var mesh := ArrayMesh.new()
		var low := Vector3.INF
		var high := -Vector3.INF
		for source: int in part:
			var indices := PackedInt32Array(part[source])
			var arrays: Array = (sources[source][0] as Array).duplicate()
			arrays[Mesh.ARRAY_INDEX] = indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, sources[source][1])
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in indices:
				low = low.min(vertices[index])
				high = high.max(vertices[index])
		var instance := MeshInstance3D.new()
		instance.name = "Piece%d" % i
		instance.mesh = mesh
		add_child(instance)
		var pivot := (low + high) * 0.5
		var from_middle := (float(i) + 0.5) / count - 0.5
		var toward_gap := -signf(from_middle) if absf(from_middle) > 0.01 else 1.0
		var top := pivot.y - _water_y
		_pieces.append(
			{
				"mesh": instance,
				"pivot": pivot,
				"width": maxf(_crossing.width_m, high.y - low.y),
				"release":
				SHUDDER_S + BREAK_SPREAD_S * absf(from_middle) * 2.0 + _rng.randf_range(0.0, 0.12),
				"fall_s": sqrt(2.0 * maxf(top, 0.2) / GRAVITY),
				# Tips about the axis across the span, its gap side down; rolls a little.
				"tip": across * toward_gap,
				"tip_rate": _rng.randf_range(0.8, 1.6),
				"spin": along,
				"spin_rate": _rng.randf_range(-0.9, 0.9),
				"drift": across * _rng.randf_range(-0.35, 0.35),
				"phase": _rng.randf_range(0.0, TAU),
				"landed": false,
			}
		)


## Adds each triangle of `arrays` (map frame) to the piece its centroid falls in along the
## span, under key `source` of that piece's dictionary.
func _split(arrays: Array, span: float, count: int, parts: Array[Dictionary], source: int) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	else:
		indices.resize(vertices.size())
		for k in vertices.size():
			indices[k] = k
	for t in range(0, indices.size() - 2, 3):
		var centre := (vertices[indices[t]] + vertices[indices[t + 1]] + vertices[indices[t + 2]]) / 3.0
		var u := CrossingGeometry.local_of(_crossing, Vector2(centre.x, centre.z)).x
		var piece := clampi(floori(u / span * count), 0, count - 1)
		var part: Dictionary = parts[piece]
		if not part.has(source):
			part[source] = []
		(part[source] as Array).append_array([indices[t], indices[t + 1], indices[t + 2]])
