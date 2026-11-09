# Map document

`map.ttmap` is the ZIP in a level folder, beside `level.json`, that holds everything authored in
tt-sim for a level. A level can have a Blender `map.glb`, a `map.ttmap`, or both. The long form
is [../ARCHITECTURE.md](../ARCHITECTURE.md) "Map document (map.ttmap)" and "Map Loading Flow";
the network side is [../NETWORKING.md](../NETWORKING.md) "Level Map Files". This doc holds the
system's map and the rules the code keeps (moved from `AGENTS.md` Key Conventions on
2026-10-09).

## Map

| File | Class | Role |
|------|-------|------|
| `resources/map_document.gd` | `MapDocument` | The document: geometry, flat `PackedFloat32Array` rows per palette asset id, `PackedByteArray` masks on the height grid; `erase_filter()` |
| `utils/map_document_io.gd` | `MapDocumentIO` | Reads and writes `map.ttmap`: `write()`, `write_snapshot()`, `read()`, `parse()` |
| `utils/map_document_snapshot.gd` | `MapDocumentSnapshot` | `serialize()` split in two: `capture()` (main thread, copy-on-write copies) and `encode()` (any thread) |
| `utils/map_document_writer.gd` | `MapDocumentWriter` | One document write at a time on a `WorkerThreadPool` task; `write_atomic()` for side files |
| `utils/map_rows_codec.gd` | `MapRowsCodec` | The binary form of the scatter and props rows (`scatter.bin`, `props.bin`) and of the mass anchors (`mass_anchors.bin`): `encode_rows()`, `decode_rows()`, `encode_offsets()`, `decode_offsets()`; reached through `MapDocumentIO.codec()` |
| `utils/map_surfaces_io.gd` | `MapSurfacesIO` | The painted-surface entries (format 2 layout) read and write |
| `utils/surface_entries.gd` | `SurfaceEntries` | The entry byte rules: `canonical()`, `read_sample()`, `write_sample()`, `used_slots()` |
| `resources/level_data.gd` | `LevelData` | `map_document` (`""` or `"map.ttmap"`) beside `map_path`; `has_map()` |
| `scenes/states/playing/level_loader.gd` | `LevelPlayLoader` | `load_map_sources_async`, the play-time load shared by the host and the client download path |
| `utils/glb_utils.gd` | `GlbUtils` | `load_map_async(..., scatter_filter)` |
| `utils/map_file_hash.gd` | `MapFileHash` | The SHA-256 per map file behind the host's `map_hashes` |

## Model

- `MapDocumentIO.write()` is atomic via a `.tmp` rename; `read()` and `parse()` return
  `{document, warnings}`.
- Writing off the main thread (2026-11-09, perfaudit card authsave). `serialize()` is
  `MapDocumentSnapshot.capture(doc).encode()`. `capture()` runs on the main thread: it checks the
  geometry, scalars and object lists (water bodies, crossings, walls, structures, settlements),
  writes their small entries and the manifest (which reads `LibraryRegistry`), and copies every
  packed array and row dictionary with `duplicate()` / `duplicate(true)`. GDScript shares a
  packed array between two variables or properties (an assignment is a reference; probed on
  4.7.2), but `duplicate()` is copy-on-write: 1 us for a 16 MB array, and the live array copies
  itself on its next write (2 ms for 16 MB), so a capture costs about 0.2-0.3 ms at any map size
  and no later edit reaches it. `encode()` reads only the snapshot (heights, masks, biomes,
  surfaces, water grids and rows checks; binary rows, PNGs, anchors; the caps), so it runs on any
  thread, and its entries are byte-identical to the one-call serialize it replaced (checked at
  100 / 200 / 320 ft and on real authoring maps). `MapDocumentWriter` runs `write_snapshot()` (encode,
  ZIP, rename) on a low-priority pool task, one job at a time, with side files written atomically
  after the document; `poll()` / `wait()` hand the job back on the main thread, where
  `MapFileHash.invalidate` runs. Freeing a writer blocks on its job. Authoring's save and
  autosave use it (`AuthoringSaving`, [authoring.md](authoring.md)); every other caller still
  writes synchronously through `write()`. Numbers: `docs/PERFORMANCE.md` "Worker saves".
- The document is untrusted network input. Extend it by adding an entry the reader validates
  with caps before allocating, never by trusting sizes from the archive:
  `ZIPReader.read_file` allocates whatever the central directory claims, and `read()` checks
  that first. Unknown entries are ignored.
- `LevelData.map_document` (`""` or `"map.ttmap"`) sits beside `map_path`. Use `has_map()`
  rather than testing `map_path` for "is this level playable".
- Structures (2026-10-28, card S1): `MapDocument.structures`, saved as `structures.json` (cap 1 MB,
  at most 128, no format bump; `MapStructureIO`), read as untrusted like `walls.json`, with the
  `MapFingerprint` key `structures` and the live-edit kind `structures`. Rules and shape:
  [structures.md](structures.md).
- Fire (2026-10-11, card F1): `MapDocument.fire_mask`, one intensity byte per height sample
  (0 none), saved as `fire.png` (8-bit greyscale, cap 4 MB, no format bump). Read as untrusted:
  the size is checked before the read, a wrong-sized or broken image is skipped with a warning
  (the map loads without fire), any format is taken as greyscale, and an all-zero mask is
  dropped on read and never written (`MapDocumentIO.has_fire`). The ash it leaves is a painted
  surface (`surface_weights`), a separate layer. `MapFingerprint` carries a `fire` key. Drawn by
  `FireField` (`scenes/terrain/fire_field.gd`), which `MapSourceLoader` adds to every map root
  whose ground is the document's; where flames may stand (not wet, not steep) is derived there,
  never saved ([fire.md](fire.md)).

## Rows as binary (format 4, 2026-11-09, perfaudit card mapformat)

`scatter.bin` and `props.bin` replace `scatter.json` and `props.json` (and `mass_anchors.bin`
replaces `mass_anchors.json`). The rows were 93 bytes each as JSON text, 93-99% of a filled map
(3.6 MB at 320 ft, 2.9 MB of it scatter); they are now integer columns that deflate well.
Layout, in `utils/map_rows_codec.gd`'s header: a header (`TTRW`, version 1, asset count), then per
asset an id, a row count and 11 columns, each a byte-plane split (low bytes together, so the
ZIP's deflate sees runs) of zigzag deltas.

- Grid. Every row component is a multiple of `MapDocumentIO.ROW_STEP` = 2^-10 m (about 1 mm,
  0.1 percent of a unit of scale or of a quaternion component, 0.06 degree of rotation). The
  native generator snaps to it (`ScatterNative` passes `row_step`), every GDScript row producer
  does too (`ScatterRows`, `ScatterMass`, `PropRows`, `GroundSnap`, `RockKeep.kept_row`), and a
  power of two is exact in float32, so a snapped row is an exact integer code and the codec is
  lossless for it: a reload returns the rows bit for bit, which the `MapFingerprint` equality of
  a session and its reload needs. A row that is not snapped (a hand-built document) comes back
  snapped, within 0.49 mm and 0.2 degree; saving twice is stable. A quaternion on the grid has
  length 1 only to about 1e-3, so a consumer normalises it before `Quaternion * Vector3`
  (`ScatterRows.row_transform` does).
- Columns. Positions are coded as deltas, since rows are emitted cell by cell; `qw` is
  predicted from the unit-quaternion constraint in integer arithmetic plus one IEEE sqrt
  (platform-deterministic) and only the residue is stored.
- Validation. The reader is bounded before it allocates: each count and length against what is
  left of the buffer, each asset's row count against `MapDocumentIO.MAX_ROWS_PER_ASSET`, the
  shared row budget (`MAX_TOTAL_ROWS`), and the column sizes against the asset's body. A
  truncated or inconsistent entry keeps the assets decoded before the fault and ignores the rest
  with one warning; an asset whose columns do not fit its body is skipped; a row with a value
  beyond `MAX_ROW_COMPONENT` or a rotation that does not normalise is dropped (counted in one
  warning). Nothing allocates from an unchecked size.
- Mass anchors. `mass_anchors.bin` (`TTAN`) is the same column form for the (dx, dz) offsets,
  coded on `MapAnchorsIO.STEP` = 1e-4 m; an asset is kept only when it has two offsets per scatter
  row.
- Format number. 4 (core only) and 5 (another library named) replace 2 and 3 (`MIN_FORMAT` 4,
  `MAX_FORMAT` 5). A document of format 1 to 3 is refused with a warning that names the cause
  ("its scatter rows are JSON, which this version no longer reads. Open it in the older version
  or build the map again"), and an older build refuses a format 4 or 5 the same way, so nothing
  is read as an empty map and lost on the next save. There is no migration: the format 1 surface
  migration went with it.
- Transfer. The late-join file is the `map.ttmap` itself (AssetStreamer zstd over the ZIP), so
  the wire shrinks with the file; there is no separate wire format.

## Painted surfaces (format 2 layout)

The layout below dates from format 2 (2026-10-13, ground-layers card G2) and is unchanged in
formats 4 and 5. It stores hand-painted surfaces as entries, so the
index ground shader (G3) can upload the paint maps verbatim and a map can paint every surface
the palette has.

- Entries. `surfaces.json` lists up to `MapDocument.MAX_SURFACES` = 64 palette surfaces; a
  slot is a position in that list. Each sample keeps up to `SURFACE_ENTRIES` = 4 (index,
  weight) pairs: `surfaces_index.png` holds the four indices (RGBA8 on the sample grid),
  `surfaces_weight.png` their weights. In memory `MapDocument.surface_weights` is the two
  planes back to back (`sample_count() * 8` bytes: the index plane, then the weight plane),
  so a plane uploads or saves as a native slice (`surface_plane()`); `surface_offset(sample,
  entry, plane, count)` is the byte of one entry.
- Canonical form, which every writer keeps and the reader restores: weights high to low (ties
  in any order), each index with weight below `surface_ids.size()`, no slot twice in a sample,
  an unused entry (0, 0), and the weights of a sample summing to at most 255. The remainder is
  automatic ground.
- Painting. `set_surface_weight()` keeps the form: the newest paint wins (the other entries
  scale down to fit), and painting a fifth surface over a sample drops its weakest entry, whose
  weight returns to the automatic ground. `SurfaceStroke` (the Paint tool) inlines the same
  rule per dab. `surface_weight(sample, slot)` reads one slot back; `used_surface_slots()`
  tells which slots carry paint anywhere (one pass), behind `ensure_surface()`,
  `surface_slot_unused()` and `trim_unused_surfaces()`.
- Authoring cap. The tools claim at most `PAINT_SURFACE_LIMIT` = 8 slots (`ensure_surface()`'s
  default limit, the Paint tool's refusal) because today's ground shader draws 8 painted
  layers. `GroundLayerTable.weight_planes()` is the CPU adapter from the entries to those slot
  channels; a received document listing more than 8 draws the rest as nothing. G3 removes the
  adapter and raises the cap to 64.
- Format bump. Format 2 made a format 1 build refuse the document instead of reading it as
  unpainted and dropping the paint on its next save (the additive-entry route of the water,
  crossings and fire entries would do exactly that here, since the format 1 entries are no longer
  written). The format 1 migration (`surfaces.png` / `surfaces_b.png`, `SurfaceEntries.from_slots`)
  was removed with the format 4 bump: this build reads formats 4 and 5 only.
- Validation of a painted-surface document, caps before allocation: both images within 4 MB and the
  size of the sample grid (from the PNG header, before decoding), else the paint is dropped
  with a warning, as it is when one of the pair is missing or `surfaces.json` is malformed
  (more than 64, repeated or malformed ids). Then `SurfaceEntries.canonical()`: an entry naming
  an unlisted slot is dropped with a warning, a slot named twice is merged with a warning, the
  weights are re-sorted quietly, a sum over 255 is scaled with a warning, and loose unused
  entries become (0, 0). Unknown palette surface names stay readable and draw as the fallback
  earth.

## Libraries (format 5, was 3)

Step S4 of the content library ([library.md](library.md)). `manifest.json` gains an optional
`libraries: [{id, version, hash}]`: one entry for every content library whose biome, scatter or
prop asset, or painted surface the map holds, found from the id's prefix (a runtime id of
another library is `<library>__...`; no prefix is `core`). The writer recomputes it at every
save from the document and the libraries served now (`MapLibraries.record_for`), falling back
to what the file claimed for a library that is not served; the reader keeps at most
`MapDocument.MAX_LIBRARIES` = 16 well-formed entries in `MapDocument.libraries` and skips a
malformed one with a warning (a bad record never loses the map).

- Format number. `MapDocument.FORMAT` (4, was 2) while only `core` is named, so a build of the
  same row format opens the map and ignores the key (core ids are unchanged);
  `MapDocument.FORMAT_LIBRARIES` (5, was 3) as soon as another library is named. The reader
  accepts `MIN_FORMAT` = 4 to `MAX_FORMAT` = 5; an older build refuses 5 instead of reading
  prefixed ids as unknown plants and dropping them on its next save (the reasoning of the format
  2 bump). `MapLibraries.format_for` picks the number.
- Reading. `MapSourceLoader.load_async` runs `MapLibraryGate.run` once the document is read:
  aliases first (`MapLibraries.apply_aliases`), then `MapLibraries.check`. A library that is
  not served (not installed, turned off, failed) is missing, one at another major version is
  incompatible; either shows a dialog (library name, the version the map was saved with, why,
  the author) with "Open without those plants" (the library's rows dropped, its biomes pointed
  at the default biome, a toast, the authoring session left unsaved) and Cancel. Without a
  `library_choice` callable the loader opens without those plants and shows the toast.
  `MapDocumentIO.peek_libraries(path)` reads the record from the manifest alone. A map with no
  record counts as core only.
- Multiplayer later: `LibraryRegistry.assets_used_by(doc)` is {library id: asset ids} of the
  rows the map holds, the list a host will send; `record_of` is what a peer compares.

## Runtime

The play-time load, `LevelPlayLoader.load_map_sources_async`, is shared by the host and the
client download path:

1. It reads the document on a worker.
2. It loads the GLB with `MapDocument.erase_filter()` threaded into
   `GlbUtils.load_map_async(..., scatter_filter)`, or builds a bare `LevelMap` with
   `AuthoredTerrain` plus the `AUTHORED_MAP_LIGHTING` map-default ambient.
3. It builds one `AuthoredScatter` for scatter and props within an 8 ms frame budget.
4. It calls `_finalize_map_loading`.

Networking:

- Clients download missing files through the host's variant whitelist (`"map"`, `"ttmap"`)
  and re-download any cached map whose SHA-256 differs from the host's `map_hashes`
  (`MapFileHash`).
- `AssetStreamer` signal listeners must accept the trailing `file_type` argument (Godot 4
  refuses a shorter handler).

## Verification

Unit tests in `tests/unit/`: `test_map_document.gd`, `test_map_document_io.gd`,
`test_map_document_validation.gd` (including formats 1 to 3 refused with a clear message, and
truncated, corrupt and hostile binary rows), `test_map_rows_codec.gd` (snapped rows round trip bit
for bit over random cells, unsnapped rows come back snapped, edge rotations, stable and small
bytes, offsets), `test_map_document_surfaces.gd` (entries, the fifth-surface rule, round trips,
hostile input), `test_map_document_water.gd`, `test_map_document_crossings.gd`, `test_map_document_fire.gd`,
`test_level_map_streaming.gd`; the `libraries` record, format 2 against 3 and the mismatch gate:
the additions in `test_map_document_io.gd` and `test_map_libraries.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
- 2026-10-13: format 2, painted surfaces as top-4 (index, weight) entries with up to 64
  surfaces (ground-layers card G2); format 1 migrates on read.
- 2026-10-24: format 3 and the `libraries` record for maps that use a content library other than
  core (step S4); the mismatch gate on open.
- 2026-11-09: formats 4 and 5, rows as binary columns on the 2^-10 grid (perfaudit card
  mapformat); formats 1 to 3 are refused, the format 1 surface migration is gone.
