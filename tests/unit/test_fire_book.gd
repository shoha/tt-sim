extends GutTest

## FireBook (the fire's shipped drawing book, res://assets/fire/fire_book.res; card fire-prod-c1):
## the file is in the checkout and is the book, not a Git LFS pointer (a clone without `git lfs
## pull` fails here loudly); it holds 8 sequences of 48 RGBA8 96x128 drawings with their mips and
## the tear layer last, 385 layers; the classes start at sequences 0, 3 and 5 of 8 and every
## sequence's bounds lie inside the tile; the GPU array builds from it with every layer and mip,
## and dropping it frees it. The pointer check itself tells a pointer from a binary file.

const POINTER_PATH := "user://_fire_book_test_pointer.txt"
const MISSING := "fire book missing or an LFS pointer: run git lfs pull"

var _book: FireBook = null


func before_all() -> void:
	if ResourceLoader.exists(FireBook.PATH) and not FireBook.is_lfs_pointer():
		_book = ResourceLoader.load(FireBook.PATH) as FireBook


func after_all() -> void:
	_book = null


func after_each() -> void:
	if FileAccess.file_exists(POINTER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(POINTER_PATH))


func test_the_book_is_checked_out_not_a_pointer() -> void:
	assert_true(FileAccess.file_exists(FireBook.PATH), MISSING)
	assert_false(FireBook.is_lfs_pointer(), MISSING)
	var size := FileAccess.get_file_as_bytes(FireBook.PATH).size()
	assert_gt(size, 1 << 20, "the book is megabytes, not a pointer's few lines")
	assert_not_null(_book, MISSING)


func test_the_pointer_check_tells_a_pointer() -> void:
	var file := FileAccess.open(POINTER_PATH, FileAccess.WRITE)
	file.store_string("version https://git-lfs.github.com/spec/v1\noid sha256:00\nsize 1\n")
	file.close()
	assert_true(FireBook.is_lfs_pointer(POINTER_PATH))
	assert_false(FireBook.is_lfs_pointer("user://_fire_book_test_absent.res"))


func test_385_rgba8_layers_with_mips() -> void:
	if _book == null:
		fail_test(MISSING)
		return
	assert_eq(_book.problem(), "", "the book validates")
	assert_eq(_book.format, "TTFSIM02")
	assert_eq(_book.source_sha256.length(), 64, "the source .bin's sha256 is recorded")
	assert_eq(_book.tile, Vector2i(96, 128))
	assert_eq(_book.drawings, 48)
	assert_eq(_book.layers.size(), 385)
	var bad := 0
	for image in _book.layers:
		var whole := (
			image != null
			and image.get_size() == Vector2i(96, 128)
			and image.get_format() == Image.FORMAT_RGBA8
			and image.has_mipmaps()
		)
		if not whole:
			bad += 1
	assert_eq(bad, 0, "every layer is a 96x128 RGBA8 Image with mips")


func test_classes_bounds_and_tear_layer() -> void:
	if _book == null:
		fail_test(MISSING)
		return
	assert_eq(_book.class_first, Vector4i(0, 3, 5, 8))
	assert_eq(_book.sequence_count(), 8)
	for b in _book.seq_bounds:
		assert_true(b.x >= 0.0 and b.y >= 0.0 and b.z <= 1.0 and b.w <= 1.0, "%s in 0..1" % b)
		assert_true(b.x < b.z and b.y < b.w, "%s is not empty" % b)
	assert_eq(_book.tear_layer, 384)
	assert_eq(_book.layer_of(7, 47), 383, "the last drawing sits just before the tear layer")
	assert_eq(_book.layer_of(1, 48), 48, "a drawing wraps round its loop")


func test_the_texture_builds_and_is_released() -> void:
	if _book == null:
		fail_test(MISSING)
		return
	var texture := _book.create_texture()
	assert_not_null(texture)
	if texture == null:
		return
	assert_eq(texture.get_layers(), 385)
	assert_eq(texture.get_width(), 96)
	assert_eq(texture.get_height(), 128)
	assert_true(texture.has_mipmaps(), "the array keeps the layers' mips")
	assert_eq(texture.get_format(), Image.FORMAT_RGBA8)
	var held: WeakRef = weakref(texture)
	texture = null
	assert_null(held.get_ref(), "dropping the last reference frees the array")
