extends RefCounted

## The net launcher's check of the peers' engine logs (every *.godot.log in the run's folder:
## each peer's, and any a scenario starts itself, such as enet_session_file's resume.godot.log)
## for the two errors a peer's teardown used to log.
##
## - A send to a closed peer: "Unable to send packet on channel 0, max channels: 0". Over ENet a
##   closing peer's channels are freed when its disconnect arrives, before Godot reports the
##   leave, so the host logged one per closed peer for every broadcast made while a poll that
##   reported several leaves was still reporting them. One from script (the error carries a
##   GDScript backtrace) fails the run. One from the engine alone is SceneMultiplayer's own
##   relay telling the other clients of a leave (server_relay, Godot's default), which no
##   script can defer; it is counted and reported, not failed.
## - A closed peer asked for its id or role: "The multiplayer instance isn't currently
##   active", which a client logged when the host ended the session while it was at a table.
##   Every one fails the run.

const SEND_TO_CLOSED := "Unable to send packet on channel"
const INACTIVE := "The multiplayer instance isn't currently active"
const BACKTRACE := "GDScript backtrace"


## The two errors in one engine log's `text`: {"script_sends", "engine_sends", "inactive"},
## each a count. An error's own lines (its "at:" line and backtrace) are the indented lines
## under it.
static func teardown_errors(text: String) -> Dictionary:
	var counts := {"script_sends": 0, "engine_sends": 0, "inactive": 0}
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i]
		if not line.begins_with("ERROR: "):
			continue
		if line.contains(INACTIVE):
			counts.inactive += 1
		elif line.contains(SEND_TO_CLOSED):
			if _has_backtrace(lines, i):
				counts.script_sends += 1
			else:
				counts.engine_sends += 1
	return counts


## True when the counts of teardown_errors() fail a run.
static func fails(counts: Dictionary) -> bool:
	return int(counts.get("script_sends", 0)) > 0 or int(counts.get("inactive", 0)) > 0


## True when one of the indented lines under line `at` is a GDScript backtrace.
static func _has_backtrace(lines: PackedStringArray, at: int) -> bool:
	for j in range(at + 1, lines.size()):
		var line := lines[j]
		if not line.begins_with(" "):
			return false
		if line.contains(BACKTRACE):
			return true
	return false
