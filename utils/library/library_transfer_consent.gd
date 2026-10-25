class_name LibraryTransferConsent
extends RefCounted

## The UI-free model of one library transfer as the player lives it: the host's quote becomes a
## question ("Host uses collection X v1.2 by Y (N assets, M MB). Download?"), the answer starts or
## ends the transfer, and the bytes received become a progress line. The dialogs
## (LibraryTransferUi) only show what this says, so the rules are testable without a window.
##
## Phases: QUOTING (asked the host what it would send), ASKING (the player decides), RECEIVING,
## INSTALLING, then one of DONE, SKIPPED (the player said no), REFUSED (the quote is over the
## size cap or the host said no: no question is asked), CANCELLED (the player cancelled while
## receiving) or FAILED (a transfer or check error). A SKIPPED, REFUSED, CANCELLED or FAILED
## transfer leaves the existing "Open without those plants" choice (MapLibraryGate) to the player.

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

const TITLE := "The host uses plants you do not have"
const DOWNLOAD := "Download"
const SKIP := "Skip"
const CANCEL_DOWNLOAD := "Cancel download"

var phase: Phase = Phase.QUOTING
var quote: Dictionary = {}
var cap_bytes: int = LibraryTransfer.MAX_REQUEST_BYTES
var received_bytes: int = 0
var message: String = ""


## The player-facing text of a failed library transfer, from its first error.
static func error_text(errors: Array) -> String:
	if errors.is_empty():
		return "The plants from the host could not be installed."
	var first: Dictionary = errors[0]
	return "The plants from the host were not installed: %s" % String(first.get("text", "?"))


func _init(size_cap: int = LibraryTransfer.MAX_REQUEST_BYTES) -> void:
	cap_bytes = size_cap


## The host answered `reply` (LibraryTransfer.quote's result). Moves to ASKING, or to REFUSED
## with the reason in `message` when the host said no or the size is over the cap.
func offer(reply: Dictionary) -> void:
	quote = reply
	if not bool(reply.get("ok", false)):
		phase = Phase.REFUSED
		message = "The host could not send its plants: %s" % String(reply.get("error", "no reason"))
		return
	var bytes := int(reply.get("bytes", 0))
	if bytes > cap_bytes:
		phase = Phase.REFUSED
		message = (
			"The host's plants for this map are %s, over the %s limit, so they are not downloaded."
			% [LibraryTransfer.format_bytes(bytes), LibraryTransfer.format_bytes(cap_bytes)]
		)
		return
	phase = Phase.ASKING
	message = question_text(reply)


## The question the dialog shows: every library the host would send, then the total and what
## happens to it.
static func question_text(reply: Dictionary) -> String:
	var lines: Array[String] = []
	for item: Dictionary in reply.get("libraries", []):
		if bool(item.get("assets_only", false)):
			lines.append(
				(
					"Also %s v%s (%d assets, %s)"
					% [
						item["name"],
						item["version"],
						item["assets"],
						LibraryTransfer.format_bytes(int(item["bytes"]))
					]
				)
			)
			continue
		var author := " by %s" % item["author"] if String(item.get("author", "")) != "" else ""
		(
			lines
			. append(
				(
					"Host uses collection %s v%s%s (%d assets, %s)."
					% [
						item["name"],
						item["version"],
						author,
						item["assets"],
						LibraryTransfer.format_bytes(int(item["bytes"])),
					]
				)
			)
		)
	var text := "\n".join(lines)
	text += (
		"\n\nDownload %s? It stays on this computer only until the session ends."
		% (LibraryTransfer.format_bytes(int(reply.get("bytes", 0))))
	)
	if int(reply.get("skipped", 0)) > 0:
		text += "\n%d plants the map uses are no longer in the host's copy." % int(reply["skipped"])
	return text


## The player's answer in ASKING: true downloads, false skips. Ignored in any other phase.
func answer(download: bool) -> void:
	if phase != Phase.ASKING:
		return
	phase = Phase.RECEIVING if download else Phase.SKIPPED
	message = "" if download else "Skipped. The map can be opened without those plants."


## Bytes of the compressed stream received so far of `total` (RECEIVING only).
func progress(done: int, total: int) -> void:
	if phase == Phase.RECEIVING:
		received_bytes = done
		message = progress_text(done, total)


func fraction(total: int) -> float:
	return clampf(float(received_bytes) / float(maxi(total, 1)), 0.0, 1.0)


static func progress_text(done: int, total: int) -> String:
	return (
		"Receiving plants from the host: %s of %s (%d%%)"
		% [
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


## Installed: the plants are served for this session.
func done() -> void:
	if phase == Phase.INSTALLING:
		phase = Phase.DONE
		message = "Received %d assets from the host for this session." % total_assets()


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


## True when the plants are installed (the gate then checks the libraries again).
func installed() -> bool:
	return phase == Phase.DONE
