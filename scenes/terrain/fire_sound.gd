class_name FireSound
extends Node3D

## The persistent fire's sound (FireField; design: docs/plans/2026-10-11-fire-features/design.md
## section 4 "Sound", cards F7, F7b and F7c): the roar loop (tools/sfx_spec.py RECORDINGS
## "fire_roar", a CC0 recording of a large fire processed into a seamless loop, which AudioManager
## does not play itself) on at most MAX_PLAYERS AudioStreamPlayer3D on the manifest entry's bus,
## SFX, so the Settings SFX volume governs it. Each player voices one of the strongest fire
## clusters near what the camera sees.
##
## Placement reuses the clusters FireField finds for its lights (FireClusters.find on each
## refresh, handed over by place() with FireClusters.spots), and the players are re-picked (pick,
## pure) only when the fire changes or the camera's view moves or zooms by REPICK_SHARE of its
## height, never per frame. A cluster is an area, not a point: its flames are the burning cells
## that belong to it (spots, every burning cell in exactly one cluster, also a long burn's cells
## outside every cluster's own nine), each reaching SPOT_REACH_M. It counts by how near those
## flames come to the camera's axis, for the orthographic game camera to the screen's middle:
## whole within FULL_SHARE of the view's height, fading out by REACH_SHARE, just past the
## screen's sides, with FULL_MIN_M and REACH_MIN_M under both once zoomed in (card F7c: at zoom 2
## a fire 3 m from its cluster's centroid fell silent while it filled the view). Its player stands
## at the flames' point nearest the screen's middle, so a fire around the view sounds centred and
## one to the right is heard right, alike at every zoom. Its loudness (gain_for) follows its size
## (square metres of flame, as the lights' energy does) on a square-root curve, full at
## FULL_SIZE_M2.
##
## Each player fades toward its cluster's loudness at FADE_PER_S (about a second from silence to
## full), so fire appearing, being put out or leaving the view eases in and out; a player whose
## cluster changes fades out, moves and fades in. The players exist only while flames do: made
## with the first cluster, freed once no cluster is left and they have faded to silence.
##
## Distance does not attenuate the players (the camera hangs far above the table at every zoom;
## the level is the view's fire, as above): their place only pans them, through the world
## viewport's listener, its camera (game_map.tscn enables the SubViewport's 3D listener). Each
## starts at a random point of the loop (it is nearly a minute long), the two at either end of
## half the entry's pitch jitter, so the pair never phases into one comb-filtered voice.

const NODE_NAME := "FireSound"
const SOUND := &"fire_roar"
const MAX_PLAYERS := 2
## A cluster of this many square metres of flame (FireClusters' size) plays at full.
const FULL_SIZE_M2 := 12.0
## Shares of the view's height (the orthographic camera's size): a cluster whose flames come this
## near the camera's axis plays whole, and one whose flames stay this far is silent (the screen's
## sides are at about 0.9).
const FULL_SHARE := 0.5
const REACH_SHARE := 1.0
## The same in metres, the floor under either share once zoomed in, so a fire just off a close
## view's sides still sounds (at the closest zoom, 2, the view is 2 m high and 3.6 m wide).
const FULL_MIN_M := 2.0
const REACH_MIN_M := 5.0
## How far a spot's flames reach around it (metres): a cell's flames stand within about half its
## diagonal of their centroid, so neighbouring cells' reaches overlap and a view over any flame
## is over some cluster's flames.
const SPOT_REACH_M := 0.75 * FireClusters.CELL_M
## Linear gain per second a player fades by.
const FADE_PER_S := 1.0
## The view re-picks the players once it moves or zooms by this share of its height.
const REPICK_SHARE := 0.15
## How far a player's place pans it (AudioStreamPlayer3D.panning_strength).
const PANNING := 0.5
## Below this gain a player is stopped.
const SILENT := 0.001
## An empty slot's cell.
const NONE := Vector2i(2147483647, 2147483647)

## The burning clusters (FireClusters.find), largest first, in this node's frame, each with its
## "spots" (place).
var _clusters: Array[Dictionary] = []
var _players: Array[AudioStreamPlayer3D] = []
## Per slot: its cluster's cell (NONE: none), its gain now and the gain it fades toward, the
## cluster it moves to once faded out (empty: none), and whether it was started (play() lands
## on the mixing thread a little later, so `playing` lags it).
var _cells: Array[Vector2i] = []
var _gain := PackedFloat32Array()
var _target := PackedFloat32Array()
var _next: Array[Dictionary] = []
var _started: Array[bool] = []
## The manifest entry's gain (dB), under every player's own.
var _base_db := 0.0
## The view the players were last picked for: the camera's place, axis and size.
var _view_eye := Vector3.INF
var _view_size := 0.0


func _init() -> void:
	name = NODE_NAME
	set_process(false)


func _process(delta: float) -> void:
	var view := _view()
	if _view_moved(view):
		_repick(view)
	advance(delta)


## Takes the burning clusters of a refresh (FireClusters.find: largest first, document metres,
## this node's frame) and where each one's flames stand (FireClusters.spots; a cluster missing
## from it counts as its centroid alone) and re-picks the players for the current view.
func place(found: Array[Dictionary], spots: Dictionary = {}) -> void:
	_clusters = []
	for cluster in found:
		var heard := cluster.duplicate()
		heard["spots"] = spots.get(cluster["cell"], PackedVector3Array([cluster["at"]]))
		_clusters.append(heard)
	_repick(_view())
	set_process(not _players.is_empty())


## Moves every player's gain `delta` seconds toward its target, moves a faded-out player to its
## next cluster, starts and stops the players, and frees them once no fire is left and all are
## silent. _process calls it each frame; tests call it directly.
func advance(delta: float) -> void:
	var loud := false
	for slot in _players.size():
		_gain[slot] = move_toward(_gain[slot], _target[slot], FADE_PER_S * delta)
		if _gain[slot] <= 0.0 and not _next[slot].is_empty():
			_players[slot].position = _next[slot]["at"]
			_target[slot] = float(_next[slot]["gain"])
			_next[slot] = {}
		_sound(slot)
		loud = loud or _gain[slot] > 0.0 or _target[slot] > 0.0
	if not loud and _clusters.is_empty():
		_free_players()
		set_process(false)


## The players (empty while no fire burns), for probes and tests.
func players() -> Array[AudioStreamPlayer3D]:
	return _players


## Each player's gain now (0..1, before the entry's volume_db), for probes and tests.
func gains() -> PackedFloat32Array:
	return _gain


## The gain each player fades toward, for probes and tests.
func targets() -> PackedFloat32Array:
	return _target


## The burning clusters place() last took (largest first, this node's frame, each with its
## "spots"), for probes and tests.
func clusters() -> Array[Dictionary]:
	return _clusters


## The clusters the players stand at for a camera at `eye` looking along `axis` (unit) with a
## view `view_m` high (INF: no camera, every cluster in view): up to MAX_PLAYERS of `candidates`
## with a gain above 0, loudest first (ties in the given order), each {"cell", "at", "gain"}.
## A cluster's flames are its "spots" (place's; without them its centroid "at"), each reaching
## SPOT_REACH_M around it; the cluster is heard by how near its flames come to the camera's axis
## and stands at their point nearest the axis (near), so a fire around the view's middle sounds
## centred at every zoom. Without a view it stands at its centroid. Pure.
static func pick(
	candidates: Array[Dictionary], eye: Vector3, axis: Vector3, view_m: float
) -> Array[Dictionary]:
	var heard: Array[Dictionary] = []
	var full := maxf(FULL_SHARE * view_m, FULL_MIN_M)
	var reach := maxf(REACH_SHARE * view_m, REACH_MIN_M)
	for cluster in candidates:
		var at: Vector3 = cluster["at"]
		var shown := 1.0
		if is_finite(view_m):
			var spots: PackedVector3Array = cluster.get("spots", PackedVector3Array([at]))
			var nearest := near(spots, eye, axis)
			at = nearest[0]
			shown = 1.0 - smoothstep(full, reach, float(nearest[1]))
		var gain := gain_for(float(cluster["size"])) * shown
		if gain > 0.0:
			heard.append({"cell": cluster["cell"], "at": at, "gain": gain})
	# A stable sort: Array.sort_custom is not, so the input order breaks ties.
	var order: Array = range(heard.size())
	order.sort_custom(
		func(a: int, b: int) -> bool:
			if heard[a]["gain"] != heard[b]["gain"]:
				return heard[a]["gain"] > heard[b]["gain"]
			return a < b
	)
	var out: Array[Dictionary] = []
	for k in mini(MAX_PLAYERS, order.size()):
		out.append(heard[order[k]])
	return out


## The point of the flames at `spots` nearest the camera's axis (from `eye` along unit `axis`)
## and its distance from the axis: [Vector3, float]. Each spot reaches SPOT_REACH_M around it,
## across the axis, so the point is a spot moved toward the axis by up to that, and the distance
## is 0 for an axis through a spot's reach. Pure.
static func near(spots: PackedVector3Array, eye: Vector3, axis: Vector3) -> Array:
	var best := Vector3.INF
	var nearest := INF
	for spot in spots:
		var off := spot - eye
		var aside := off - axis * off.dot(axis)
		var length := aside.length()
		if length < nearest:
			nearest = length
			best = spot - aside * (minf(length, SPOT_REACH_M) / maxf(length, 1e-6))
	return [best, maxf(nearest - SPOT_REACH_M, 0.0)]


## A cluster's loudness (0..1) for its size in square metres of flame. Pure.
static func gain_for(size_m2: float) -> float:
	return sqrt(clampf(size_m2 / FULL_SIZE_M2, 0.0, 1.0))


## The camera's view in this node's frame: [eye, axis, size], or empty without a camera (or out
## of the tree). The size is taken into the frame too (camera.size is in world units; a level's
## map_scale scales the map and this node with it). A perspective camera counts as no view
## (every cluster heard).
func _view() -> Array:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return []
	var into_local := global_transform.affine_inverse()
	var forward := into_local.basis * -camera.global_basis.z
	var size := INF
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		size = camera.size * forward.length()
	return [into_local * camera.global_position, forward.normalized(), size]


## Whether `view` moved or zoomed by REPICK_SHARE of its height since the last pick.
func _view_moved(view: Array) -> bool:
	if view.is_empty() or _players.is_empty():
		return false
	var size: float = view[2]
	if not is_finite(size) or not is_finite(_view_size):
		return size != _view_size
	var eye: Vector3 = view[0]
	var step := REPICK_SHARE * size
	return eye.distance_to(_view_eye) > step or absf(size - _view_size) > step


## Picks the players' clusters for `view` (_view) and points each slot at its own: a slot keeps
## its cluster when it is still picked (FireClusters.keep_slots), a new one fades out and moves.
func _repick(view: Array) -> void:
	var eye: Vector3 = Vector3.ZERO if view.is_empty() else view[0]
	var axis: Vector3 = Vector3.DOWN if view.is_empty() else view[1]
	var size: float = INF if view.is_empty() else view[2]
	_view_eye = eye
	_view_size = size
	var picked := pick(_clusters, eye, axis, size)
	if not picked.is_empty():
		_make_players()
	var wanted: Array[Vector2i] = []
	for cluster in picked:
		wanted.append(cluster["cell"])
	var slots := FireClusters.keep_slots(_cells, wanted)
	for slot in _players.size():
		var k := slots[slot]
		var moving := not _next[slot].is_empty()
		_next[slot] = {}
		if k < 0:
			_cells[slot] = NONE
			_target[slot] = 0.0
			continue
		var cluster := picked[k]
		if (_cells[slot] == cluster["cell"] and not moving) or _gain[slot] <= 0.0:
			_players[slot].position = cluster["at"]
			_target[slot] = float(cluster["gain"])
		else:
			_target[slot] = 0.0
			_next[slot] = cluster
		_cells[slot] = cluster["cell"]


## Makes the players (once; none while the manifest has no file for the sound).
func _make_players() -> void:
	if not _players.is_empty():
		return
	var stream := AudioManager.loop_stream(SOUND)
	if stream == null:
		return
	var entry := AudioManager.sound_entry(SOUND)
	var jitter := float(entry.get("pitch_jitter", 0.0))
	_base_db = float(entry.get("volume_db", 0.0))
	for slot in MAX_PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.name = "Voice%d" % slot
		player.stream = stream
		player.bus = str(entry.get("bus", AudioManager.BUS_SFX))
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = 0.0
		player.panning_strength = PANNING
		var unit := -0.5 if slot == 0 else 0.5
		player.pitch_scale = SoundRequestQueue.jittered_pitch(1.0, jitter, unit)
		add_child(player)
		_players.append(player)
		_cells.append(NONE)
		_gain.append(0.0)
		_target.append(0.0)
		_next.append({})
		_started.append(false)


## Sets one player's level from its gain and starts or stops it.
func _sound(slot: int) -> void:
	var player := _players[slot]
	player.volume_db = _base_db + linear_to_db(maxf(_gain[slot], SILENT))
	var on := _gain[slot] >= SILENT
	if on and not _started[slot] and player.is_inside_tree():
		player.play(randf() * player.stream.get_length())
		_started[slot] = true
	elif not on and _started[slot]:
		player.stop()
		_started[slot] = false


func _free_players() -> void:
	for player in _players:
		player.free()
	_players.clear()
	_cells.clear()
	_gain.clear()
	_target.clear()
	_next.clear()
	_started.clear()
