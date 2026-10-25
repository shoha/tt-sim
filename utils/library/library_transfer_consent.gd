class_name LibraryTransferConsent
extends RefCounted

## The UI-free model of one library transfer as the player lives it: the host's quote becomes a
## question ("The host uses collection X v1.2 by Y (N items, M MB). Download?"), the answer
## starts or ends the transfer, and the bytes received become a progress line. The dialogs
## (LibraryTransferUi) only show what this says, so the rules are testable without a window.
##
## Consent is asked ONCE per collection and source hash: a collection kept from this host
## (`kept`, its LibraryFromHost record) extends without a question while the delta is small
## (LibraryFromHost.covers), a bigger delta or a new version asks again, and a Skip is remembered
## by the channel for the session. Every word that names the content goes through LibraryNames
## (the one-word rule, and no "plants"), every count through its plural helper.
##
## Phases: QUOTING (asked the host what it would send), ASKING (the player decides), RECEIVING,
## INSTALLING, then one of DONE, SKIPPED (the player said no), REFUSED (the quote is over the
## size cap or the host said no: no question is asked), CANCELLED (the player cancelled while
## receiving) or FAILED (a transfer or check error). A SKIPPED, REFUSED, CANCELLED or FAILED
## transfer leaves the existing "Open without those ..." choice (MapLibraryGate) to the player.

enum Phase {
	QUOTING,
	ASKING,
	RECEIVING,
	INSTALLING,
	DONE,
	SKIPPED,
	REFUSED,
	CANCELLED,
	FAILED,
}

const DOWNLOAD := "Download"
const SKIP := "Skip"
const CANCEL_DOWNLOAD := "Cancel download"

var phase: Phase = Phase.QUOTING
var quote: Dictionary = {}
var cap_bytes: int = LibraryTransfer.MAX_REQUEST_BYTES
var received_bytes: int = 0
var message: String = ""
## True when the player's earlier "Download" covered this one and no question was asked.
var unasked: bool = false


func _init(size_cap: int = LibraryTransfer.MAX_REQUEST_BYTES) -> void:
	cap_bytes = size_cap


## The title of the question and of the progress sheet.
static func title() -> String:
	return LibraryNames.host_uses_title()


## The player-facing text of a failed library transfer, from its first error.
static func error_text(errors: Array) -> String:
	if errors.is_empty():
		return "The %s from the host could not be installed." % LibraryNames.lower(2)
	var first: Dictionary = errors[0]
	var head := "The %s from the host were not installed" % LibraryNames.lower(2)
	return "%s: %s" % [head, String(first.get("text", "?"))]


## The library the player asked for in a quote (the first that is not a dependency pool), {} when
## there is none.
static func main_library(reply: Dictionary) -> Dictionary:
	for item: Dictionary in reply.get("libraries", []):
		if not bool(item.get("assets_only", false)):
			return item
	return {}


## The host answered `reply` (LibraryTransfer.quote's result); `kept` is the LibraryFromHost
## record of the collection when an earlier download is on disk, else {}. Moves to ASKING, to
## RECEIVING without a question when `kept` covers it, or to REFUSED with the reason in `message`
## when the host said no or the size is over the cap.
func offer(reply: Dictionary, kept: Dictionary = {}) -> void:
	quote = reply
	if not bool(reply.get("ok", false)):
		phase = Phase.REFUSED
		var reason := String(reply.get("error", "no reason"))
		message = "The host could not send its %s: %s" % [LibraryNames.lower(2), reason]
		return
	var bytes := int(reply.get("bytes", 0))
	if bytes > cap_bytes:
		phase = Phase.REFUSED
		message = (
			"The host's %s for this map are %s, over the %s limit, so they are not downloaded."
			% [
				LibraryNames.lower(2),
				LibraryTransfer.format_bytes(bytes),
				LibraryTransfer.format_bytes(cap_bytes)
			]
		)
		return
	var main := main_library(reply)
	if LibraryFromHost.covers(kept, String(main.get("hash", "?")), bytes):
		unasked = true
		phase = Phase.RECEIVING
		message = ""
		return
	phase = Phase.ASKING
	message = question_text(reply, kept)


## The question the dialog shows: every collection the host would send, then the total and what
## happens to it. `kept` is the record of the copy already on disk ({} for a new collection).
static func question_text(reply: Dictionary, kept: Dictionary = {}) -> String:
	var lines: Array[String] = []
	for item: Dictionary in reply.get("libraries", []):
		var items := LibraryNames.count_of(int(item["assets"]), "item")
		var size := LibraryTransfer.format_bytes(int(item["bytes"]))
		if bool(item.get("assets_only", false)):
			lines.append("Also %s v%s (%s, %s)" % [item["name"], item["version"], items, size])
			continue
		var author := " by %s" % item["author"] if String(item.get("author", "")) != "" else ""
		var same := String(kept.get("source_hash", "?")) == String(item.get("hash", ""))
		if not kept.is_empty() and same:
			var more := "The host's map needs %s more from the %s %s v%s%s you downloaded (%s)."
			var parts := [items, LibraryNames.lower(), item["name"], item["version"], author, size]
			lines.append(more % parts)
			continue
		var uses := "The host uses the %s %s v%s%s (%s, %s)."
		var facts := [LibraryNames.lower(), item["name"], item["version"], author, items, size]
		lines.append(uses % facts)
	var text := "\n".join(lines)
	text += (
		"\n\nDownload %s? It stays on this computer until you remove it in %s."
		% [LibraryTransfer.format_bytes(int(reply.get("bytes", 0))), LibraryNames.title(2)]
	)
	if int(reply.get("skipped", 0)) > 0:
		var gone := LibraryNames.count_of(int(reply["skipped"]), "item")
		text += "\n%s the map uses no longer exist in the host's copy." % gone
	return text


## The player's answer in ASKING: true downloads, false skips. Ignored in any other phase.
func answer(download: bool) -> void:
	if phase != Phase.ASKING:
		return
	phase = Phase.RECEIVING if download else Phase.SKIPPED
	if not download:
		message = "Skipped. The map can be opened without those %s." % LibraryNames.lower(2)
	else:
		message = ""


## The player skipped this collection earlier in the session: no question, no download.
func skip_remembered() -> void:
	phase = Phase.SKIPPED
	message = ""


## Bytes of the compressed stream received so far of `total` (RECEIVING only).
func progress(done: int, total: int) -> void:
	if phase == Phase.RECEIVING:
		received_bytes = done
		message = progress_text(done, total)


func fraction(total: int) -> float:
	return clampf(float(received_bytes) / float(maxi(total, 1)), 0.0, 1.0)


static func progress_text(done: int, total: int) -> String:
	return (
		"%s: %s of %s (%d%%)"
		% [
			LibraryNames.receiving_from_host(),
			LibraryTransfer.format_bytes(done),
			LibraryTransfer.format_bytes(total),
			int(100.0 * float(done) / float(maxi(total, 1))),
		]
	)


## The bytes arrived and are being checked.
func installing() -> void:
	if phase == Phase.RECEIVING:
		phase = Phase.INSTALLING
		message = "Checking what the host sent..."


## Installed: kept on this computer, ready to use.
func done() -> void:
	if phase == Phase.INSTALLING:
		phase = Phase.DONE
		message = done_text()


## The line after an install, naming the collection and where to manage it.
func done_text() -> String:
	var main := main_library(quote)
	var what := LibraryNames.count_of(total_assets(), "item")
	return (
		"Received %s (%s) from the host. It stays on this computer; remove it any time in %s."
		% [String(main.get("name", LibraryNames.title())), what, LibraryNames.title(2)]
	)


## The player cancelled during RECEIVING.
func cancel() -> void:
	if phase == Phase.RECEIVING:
		phase = Phase.CANCELLED
		message = "Download cancelled."


## A transfer, check or install error in RECEIVING or INSTALLING.
func fail(text: String) -> void:
	if phase == Phase.RECEIVING or phase == Phase.INSTALLING or phase == Phase.QUOTING:
		phase = Phase.FAILED
		message = text


func total_assets() -> int:
	var total := 0
	for item: Dictionary in quote.get("libraries", []):
		total += int(item.get("assets", 0))
	return total


## True once the transfer is over, whatever the outcome.
func finished() -> bool:
	return phase in [Phase.DONE, Phase.SKIPPED, Phase.REFUSED, Phase.CANCELLED, Phase.FAILED]


## True when the collections are installed (the gate then checks the libraries again).
func installed() -> bool:
	return phase == Phase.DONE
