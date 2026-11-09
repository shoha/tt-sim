class_name TokenStateWire
extends RefCounted

## The table's token state on the wire (topic perfaudit, card netspawn): GameState's state
## dictionary (GameState.get_full_state_dict()'s shape, {"tokens": {network_id: TokenState
## dict}, "permissions": {...}, "drag_locks": {...}}) as one compressed message, cut into
## chunks for the reliable channel.
##
## Two kinds share the one encoding and the one receive path, so a token's add and a late
## joiner's state cannot drift apart: FULL is the whole table (a late joiner's state, a table
## set out, the reconciliation heartbeat) and replaces what the receiver holds
## (GameState.merge_full_state_dict); ADD carries one or a few tokens in the same shape and
## adds or updates only those (GameState.upsert_state_dict), keyed by network_id, so an add
## that arrives for a token the receiver already holds changes nothing but its values.
##
## Bytes: [u8 FORMAT][u8 kind][u32 raw size, little endian][zstd of var_to_bytes(state)].
## zstd beat deflate from 10 tokens up (the 200-avatar state: 153,660 B raw, 4,711 zstd, 5,579
## deflate; docs/PERFORMANCE.md "Token sync bytes"); deflate is about 40 B smaller for one token,
## not worth a second codec. A message leaves in chunks of at
## most CHUNK_BYTES (64 KB; Steam refuses one message past 512 KB, chunks()) and is put back
## together by an Assembler (the live edits' scheme, LiveEditCodec, kept apart so this codec
## loads nothing else), all chunks in one call: no other token message can come between them
## on the ordered reliable channel, so every add or removal sent after a state was taken
## arrives after it. SEND_BUDGET_BYTES is the size a state may reach before that burst could
## crowd Steam's send queue (see the constant).
##
## decode() reads untrusted bytes: the header, the raw size cap before decompressing, the
## decompressed length, and a Dictionary with a "tokens" Dictionary; bytes_to_var refuses
## objects. Malformed zstd makes the engine print an error first; only the host sends.

enum Kind { FULL = 0, ADD = 1 }

const FORMAT := 1
const HEADER_BYTES := 6
## Largest decompressed state decode() accepts: about 40,000 avatar tokens, far past any table.
const MAX_RAW_BYTES := 32 * 1024 * 1024
const COMPRESSION := FileAccess.COMPRESSION_ZSTD
## Largest chunk of a message on the wire, and most chunks one message takes (4 MB compressed).
const CHUNK_BYTES := 64 * 1024
const MAX_CHUNKS := 64
## A state burst above this many bytes is logged as a warning. Steam silently drops reliable
## messages past about 512 KB queued per connection (NETWORKING.md "Send limits"); a map
## download keeps up to AssetStreamer's 256 KB window in flight to the same peer and live
## edits burst one 64 KB chunk, which leaves 192 KB for a state sent in one go. At the
## measured 40 to 97 B per token compressed (identical avatars, pack tokens, avatars with
## distinct full recipes) that is 2,000 to 4,900 tokens, and 512 KB is 5,400 to 13,000.
const SEND_BUDGET_BYTES := 192 * 1024


## `state` (GameState's state dictionary) as one message of `kind`.
static func encode(state: Dictionary, kind: int) -> PackedByteArray:
	var raw := var_to_bytes(state)
	var out := PackedByteArray()
	out.resize(HEADER_BYTES)
	out.encode_u8(0, FORMAT)
	out.encode_u8(1, kind)
	out.encode_u32(2, raw.size())
	out.append_array(raw.compress(COMPRESSION))
	return out


## Reads untrusted `bytes`: {"kind": Kind, "state": Dictionary, "problem": ""}, or with
## "problem" saying why it was refused (then "state" is {}).
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= HEADER_BYTES:
		return _refused("%d bytes, no payload" % bytes.size())
	if bytes.decode_u8(0) != FORMAT:
		return _refused("format %d is not %d" % [bytes.decode_u8(0), FORMAT])
	var kind := bytes.decode_u8(1)
	if not Kind.values().has(kind):
		return _refused("unknown kind %d" % kind)
	var raw_size := bytes.decode_u32(2)
	if raw_size < 1 or raw_size > MAX_RAW_BYTES:
		return _refused("raw size %d outside 1..%d" % [raw_size, MAX_RAW_BYTES])
	var raw := bytes.slice(HEADER_BYTES).decompress(raw_size, COMPRESSION)
	if raw.size() != raw_size:
		return _refused("inflated to %d bytes, not %d" % [raw.size(), raw_size])
	var value: Variant = bytes_to_var(raw)
	if not value is Dictionary or not (value as Dictionary).get("tokens") is Dictionary:
		return _refused("not a state")
	return {"kind": kind, "state": value, "problem": ""}


## `bytes` as the chunks that cross the network, each at most CHUNK_BYTES, in order.
static func chunks(bytes: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for start in range(0, bytes.size(), CHUNK_BYTES):
		out.append(bytes.slice(start, start + CHUNK_BYTES))
	return out


static func _refused(why: String) -> Dictionary:
	return {"kind": -1, "state": {}, "problem": why}


## A receiver's reassembly of one message from its chunks, which arrive in order on one
## reliable channel: part 0 starts a message, every later part must continue it (same serial
## and count, the next index), and the whole is returned with its last part. A part out of
## order, empty or past CHUNK_BYTES, or a count past MAX_CHUNKS drops the message (`problem`
## says why); the next part 0 starts afresh.
class Assembler:
	extends RefCounted

	## Why the last part was refused, or "".
	var problem: String = ""

	var _serial: int = -1
	var _parts: int = 0
	var _next: int = 0
	var _bytes := PackedByteArray()

	## Adds part `part` of `parts` of message `serial`: the message's bytes once whole, else
	## [] (more to come, or refused).
	func add(serial: int, part: int, parts: int, data: PackedByteArray) -> PackedByteArray:
		problem = ""
		if part == 0:
			_reset()
			if parts < 1 or parts > TokenStateWire.MAX_CHUNKS:
				return _refuse("a message of %d chunks" % parts)
			_serial = serial
			_parts = parts
		elif serial != _serial or parts != _parts or part != _next:
			return _refuse("a chunk out of order")
		if data.is_empty() or data.size() > TokenStateWire.CHUNK_BYTES:
			return _refuse("a chunk of %d bytes" % data.size())
		_bytes.append_array(data)
		_next += 1
		if _next < _parts:
			return PackedByteArray()
		var whole := _bytes
		_reset()
		return whole

	func _refuse(why: String) -> PackedByteArray:
		problem = why
		_reset()
		return PackedByteArray()

	func _reset() -> void:
		_serial = -1
		_parts = 0
		_next = 0
		_bytes = PackedByteArray()
