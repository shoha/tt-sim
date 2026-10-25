extends GutTest

## The UI-free model of one library transfer (LibraryTransferConsent): the question the host's
## quote becomes, what Download and Skip lead to, the size cap's refusal, the progress line and
## every end state. The dialogs only show what this says.

const QUOTE := {
	"ok": true,
	"protocol": 1,
	"libraries":
	[
		{
			"id": "alienworld",
			"name": "Alien World",
			"version": "1.2.0",
			"author": "Test Author",
			"assets": 12,
			"files": 20,
			"bytes": 5 * 1024 * 1024,
			"assets_only": false,
		},
	],
	"bytes": 5 * 1024 * 1024,
	"files": 20,
	"skipped": 0,
}


func _quote(extra: Dictionary = {}) -> Dictionary:
	var out := QUOTE.duplicate(true)
	out.merge(extra, true)
	return out


func test_the_question_names_the_collection_its_author_assets_and_size() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_quote())
	assert_eq(model.phase, LibraryTransferConsent.Phase.ASKING)
	assert_string_contains(
		model.message, "Host uses collection Alien World v1.2.0 by Test Author (12 assets, 5.0 MB)."
	)
	assert_string_contains(model.message, "Download 5.0 MB?")
	assert_string_contains(model.message, "until the session ends")


func test_a_dependency_part_is_listed_and_skipped_assets_are_reported() -> void:
	var quote := _quote({"skipped": 3})
	(
		quote["libraries"]
		. append(
			{
				"id": "pool",
				"name": "Pool",
				"version": "1.0.0",
				"author": "",
				"assets": 2,
				"files": 3,
				"bytes": 2048,
				"assets_only": true,
			}
		)
	)
	var model := LibraryTransferConsent.new()
	model.offer(quote)
	assert_string_contains(model.message, "Also Pool v1.0.0 (2 assets, 2 KB)")
	assert_string_contains(model.message, "3 plants the map uses are no longer in the host's copy")


func test_a_quote_over_the_size_cap_is_refused_without_a_question() -> void:
	var model := LibraryTransferConsent.new(1024 * 1024)
	model.offer(_quote())
	assert_eq(model.phase, LibraryTransferConsent.Phase.REFUSED)
	assert_string_contains(model.message, "5.0 MB, over the 1.0 MB limit")
	assert_true(model.finished())
	model.answer(true)
	assert_eq(model.phase, LibraryTransferConsent.Phase.REFUSED, "no answer is taken")


func test_a_host_refusal_ends_the_transfer_with_its_reason() -> void:
	var model := LibraryTransferConsent.new()
	model.offer({"ok": false, "error": "not used by any map in this session"})
	assert_eq(model.phase, LibraryTransferConsent.Phase.REFUSED)
	assert_string_contains(model.message, "not used by any map")


func test_skip_ends_it_and_leaves_the_open_without_choice() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_quote())
	model.answer(false)
	assert_eq(model.phase, LibraryTransferConsent.Phase.SKIPPED)
	assert_string_contains(model.message, "without those plants")
	assert_true(model.finished())
	assert_false(model.installed())


func test_download_then_progress_then_install() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_quote())
	model.answer(true)
	assert_eq(model.phase, LibraryTransferConsent.Phase.RECEIVING)
	model.progress(2 * 1024 * 1024, 5 * 1024 * 1024)
	assert_eq(model.message, "Receiving plants from the host: 2.0 MB of 5.0 MB (40%)")
	assert_almost_eq(model.fraction(5 * 1024 * 1024), 0.4, 0.001)
	model.installing()
	assert_eq(model.phase, LibraryTransferConsent.Phase.INSTALLING)
	model.done()
	assert_true(model.installed())
	assert_string_contains(model.message, "Received 12 assets")


func test_cancel_only_works_while_receiving() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_quote())
	model.cancel()
	assert_eq(model.phase, LibraryTransferConsent.Phase.ASKING, "not receiving yet")
	model.answer(true)
	model.cancel()
	assert_eq(model.phase, LibraryTransferConsent.Phase.CANCELLED)
	assert_true(model.finished())
	model.fail("too late")
	assert_eq(model.phase, LibraryTransferConsent.Phase.CANCELLED, "an ended transfer stays ended")


func test_a_failure_while_receiving_or_waiting_carries_its_text() -> void:
	var model := LibraryTransferConsent.new()
	model.fail("The host did not answer.")
	assert_eq(model.phase, LibraryTransferConsent.Phase.FAILED)
	assert_eq(model.message, "The host did not answer.")
	var other := LibraryTransferConsent.new()
	other.offer(_quote())
	other.answer(true)
	other.fail("The download failed")
	assert_eq(other.phase, LibraryTransferConsent.Phase.FAILED)


func test_error_text_names_the_first_error() -> void:
	assert_string_contains(
		LibraryTransferConsent.error_text(
			[{"code": "bad_hash", "text": "alienworld: catalog x differs"}]
		),
		"catalog x differs"
	)
	assert_ne(LibraryTransferConsent.error_text([]), "")


func test_bytes_read_as_people_say_them() -> void:
	assert_eq(LibraryTransfer.format_bytes(12), "12 bytes")
	assert_eq(LibraryTransfer.format_bytes(1500), "2 KB")
	assert_eq(LibraryTransfer.format_bytes(3 * 1024 * 1024), "3.0 MB")
