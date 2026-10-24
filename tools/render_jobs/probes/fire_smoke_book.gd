extends RefCounted

## Render-job probe (`call` op) that bakes the persistent fire's smoke book once, offline (card
## fire-prod-c5a; job fire_smoke_book, tools/fire_sim/README.md): BAKE is drawn into one
## SubViewport atlas of GRID tiles (FireSmokeBook.SEEDS x FRAMES) in the real window, since the
## bake needs the GPU and a headless run draws nothing, then read back, sliced into the book's
## layers and saved as FireSmokeBook.PATH. The steps are round 6's runtime bake (spike-flipbook
## de7f3d16, FireFlipbook._bake and _build_smoke): the same atlas, uniforms, viewport settings
## and readback after the frame that draws it, so the saved frames are the ones the spike baked
## at load. Actions:
##   bake {save, reference}  sets the atlas up to draw on the next frame and returns; the
##                     readback runs after that frame (wait a second or two, then `report`).
##                     `save` (default true) writes the book with ResourceSaver.FLAG_COMPRESS
##                     and reloads it from disk to check that it round-trips. `reference` (a
##                     shader's path: the spike's own bake shader, for the reproduction check; a
##                     scratch job passes it, no absolute path is committed) is baked the same
##                     way in a second atlas and compared with the book layer by layer
##   report            the last bake's result: the book's problem() ("whole" when none), the
##                     reference comparison (bytes that differ, the largest difference in
##                     levels), the saved file's size and the round trip

const BAKE := "res://tools/fire_sim/fire_smoke_book_bake.gdshader"
## The atlas's tiles (columns, rows): every seed's frames in turn, row by row.
const GRID := Vector2i(8, 6)

static var _result := "no bake yet"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	match action:
		"bake":
			return _bake(base, step)
		"report":
			return _result
	return "unknown action %s" % action


static func _bake(base: Node, step: Dictionary) -> String:
	if GRID.x * GRID.y != FireSmokeBook.SEEDS * FireSmokeBook.FRAMES:
		return "the grid %s does not hold %d frames" % [GRID, FireSmokeBook.SEEDS * FireSmokeBook.FRAMES]
	var shaders: Array[Shader] = [load(BAKE) as Shader]
	var reference_path := String(step.get("reference", ""))
	if reference_path != "":
		var code := FileAccess.get_file_as_string(reference_path)
		if code == "":
			return "no reference shader at %s" % reference_path
		var shader := Shader.new()
		shader.code = code
		shaders.append(shader)
	var atlases: Array[SubViewport] = []
	for k in shaders.size():
		atlases.append(_atlas(base, shaders[k], "SmokeBookBake%d" % k))
	var save := bool(step.get("save", true))
	_result = "baking"
	RenderingServer.frame_post_draw.connect(func() -> void: _read(atlases, save), CONNECT_ONE_SHOT)
	return "baking %d atlas(es) of %s texels" % [atlases.size(), GRID * FireSmokeBook.TILE]


## A one-shot atlas drawing `shader` over its whole rect with the book's uniforms (round 6's
## SmokeBake viewport).
static func _atlas(base: Node, shader: Shader, label: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = GRID * FireSmokeBook.TILE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	base.add_child(viewport)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("grid", GRID)
	mat.set_shader_parameter("frames", FireSmokeBook.FRAMES)
	mat.set_shader_parameter("rise", FireFieldSmoke.RISE)
	mat.set_shader_parameter("width", FireFieldSmoke.WIDTH)
	mat.set_shader_parameter("domain", FireSmokeBook.DOMAIN)
	var fill := ColorRect.new()
	fill.material = mat
	fill.position = Vector2.ZERO
	fill.size = Vector2(viewport.size)
	viewport.add_child(fill)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return viewport


## After the frame that drew the atlases: slices each into a book, compares the reference's with
## the book's, saves the book and checks the saved file.
static func _read(atlases: Array[SubViewport], save: bool) -> void:
	var books: Array[FireSmokeBook] = []
	for atlas in atlases:
		books.append(slice(atlas.get_texture().get_image()))
		atlas.queue_free()
	var book := books[0]
	var problem := book.problem()
	var lines := PackedStringArray(["book %s" % ("whole" if problem == "" else problem)])
	if books.size() > 1:
		lines.append("against the reference: %s" % compare(book, books[1]))
	if save and problem == "":
		lines.append(_save(book))
	_result = "; ".join(lines)
	print("fire_smoke_book: ", _result)


## The book of a baked atlas (GRID tiles of FireSmokeBook.TILE): seed k's frame f is tile
## k * FRAMES + f, row by row.
static func slice(atlas: Image) -> FireSmokeBook:
	var book := FireSmokeBook.new()
	book.tile = FireSmokeBook.TILE
	book.seeds = FireSmokeBook.SEEDS
	book.frames = FireSmokeBook.FRAMES
	book.domain = FireSmokeBook.DOMAIN
	book.rise = FireFieldSmoke.RISE
	book.width = FireFieldSmoke.WIDTH
	var layers: Array[Image] = []
	for k in book.seeds * book.frames:
		@warning_ignore("integer_division")
		var corner := Vector2i(k % GRID.x, k / GRID.x) * book.tile
		layers.append(atlas.get_region(Rect2i(corner, book.tile)))
	book.layers = layers
	return book


## How two books' layers differ: the bytes that differ and the largest difference in levels.
static func compare(a: FireSmokeBook, b: FireSmokeBook) -> String:
	if a.layers.size() != b.layers.size():
		return "%d layers against %d" % [a.layers.size(), b.layers.size()]
	var differ := 0
	var largest := 0
	var total := 0
	for k in a.layers.size():
		var x := a.layers[k].get_data()
		var y := b.layers[k].get_data()
		if x.size() != y.size() or a.layers[k].get_format() != b.layers[k].get_format():
			return "layer %d's size or format differs" % k
		total += x.size()
		if x == y:
			continue
		for i in x.size():
			var d := absi(x[i] - y[i])
			if d > 0:
				differ += 1
				largest = maxi(largest, d)
	return "%d of %d bytes differ, the largest by %d levels" % [differ, total, largest]


static func _save(book: FireSmokeBook) -> String:
	var error := ResourceSaver.save(book, FireSmokeBook.PATH, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		return "save FAILED (%s)" % error_string(error)
	var bytes := FileAccess.get_file_as_bytes(FireSmokeBook.PATH).size()
	var back := (
		ResourceLoader.load(FireSmokeBook.PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as FireSmokeBook
	)
	var trip := "the reload FAILED" if back == null else "reloaded: %s" % compare(book, back)
	return "saved %s, %d bytes; %s" % [FireSmokeBook.PATH, bytes, trip]
