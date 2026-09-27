class_name ZipEntrySizes
extends RefCounted

## The declared uncompressed size of every entry of a ZIP archive, read from its central
## directory without trusting anything else. MapDocumentIO uses it as its ZIP bomb guard.
##
## The one allocation ZIPReader makes on the archive's say-so is read_file(), which sizes
## its buffer from the entry's declared uncompressed size, and ZIPReader has no way to ask
## for that size first (probed on 4.7.1: its methods are open, close, get_files,
## read_file, file_exists, get_compression_level). A 432-byte archive whose headers claim
## 400 MB made read_file allocate 400 MB before failing. So a reader parses the central
## directory here first and only calls read_file on an entry whose declared size is
## within its cap.
##
## Record selection mirrors minizip (thirdparty/minizip/unzip.c), which is what ZIPReader
## sizes read_file() from: the end-of-central-directory record is the last signature in
## the tail, the directory is taken to end where that record starts (minizip's
## byte_before_the_zipfile correction), and a Zip64 locator that points at a Zip64 record
## makes minizip use that instead, so such an archive is refused rather than parsed with
## different numbers. ZIPPacker never writes Zip64 for entries under 4 GB.

const _EOCD_SIGNATURE := 0x06054b50
const _EOCD_SIZE := 22
const _MAX_ZIP_COMMENT := 65535
const _CENTRAL_SIGNATURE := 0x02014b50
const _CENTRAL_HEADER_SIZE := 46
const _ZIP64_LOCATOR_SIGNATURE := 0x07064b50
const _ZIP64_EOCD_SIGNATURE := 0x06064b50


## {"sizes": Dictionary (entry name -> declared bytes, the larger one for a repeated
## name) or null, "error": String}. `error` says why `sizes` is null: the file is missing,
## over `max_archive_bytes`, not a plain ZIP, Zip64, or its directory is over
## `max_entries` records or `max_directory_bytes`, inconsistent or malformed.
static func read(
	path: String, max_archive_bytes: int, max_entries: int, max_directory_bytes: int
) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("%s cannot be opened" % path)
	var length := file.get_length()
	if length > max_archive_bytes:
		return _failure("%s is %d bytes, over the cap of %d" % [path, length, max_archive_bytes])
	var tail_start := maxi(0, length - (_EOCD_SIZE + _MAX_ZIP_COMMENT))
	file.seek(tail_start)
	var tail := file.get_buffer(length - tail_start)
	var eocd := _last_signature(tail, _EOCD_SIGNATURE, _EOCD_SIZE)
	if eocd < 0 or eocd + _EOCD_SIZE + tail.decode_u16(eocd + 20) != tail.size():
		return _failure("%s is not a ZIP archive" % path)
	if _has_zip64_record(file, tail):
		return _failure("%s is a Zip64 archive, which map documents never are" % path)
	var count := tail.decode_u16(eocd + 10)
	var directory_size := tail.decode_u32(eocd + 12)
	var directory_end := tail_start + eocd
	if count > max_entries or directory_size > max_directory_bytes:
		return _failure("%s has an oversized ZIP directory" % path)
	if tail.decode_u32(eocd + 16) + directory_size > directory_end:
		return _failure("%s has an inconsistent ZIP directory" % path)
	file.seek(directory_end - directory_size)
	var sizes: Variant = parse_central_directory(file.get_buffer(directory_size), count)
	if sizes == null:
		return _failure("%s has a malformed ZIP directory" % path)
	return {"sizes": sizes, "error": ""}


## Name -> declared uncompressed size for `count` central-directory records, or null
## when a record is truncated or carries the wrong signature. Pure.
static func parse_central_directory(directory: PackedByteArray, count: int) -> Variant:
	var sizes := {}
	var at := 0
	for _record in count:
		if at + _CENTRAL_HEADER_SIZE > directory.size():
			return null
		if directory.decode_u32(at) != _CENTRAL_SIGNATURE:
			return null
		var declared := directory.decode_u32(at + 24)
		var name_length := directory.decode_u16(at + 28)
		var name_end := at + _CENTRAL_HEADER_SIZE + name_length
		if name_end > directory.size():
			return null
		var entry_name := (
			directory.slice(at + _CENTRAL_HEADER_SIZE, name_end).get_string_from_utf8()
		)
		sizes[entry_name] = maxi(sizes.get(entry_name, 0), declared)
		at = name_end + directory.decode_u16(at + 30) + directory.decode_u16(at + 32)
	return sizes


static func _failure(message: String) -> Dictionary:
	return {"sizes": null, "error": message}


## Offset of the last occurrence of a little-endian u32 `signature` in `bytes` that has
## at least `record_size` bytes after it, or -1.
static func _last_signature(bytes: PackedByteArray, signature: int, record_size: int) -> int:
	for i in range(bytes.size() - record_size, -1, -1):
		if bytes.decode_u32(i) == signature:
			return i
	return -1


## True when the tail holds a Zip64 end-of-directory locator (the last one, as minizip
## searches) that points at a real Zip64 end-of-directory record.
static func _has_zip64_record(file: FileAccess, tail: PackedByteArray) -> bool:
	var locator := _last_signature(tail, _ZIP64_LOCATOR_SIGNATURE, 20)
	if locator < 0:
		return false
	var record := tail.decode_u64(locator + 8)
	if record < 0 or record + 4 > file.get_length():
		return false
	file.seek(record)
	return file.get_32() == _ZIP64_EOCD_SIGNATURE
