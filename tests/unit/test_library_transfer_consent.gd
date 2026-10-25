extends GutTest

## The UI-free model of one library transfer (LibraryTransferConsent): the question the host's
## quote becomes, what Download and Skip lead to, the size cap's refusal, the progress line, the
## ask-once rule for a collection already kept from this host, and every end state. The dialogs
## only show what this says.

const MIB := 1024 * 1024
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
			"hash": "abc12345",
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


## A quote of a delta of `bytes` bytes for the collection above.
func _delta(bytes: int, assets: int = 2) -> Dictionary:
	var out := _quote({"bytes": bytes})
	out["libraries"][0]["bytes"] = bytes
	out["libraries"][0]["assets"] = assets
	return out


## The record of a kept copy of the same collection (the player agreed to it once).
func _kept(source_hash: String = "abc12345", auto_delta: bool = true) -> Dictionary:
	return {"source_hash": source_hash, "version": "1.2.0", "auto_delta": auto_delta}


func test_the_question_names_the_collection_its_author_items_and_size() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_quote())
	assert_eq(model.phase, LibraryTransferConsent.Phase.ASKING)
	assert_string_contains(
		model.message,
		"The host uses the collection Alien World v1.2.0 by Test Author (12 items, 5.0 MB)."
	)
	assert_string_contains(model.message, "Download 5.0 MB?")
	assert_string_contains(model.message, "until you remove it in Collections")
	assert_false("session" in model.message, "it is kept, not session-only")


func test_counts_read_in_the_singular_too() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_delta(4096, 1))
	assert_string_contains(model.message, "(1 item, 4 KB)")
	assert_false("1 items" in model.message)
	assert_eq(LibraryNames.count_of(0, "item"), "0 items")
	assert_eq(LibraryNames.count_of(1, "item"), "1 item")
	assert_eq(LibraryNames.count_of(2, "item"), "2 items")


func test_a_dependency_part_is_listed_and_skipped_items_are_reported() -> void:
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
	assert_string_contains(model.message, "Also Pool v1.0.0 (2 items, 2 KB)")
	assert_string_contains(model.message, "3 items the map uses no longer exist in the host's copy")


func test_no_transfer_text_says_plants_or_keep() -> void:
	var texts: Array[String] = []
	var model := LibraryTransferConsent.new()
	model.offer(_quote({"skipped": 1}))
	texts.append(model.message)
	model.answer(false)
	texts.append(model.message)
	texts.append(LibraryTransferConsent.title())
	texts.append(LibraryTransferConsent.progress_text(1, 2))
	texts.append(LibraryTransferConsent.error_text([]))
	texts.append(LibraryTransferConsent.error_text([{"text": "x"}]))
	var refused := LibraryTransferConsent.new(1)
	refused.offer(_quote())
	texts.append(refused.message)
	var failed := LibraryTransferConsent.new()
	failed.offer({"ok": false, "error": "no"})
	texts.append(failed.message)
	var done := LibraryTransferConsent.new()
	done.offer(_quote())
	done.answer(true)
	done.installing()
	done.done()
	texts.append(done.message)
	for text in texts:
		assert_false("plants" in text.to_lower(), text)
		assert_false("keep" in text.to_lower().split(" "), text)


func test_a_quote_over_the_size_cap_is_refused_without_a_question() -> void:
	var model := LibraryTransferConsent.new(1024 * 1024)
	model.offer(_quote())
	assert_eq(model.phase, LibraryTransferConsent.Phase.REFUSED)
	assert_string_contains(model.message, "5.0 MB, over the 1.0 MB limit")
	assert_string_contains(model.message, "The host's collections for this map")
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
	assert_string_contains(model.message, "without those collections")
	assert_true(model.finished())
	assert_false(model.installed())


func test_download_then_progress_then_install() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_quote())
	model.answer(true)
	assert_eq(model.phase, LibraryTransferConsent.Phase.RECEIVING)
	model.progress(2 * 1024 * 1024, 5 * 1024 * 1024)
	assert_eq(model.message, "Receiving collections from the host: 2.0 MB of 5.0 MB (40%)")
	assert_almost_eq(model.fraction(5 * 1024 * 1024), 0.4, 0.001)
	model.installing()
	assert_eq(model.phase, LibraryTransferConsent.Phase.INSTALLING)
	model.done()
	assert_true(model.installed())
	assert_string_contains(model.message, "Received Alien World (12 items) from the host")
	assert_string_contains(model.message, "remove it any time in Collections")


# ---- ask once ----


func test_a_collection_kept_from_this_host_extends_without_a_question_while_small() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_delta(2 * MIB), _kept())
	assert_eq(model.phase, LibraryTransferConsent.Phase.RECEIVING, "straight to the download")
	assert_true(model.unasked)


func test_a_big_delta_asks_again_and_says_it_is_more_of_the_same() -> void:
	var model := LibraryTransferConsent.new()
	model.offer(_delta(LibraryFromHost.AUTO_DELTA_BYTES), _kept())
	assert_eq(model.phase, LibraryTransferConsent.Phase.ASKING, "5 MB is not under the threshold")
	assert_false(model.unasked)
	assert_string_contains(model.message, "needs 2 items more from the collection Alien World")
	assert_string_contains(model.message, "you downloaded")


func test_another_source_hash_or_no_record_or_a_cleared_flag_asks() -> void:
	var changed := LibraryTransferConsent.new()
	changed.offer(_delta(1024), _kept("another1"))
	assert_eq(changed.phase, LibraryTransferConsent.Phase.ASKING, "not the same collection")
	var fresh := LibraryTransferConsent.new()
	fresh.offer(_delta(1024), {})
	assert_eq(fresh.phase, LibraryTransferConsent.Phase.ASKING)
	var no_auto := LibraryTransferConsent.new()
	no_auto.offer(_delta(1024), _kept("abc12345", false))
	assert_eq(no_auto.phase, LibraryTransferConsent.Phase.ASKING)


func test_a_size_cap_still_refuses_a_covered_delta() -> void:
	var model := LibraryTransferConsent.new(1024)
	model.offer(_delta(2 * MIB), _kept())
	assert_eq(model.phase, LibraryTransferConsent.Phase.REFUSED)


func test_a_skip_remembered_for_the_session_ends_it_quietly() -> void:
	var model := LibraryTransferConsent.new()
	model.skip_remembered()
	assert_eq(model.phase, LibraryTransferConsent.Phase.SKIPPED)
	assert_eq(model.message, "")


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
