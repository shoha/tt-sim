extends RefCounted

## Writes ZIP archives byte by byte, for the tests of LibraryImporter: ZIPPacker only writes
## well-formed archives, and the hostile cases need entries it will not (a symbolic link's mode,
## an entry whose directory claims another size, an encrypted flag, a backslash in a name).
## Entries are STORED (method 0) unless an entry says otherwise; the CRC is real. Not a test
## file itself (GUT only collects test_*.gd). Preload it as a const.
##
## An entry is a Dictionary: {name, data (PackedByteArray or String), and optionally
## method (claimed, default 0), flags, host (the "version made by" host byte, 3 is Unix),
## external (the attribute word), size (the uncompressed size the directory CLAIMS), packed (the
## compressed size it claims)}.

const LOCAL_SIGNATURE := 0x04034b50
const CENTRAL_SIGNATURE := 0x02014b50
const END_SIGNATURE := 0x06054b50

static var _crc_table: PackedInt64Array = PackedInt64Array()


## The archive holding `entries`, in order.
static func build(entries: Array) -> PackedByteArray:
	var out := PackedByteArray()
	var central := PackedByteArray()
	for item: Dictionary in entries:
		var name_bytes := String(item["name"]).to_utf8_buffer()
		var data := _bytes(item.get("data", PackedByteArray()))
		var method := int(item.get("method", 0))
		var flags := int(item.get("flags", 0))
		var crc := crc32(data)
		var size := int(item.get("size", data.size()))
		var packed := int(item.get("packed", data.size()))
		var offset := out.size()
		_u32(out, LOCAL_SIGNATURE)
		_u16(out, 20)
		_u16(out, flags)
		_u16(out, method)
		_u16(out, 0)
		_u16(out, 0x21)
		_u32(out, crc)
		_u32(out, data.size())
		_u32(out, data.size())
		_u16(out, name_bytes.size())
		_u16(out, 0)
		out.append_array(name_bytes)
		out.append_array(data)
		_u32(central, CENTRAL_SIGNATURE)
		_u16(central, (int(item.get("host", 0)) << 8) | 20)
		_u16(central, 20)
		_u16(central, flags)
		_u16(central, method)
		_u16(central, 0)
		_u16(central, 0x21)
		_u32(central, crc)
		_u32(central, packed)
		_u32(central, size)
		_u16(central, name_bytes.size())
		_u16(central, 0)
		_u16(central, 0)
		_u16(central, 0)
		_u16(central, 0)
		_u32(central, int(item.get("external", 0)))
		_u32(central, offset)
		central.append_array(name_bytes)
	var central_at := out.size()
	out.append_array(central)
	_u32(out, END_SIGNATURE)
	_u16(out, 0)
	_u16(out, 0)
	_u16(out, entries.size())
	_u16(out, entries.size())
	_u32(out, central.size())
	_u32(out, central_at)
	_u16(out, 0)
	return out


## Every file under `folder` as entries named relative to it, prefixed with `prefix` ("lib/").
static func entries_of(folder: String, prefix: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect(folder, "", prefix, out)
	return out


static func _collect(
	folder: String, relative: String, prefix: String, out: Array[Dictionary]
) -> void:
	var here := folder if relative == "" else folder.path_join(relative)
	var files := Array(DirAccess.get_files_at(here))
	files.sort()
	for file_name: String in files:
		var name := file_name if relative == "" else relative + "/" + file_name
		out.append(
			{"name": prefix + name, "data": FileAccess.get_file_as_bytes(here.path_join(file_name))}
		)
	var folders := Array(DirAccess.get_directories_at(here))
	folders.sort()
	for sub: String in folders:
		_collect(folder, sub if relative == "" else relative + "/" + sub, prefix, out)


## Writes the archive of `entries` to `path`.
static func write(path: String, entries: Array) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(build(entries))
	file.close()


static func crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for _bit in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
			_crc_table[i] = c
	var crc := 0xFFFFFFFF
	for byte in data:
		crc = _crc_table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


static func _bytes(data: Variant) -> PackedByteArray:
	return (data as String).to_utf8_buffer() if data is String else (data as PackedByteArray)


static func _u16(buffer: PackedByteArray, value: int) -> void:
	buffer.append(value & 0xFF)
	buffer.append((value >> 8) & 0xFF)


static func _u32(buffer: PackedByteArray, value: int) -> void:
	_u16(buffer, value & 0xFFFF)
	_u16(buffer, (value >> 16) & 0xFFFF)
