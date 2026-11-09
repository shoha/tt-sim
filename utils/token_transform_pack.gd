class_name TokenTransformPack
extends RefCounted

## Token transforms packed into one message (topic perfaudit, card netspawn), and the dirty
## set the host's reconciliation sends from.
##
## Bytes: [u8 FORMAT][u16 count, little endian], then per token [u8 id length][network_id,
## UTF-8][9 x f32: position xyz, rotation xyz, scale xyz]: 37 B plus the id (about 57 B for a
## factory id such as "1762650000.123_45678"), against 128 B for one transform RPC with its
## Variant arrays and 180 B per token in the old Variant batch. The receiver gets the
## transform_batch_received shape back (to_batch()), so one client path applies both a drag's
## batch and a reconciliation.
##
## decode() reads untrusted bytes: the header, the count cap, every length against what is
## left, and finite numbers only; a short or malformed message is refused whole.
##
## DirtySet is the reconciliation's memory: the transform it last sent per token. take_changed()
## returns only the tokens that moved by more than EPSILON since, so a table at rest sends
## nothing; the host's slow full-state heartbeat (NetworkTokenSync.HEARTBEAT_TICKS) heals
## whatever a lost message left behind.

const FORMAT := 1
const HEADER_BYTES := 3
const FLOATS := 9
const ENTRY_FIXED_BYTES := 1 + FLOATS * 4
const MAX_ID_BYTES := 255
## Most tokens one message carries; a table past it sends several messages.
const MAX_ENTRIES := 4096
## Largest unreliable message (a drag's batch): under ENet's 1,392 B MTU and Steam's ~1,200 B
## unfragmented payload, about 20 tokens.
const UNRELIABLE_BYTES := 1100
## Two transforms closer than this in every component (metres, radians, scale) are the same.
const EPSILON := 0.0005


## A token's transform as the nine floats an entry carries.
static func floats_of(position: Vector3, rotation: Vector3, scale: Vector3) -> PackedFloat32Array:
	return PackedFloat32Array(
		[
			position.x,
			position.y,
			position.z,
			rotation.x,
			rotation.y,
			rotation.z,
			scale.x,
			scale.y,
			scale.z,
		]
	)


## `transforms` (network_id -> floats_of()) as messages in the dictionary's order, each of at
## most MAX_ENTRIES tokens and, when `max_bytes` is above 0, at most that many bytes (an
## unreliable message stays under the MTU, UNRELIABLE_BYTES, so one lost fragment never loses
## a whole batch). An id longer than MAX_ID_BYTES is left out (no factory makes one).
static func encode(transforms: Dictionary, max_bytes: int = 0) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var bytes := PackedByteArray()
	var count := 0
	for network_id: String in transforms:
		var id_bytes := network_id.to_utf8_buffer()
		var floats: PackedFloat32Array = transforms[network_id]
		if id_bytes.is_empty() or id_bytes.size() > MAX_ID_BYTES or floats.size() != FLOATS:
			continue
		var entry_size := ENTRY_FIXED_BYTES + id_bytes.size()
		var full := count >= MAX_ENTRIES or (max_bytes > 0 and bytes.size() + entry_size > max_bytes)
		if count > 0 and full:
			bytes.encode_u16(1, count)
			out.append(bytes)
			count = 0
		if count == 0:
			bytes = PackedByteArray([FORMAT, 0, 0])
		bytes.append(id_bytes.size())
		bytes.append_array(id_bytes)
		bytes.append_array(floats.to_byte_array())
		count += 1
	if count > 0:
		bytes.encode_u16(1, count)
		out.append(bytes)
	return out


## Reads untrusted `bytes`: {"transforms": network_id -> PackedFloat32Array, "problem": ""},
## or with "problem" saying why it was refused (then "transforms" is {}).
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_BYTES or bytes.decode_u8(0) != FORMAT:
		return _refused("no version %d header" % FORMAT)
	var count := bytes.decode_u16(1)
	if count > MAX_ENTRIES:
		return _refused("%d entries, past %d" % [count, MAX_ENTRIES])
	var out := {}
	var ofs := HEADER_BYTES
	for i in count:
		if ofs >= bytes.size():
			return _refused("entry %d missing" % i)
		var id_size := bytes.decode_u8(ofs)
		if id_size == 0 or ofs + 1 + id_size + FLOATS * 4 > bytes.size():
			return _refused("entry %d short" % i)
		var network_id := bytes.slice(ofs + 1, ofs + 1 + id_size).get_string_from_utf8()
		ofs += 1 + id_size
		var floats := bytes.slice(ofs, ofs + FLOATS * 4).to_float32_array()
		ofs += FLOATS * 4
		for value in floats:
			if not is_finite(value):
				return _refused("entry %d not finite" % i)
		out[network_id] = floats
	if ofs != bytes.size():
		return _refused("%d bytes past the last entry" % (bytes.size() - ofs))
	return {"transforms": out, "problem": ""}


## `transforms` (decode()'s) in NetworkGameSync.transform_batch_received's shape: network_id
## -> {"position", "rotation", "scale"}, each an [x, y, z] array.
static func to_batch(transforms: Dictionary) -> Dictionary:
	var batch := {}
	for network_id: String in transforms:
		var f: PackedFloat32Array = transforms[network_id]
		batch[network_id] = {
			"position": [f[0], f[1], f[2]],
			"rotation": [f[3], f[4], f[5]],
			"scale": [f[6], f[7], f[8]],
		}
	return batch


## True when `a` and `b` (floats_of()) differ by more than EPSILON in any component.
static func differs(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return true
	for i in a.size():
		if absf(a[i] - b[i]) > EPSILON:
			return true
	return false


static func _refused(why: String) -> Dictionary:
	return {"transforms": {}, "problem": why}


## The transform last sent per token (see the header).
class DirtySet:
	extends RefCounted

	var _sent: Dictionary = {}

	## The entries of `current` (network_id -> floats_of()) that are new or moved past EPSILON
	## since they were last taken; remembers them as sent.
	func take_changed(current: Dictionary) -> Dictionary:
		var changed := {}
		for network_id: String in current:
			var floats: PackedFloat32Array = current[network_id]
			if not _sent.has(network_id) or TokenTransformPack.differs(_sent[network_id], floats):
				changed[network_id] = floats
				_sent[network_id] = floats
		return changed

	## Remembers every entry of `current` as sent (a full state just carried them).
	func mark_sent(current: Dictionary) -> void:
		for network_id: String in current:
			_sent[network_id] = current[network_id]

	## Forgets every token not in `alive` (network_id -> anything), so a removed token's
	## memory goes and a re-added one is sent again.
	func retain(alive: Dictionary) -> void:
		for network_id: String in _sent.keys():
			if not alive.has(network_id):
				_sent.erase(network_id)

	## Tokens remembered.
	func size() -> int:
		return _sent.size()

	func clear() -> void:
		_sent.clear()
