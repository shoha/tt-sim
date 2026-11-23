extends GutTest
## The landing invariant under shuffled interleavings (card terraform-p2-sculpt round 3;
## docs/systems/terraform.md "The session"): whatever order river releases, Sculpt presses, held
## frames, undos and redos come in (card terraform-p2-paint-path: Paint presses, erase coats and
## path releases too), and however many frames pass between them, stepped or not, once
## everything has landed the session's settled derive answers for its document (every digest equals
## a fresh derive_full of it) and MapDocument.heights and surface planes are that fresh derive's.
## Seeds 1 and 8 caught
## the held add whose floats a later append grew in place (TerraSession.apply copies them now).

const SEEDS := [1, 8, 11, 23, 37, 58, 3, 14]
const STEPS := 9
## River lines on the corpus (map XZ), one per release in a run.
const RIVERS := [
	[Vector2(46, 11), Vector2(40, 10.5), Vector2(34, 11), Vector2(29, 12)],
	[Vector2(44, 30), Vector2(38, 31), Vector2(32, 30.5), Vector2(27, 31)],
]

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()


func _rig() -> TerraRig:
	TerraCore.switch_override = true
	var rig := await TerraRig.build(self)
	_rigs.append(rig)
	return rig


## `n` frames; with `step` the editor's height work steps each one, as AuthoringController does.
func _frames(rig: TerraRig, n: int, step: bool) -> void:
	for i in n:
		if step:
			rig.editor.step_height_work()
		await get_tree().process_frame


## A held Raise or Lower of `frames` frames from `a` to `b` (map XZ), each frame dabbing, flushing
## and stepping the height work, then the release.
func _press(rig: TerraRig, op: int, a: Vector2, b: Vector2, frames: int) -> void:
	var e := rig.editor
	if not e.begin_height_stroke(op, 0.0):
		return
	for k in frames:
		var p := a.lerp(b, float(k) / frames)
		var q := a.lerp(b, float(k + 1) / frames)
		var from := e.to_world(Vector3(p.x, 0, p.y))
		e.stroke_dab(from, e.to_world(Vector3(q.x, 0, q.y)), 3.0, 1.0 / 30.0)
		e.flush()
		e.step_height_work()
		await get_tree().process_frame
	e.end_stroke()


## River release `n` (RIVERS) through the editor's route.
func _release(rig: TerraRig, n: int) -> void:
	var line := PackedVector2Array()
	for p: Vector2 in RIVERS[n % RIVERS.size()]:
		line.append(rig.corpus.at(p.x, p.y))
	rig.editor.terra.carve_river(line, PackedFloat32Array([1.4]), 1)


## The invariant (see the header) on `rig`, once idle; `what` names the run.
func _check(rig: TerraRig, what: String) -> void:
	var fresh := TerraCache.derive_for(rig.doc.terra, rig.doc)
	var want := TerraCache.digests_of(fresh)
	var have := rig.session().digests()
	for key in want:
		assert_eq(have.get(key), want[key], "%s: settled %s = a fresh derive's" % [what, key])
	assert_true(
		fresh.call("doc_heights") == rig.doc.heights, "%s: heights = a fresh derive's" % what
	)
	var table := (rig.doc.terra as TerraDoc).surfaces
	assert_eq(rig.doc.surface_ids, table, "%s: surface_ids = the table" % what)
	if not table.is_empty():
		assert_true(
			fresh.call("doc_surfaces", Rect2i()) == rig.doc.surface_weights,
			"%s: surface planes = a fresh derive's" % what
		)


## A held Paint stroke (card terraform-p2-paint-path) of `frames` frames from `a` to `b` (map XZ):
## a coat of `surface`, or an erase coat for "".
func _paint(rig: TerraRig, surface: String, a: Vector2, b: Vector2, frames: int) -> void:
	var e := rig.editor
	if not e.begin_surface_stroke(surface, surface == ""):
		return
	for k in frames:
		var p := a.lerp(b, float(k) / frames)
		var q := a.lerp(b, float(k + 1) / frames)
		var from := e.to_world(Vector3(p.x, 0, p.y))
		e.stroke_dab(from, e.to_world(Vector3(q.x, 0, q.y)), 2.5, 1.0 / 30.0)
		e.flush()
		e.step_height_work()
		await get_tree().process_frame
	e.end_stroke()


## One shuffled run of STEPS actions drawn from seed `s`, then the invariant.
func _run(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var extra := RandomNumberGenerator.new()
	extra.seed = s * 31 + 7
	var rig := await _rig()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "seed %d: the load settles" % s)
	var rivers := 0
	var done := PackedStringArray()
	for i in STEPS:
		match rng.randi_range(0, 5):
			0, 1:
				if rivers < RIVERS.size():
					_release(rig, rivers)
					rivers += 1
					done.append("river")
			2, 3:
				var a := Vector2(rng.randf_range(12, 40), rng.randf_range(10, 34))
				var b := a + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
				var op := HeightBrush.RAISE if rng.randf() < 0.7 else HeightBrush.LOWER
				var frames := rng.randi_range(1, 8)
				await _press(rig, op, a, b, frames)
				done.append("press%d" % frames)
			4:
				if rig.history.can_undo():
					rig.history.undo()
					done.append("undo")
			5:
				if rig.history.can_redo():
					rig.history.redo()
					done.append("redo")
		# Paint presses and path releases (card terraform-p2-paint-path) from their own stream, so
		# the shuffles above stay the ones seeds 1 and 8 caught a bug with.
		match extra.randi_range(0, 4):
			0:
				var a := Vector2(extra.randf_range(12, 40), extra.randf_range(10, 34))
				var b := a + Vector2(extra.randf_range(-6, 6), extra.randf_range(-6, 6))
				var surface: String = ["gravel", "cobblestone", ""][extra.randi_range(0, 2)]
				var frames := extra.randi_range(1, 6)
				await _paint(rig, surface, a, b, frames)
				done.append("paint%d%s" % [frames, "e" if surface == "" else ""])
			1:
				var a := Vector2(extra.randf_range(12, 40), extra.randf_range(10, 34))
				var line := PackedVector2Array(
					[rig.corpus.at(a.x, a.y), rig.corpus.at(a.x + 8, a.y + extra.randf_range(-4, 4))]
				)
				rig.editor.terra.paint.add_path(line, 1.6, "dirt_road_packed")
				done.append("path")
		# Nothing, a frame or a few between gestures, stepped or not.
		var gap := rng.randi_range(0, 3)
		done.append("g%d" % gap)
		await _frames(rig, gap, rng.randf() < 0.6)
	assert_true(await TerraRig.settle(get_tree(), [rig]), "seed %d: idle" % s)
	_check(rig, "seed %d (%s)" % [s, ",".join(done)])
	rig.root.free()
	_rigs.erase(rig)


func test_shuffled_interleavings_land_on_their_document() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	for s: int in SEEDS:
		await _run(s)
