extends SceneTree

## Packs the fire's baked drawing book (bake_fire_book.py's "TTFSIM02" .bin) into the shipped
## FireBook resource (tools/fire_sim/README.md has the whole procedure):
##
##   godot --headless --path D:/dev/tt-sim --script res://tools/fire_sim/pack_fire_book.gd
##       -- --in <folder>/fire_sim_book.bin [--out <path>]
##
## `--out` defaults to FireBook.PATH (res://assets/fire/fire_book.res). The .bin is little-endian:
## the magic, int32 tile width, tile height, sequences and drawings, per sequence an int32 width
## class and four float32 bounds (left, top, right, bottom in the tile's UV), then the RGBA8
## layers, rows top first, each sequence's drawings in turn and the tear layer last.
##
## The packer refuses a book that is not the one the flame shader is written for: another magic,
## a tile other than 96x128, more than 16 sequences, classes out of order or out of range, a size
## that does not match its header, or other than EXPECTED_LAYERS layers. It builds each layer's
## mips on the CPU here (Image.generate_mipmaps), so the runtime uploads them as they are, saves
## the book compressed, then reads the saved file back and checks every layer's bytes against
## what it wrote (Images saved from a headless run must survive the round trip). The last line
## prints the file's size and the load and texture-build times.

const FireBookScript := preload("res://resources/fire_book.gd")
const HEADER_BYTES := 24
const SEQUENCE_BYTES := 20
## The book the shader is written for: 8 sequences x 48 drawings and the tear layer. A re-bake
## that changes the sequences changes this and test_fire_book.gd together.
const EXPECTED_LAYERS := 385


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.input.is_empty():
		print("FB| usage: -- --in <fire_sim_book.bin> [--out <path>]")
		quit(1)
		return
	var built: Variant = _read_book(args.input)
	if built is String:
		print("FB| refused %s: %s" % [args.input, built])
		quit(1)
		return
	var book: FireBook = built
	var problem := book.problem()
	if not problem.is_empty():
		print("FB| refused %s: %s" % [args.input, problem])
		quit(1)
		return
	var failure := _save_and_check(book, args.output)
	if not failure.is_empty():
		print("FB| failed: %s" % failure)
		quit(1)
		return
	quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"input": "", "output": FireBook.PATH}
	var k := 0
	while k < args.size():
		var key := args[k]
		var value := args[k + 1] if k + 1 < args.size() else ""
		if key == "--in":
			out.input = value
			k += 1
		elif key == "--out":
			out.output = value
			k += 1
		k += 1
	return out


## The book read from the .bin at `path`, or a String saying why it was refused.
func _read_book(path: String) -> Variant:
	var data := FileAccess.get_file_as_bytes(path)
	if data.size() < HEADER_BYTES:
		return "missing or shorter than its header"
	var magic := data.slice(0, 8).get_string_from_ascii()
	if magic != FireBook.FORMAT:
		return "magic %s, expected %s" % [magic, FireBook.FORMAT]
	var tile := Vector2i(data.decode_s32(8), data.decode_s32(12))
	var sequences := data.decode_s32(16)
	var drawings := data.decode_s32(20)
	if tile != FireBook.TILE:
		return "tile %s, expected %s" % [tile, FireBook.TILE]
	if sequences < 1 or sequences > FireBook.MAX_SEQUENCES:
		return "%d sequences, expected 1 to %d" % [sequences, FireBook.MAX_SEQUENCES]
	if drawings < 1:
		return "%d drawings a sequence" % drawings
	var count := sequences * drawings + 1
	if count != EXPECTED_LAYERS:
		return "%d layers, expected %d" % [count, EXPECTED_LAYERS]
	var layer_bytes := tile.x * tile.y * 4
	var start := HEADER_BYTES + sequences * SEQUENCE_BYTES
	if data.size() != start + count * layer_bytes:
		return "%d bytes, its header says %d" % [data.size(), start + count * layer_bytes]
	var classes := PackedInt32Array()
	var bounds := PackedVector4Array()
	for k in sequences:
		var at := HEADER_BYTES + k * SEQUENCE_BYTES
		var klass := data.decode_s32(at)
		if klass < 0 or klass >= FireBook.CLASSES:
			return "sequence %d has class %d" % [k, klass]
		if k > 0 and klass < classes[k - 1]:
			return "the classes are not sorted (sequence %d)" % k
		classes.append(klass)
		bounds.append(
			Vector4(
				data.decode_float(at + 4),
				data.decode_float(at + 8),
				data.decode_float(at + 12),
				data.decode_float(at + 16)
			)
		)
	var t0 := Time.get_ticks_msec()
	var layers: Array[Image] = []
	for k in count:
		var at := start + k * layer_bytes
		var image := Image.create_from_data(
			tile.x, tile.y, false, Image.FORMAT_RGBA8, data.slice(at, at + layer_bytes)
		)
		image.generate_mipmaps()
		layers.append(image)
	print("FB| read %d layers and built their mips in %d ms" % [count, Time.get_ticks_msec() - t0])
	var book: FireBook = FireBookScript.new()
	book.format = magic
	book.source_sha256 = FileAccess.get_sha256(path)
	book.tile = tile
	book.drawings = drawings
	book.tear_layer = count - 1
	book.class_first = class_firsts(classes)
	book.seq_bounds = bounds
	book.layers = layers
	return book


## Each class's first sequence (x, y, z) and the sequence count (w) from the sorted classes; a
## class with no sequence borrows the next one's first.
static func class_firsts(classes: PackedInt32Array) -> Vector4i:
	var first := Vector4i(0, 0, 0, classes.size())
	for c in range(FireBook.CLASSES - 1, -1, -1):
		first[c] = first[c + 1]
		var found := classes.find(c)
		if found >= 0:
			first[c] = found
	return first


## Saves `book` to `path` compressed, reads it back and checks it; "" when it round-trips.
func _save_and_check(book: FireBook, path: String) -> String:
	var folder := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var t0 := Time.get_ticks_msec()
	var error := ResourceSaver.save(book, path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		return "saving %s: %s" % [path, error_string(error)]
	var save_ms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as FireBook
	var load_ms := Time.get_ticks_msec() - t0
	if back == null:
		return "%s did not load back as a FireBook" % path
	var problem := back.problem()
	if not problem.is_empty():
		return "%s read back broken: %s" % [path, problem]
	if back.source_sha256 != book.source_sha256 or back.class_first != book.class_first:
		return "%s read back with other fields" % path
	if back.seq_bounds != book.seq_bounds or back.drawings != book.drawings:
		return "%s read back with other bounds or drawings" % path
	for k in book.layers.size():
		if back.layers[k].get_data() != book.layers[k].get_data():
			return "%s layer %d read back with other bytes" % [path, k]
	t0 = Time.get_ticks_msec()
	var texture := back.create_texture()
	var texture_ms := Time.get_ticks_msec() - t0
	if texture == null or texture.get_layers() != book.layers.size():
		return "the read-back book did not build its texture"
	var size := FileAccess.get_file_as_bytes(path).size()
	print(
		(
			"FB| wrote %s: %d layers, class_first %s, %.2f MB (%d bytes), source sha256 %s; save %d"
			+ " ms, load %d ms, texture %d ms; every layer read back intact"
		)
		% [
			path,
			back.layers.size(),
			back.class_first,
			size / 1048576.0,
			size,
			back.source_sha256,
			save_ms,
			load_ms,
			texture_ms,
		]
	)
	return ""
