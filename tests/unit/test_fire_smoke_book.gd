extends GutTest

## FireSmokeBook (the persistent fire's shipped smoke book, res://assets/fire/fire_smoke_book.res;
## card fire-prod-c5a): the file is in the checkout and is the book, not a Git LFS pointer (a
## clone without `git lfs pull` fails here loudly); it holds 2 seeds of 24 RGBA8 128x160 frames,
## 48 layers, baked at the column's own rise and width over the draw's domain; each seed's loop
## closes (its last frame runs into its first as any frame runs into the next); the GPU array
## builds from it and dropping it frees it; and FireFieldSmoke binds it and lets it go, the
## columns drawing nothing while it is not bound.

const MISSING := "fire smoke book missing or an LFS pointer: run git lfs pull"

var _book: FireSmokeBook = null


func before_all() -> void:
	FireFieldSmoke.release_book()
	if ResourceLoader.exists(FireSmokeBook.PATH) and not FireBook.is_lfs_pointer(FireSmokeBook.PATH):
		_book = ResourceLoader.load(FireSmokeBook.PATH) as FireSmokeBook


func after_all() -> void:
	_book = null
	FireFieldSmoke.release_book()


func test_the_book_is_checked_out_not_a_pointer() -> void:
	assert_true(FileAccess.file_exists(FireSmokeBook.PATH), MISSING)
	assert_false(FireBook.is_lfs_pointer(FireSmokeBook.PATH), MISSING)
	var size := FileAccess.get_file_as_bytes(FireSmokeBook.PATH).size()
	assert_gt(size, 1 << 20, "the book is megabytes, not a pointer's few lines")
	assert_not_null(_book, MISSING)


func test_48_rgba8_frames_baked_for_the_column() -> void:
	if _book == null:
		fail_test(MISSING)
		return
	assert_eq(_book.problem(), "", "the book validates")
	assert_eq(_book.format, "TTSMOKE1")
	assert_eq(_book.tile, Vector2i(128, 160))
	assert_eq(_book.seeds, 2)
	assert_eq(_book.frames, 24)
	assert_eq(_book.layers.size(), 48)
	assert_eq(_book.layer_of(1, 24), 24, "a frame wraps round its loop")
	assert_eq(_book.domain, FireSmokeBook.DOMAIN, "the draw's frame is the bake's")
	assert_eq(_book.rise, FireFieldSmoke.RISE, "baked at the column's rise")
	assert_eq(_book.width, FireFieldSmoke.WIDTH, "and its width")
	var bad := 0
	for image in _book.layers:
		var whole := (
			image != null
			and image.get_size() == Vector2i(128, 160)
			and image.get_format() == Image.FORMAT_RGBA8
		)
		if not whole:
			bad += 1
	assert_eq(bad, 0, "every layer is a 128x160 RGBA8 Image")


func test_each_seeds_loop_closes() -> void:
	if _book == null:
		fail_test(MISSING)
		return
	for book_seed in _book.seeds:
		var steps := 0.0
		for f in _book.frames - 1:
			steps += _step(
				_book.layers[_book.layer_of(book_seed, f)],
				_book.layers[_book.layer_of(book_seed, f + 1)]
			)
		var mean := steps / (_book.frames - 1)
		assert_gt(mean, 0.0, "seed %d's frames move" % book_seed)
		var wrap_step := _step(
			_book.layers[_book.layer_of(book_seed, -1)], _book.layers[_book.layer_of(book_seed, 0)]
		)
		assert_lt(wrap_step, mean * 2.0, "seed %d's last frame runs into its first" % book_seed)


func test_the_texture_builds_and_is_released() -> void:
	if _book == null:
		fail_test(MISSING)
		return
	var texture := _book.create_texture()
	assert_not_null(texture)
	if texture == null:
		return
	assert_eq(texture.get_layers(), 48)
	assert_eq(texture.get_width(), 128)
	assert_eq(texture.get_height(), 160)
	assert_eq(texture.get_format(), Image.FORMAT_RGBA8)
	var held: WeakRef = weakref(texture)
	texture = null
	assert_null(held.get_ref(), "dropping the last reference frees the array")


func test_the_smoke_binds_its_book_and_lets_it_go() -> void:
	var material := FireFieldSmoke.material()
	FireFieldSmoke.release_book()
	assert_eq(material.get_shader_parameter("frames"), 0, "no book: the columns draw nothing")
	FireFieldSmoke.request_book()
	assert_eq(FireFieldSmoke.book_state(), FireLook.Book.LOADING)
	assert_true(FireFieldSmoke.finish_book(), "the book lands")
	assert_not_null(material.get_shader_parameter("smoke_book"), "bound")
	assert_not_null(FireFieldSmoke.book_texture())
	assert_eq(material.get_shader_parameter("frames"), 24)
	assert_eq(material.get_shader_parameter("seeds"), 2)
	assert_eq(material.get_shader_parameter("domain"), FireSmokeBook.DOMAIN)
	FireFieldSmoke.release_book()
	assert_eq(FireFieldSmoke.book_state(), FireLook.Book.NONE)
	assert_null(FireFieldSmoke.book_texture())
	assert_null(material.get_shader_parameter("smoke_book"), "the sampler is null")
	assert_eq(material.get_shader_parameter("frames"), 0, "and nothing draws")


## The mean difference (0..255) between two frames.
func _step(a: Image, b: Image) -> float:
	return float(a.compute_image_metrics(b, false)["mean"])
