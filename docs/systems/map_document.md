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
| `utils/map_document_io.gd` | `MapDocumentIO` | Reads and writes `map.ttmap`: `write()`, `read()`, `parse()` |
| `utils/map_surfaces_io.gd` | `MapSurfacesIO` | The painted-surface entries: format 2 read and write, format 1 read and migration |
| `utils/surface_entries.gd` | `SurfaceEntries` | The entry byte rules: `canonical()`, `from_slots()` (format 1), `read_sample()`, `write_sample()`, `used_slots()` |
| `resources/level_data.gd` | `LevelData` | `map_document` (`""` or `"map.ttmap"`) beside `map_path`; `has_map()` |
| `scenes/states/playing/level_loader.gd` | `LevelPlayLoader` | `load_map_sources_async`, the play-time load shared by the host and the client download path |
| `utils/glb_utils.gd` | `GlbUtils` | `load_map_async(..., scatter_filter)` |
| `utils/map_file_hash.gd` | `MapFileHash` | The SHA-256 per map file behind the host's `map_hashes` |

## Model

- `MapDocumentIO.write()` is atomic via a `.tmp` rename; `read()` and `parse()` return
  `{document, warnings}`.
- The document is untrusted network input. Extend it by adding an entry the reader validates
  with caps before allocating, never by trusting sizes from the archive:
  `ZIPReader.read_file` allocates whatever the central directory claims, and `read()` checks
  that first. Unknown entries are ignored.
- `LevelData.map_document` (`""` or `"map.ttmap"`) sits beside `map_path`. Use `has_map()`
  rather than testing `map_path` for "is this level playable".
- Fire (2026-10-11, card F1): `MapDocument.fire_mask`, one intensity byte per height sample
  (0 none), saved as `fire.png` (8-bit greyscale, cap 4 MB, no format bump). Read as untrusted:
  the size is checked before the read, a wrong-sized or broken image is skipped with a warning
  (the map loads without fire), any format is taken as greyscale, and an all-zero mask is
  dropped on read and never written (`MapDocumentIO.has_fire`). The ash it leaves is a painted
  surface (`surface_weights`), a separate layer. `MapFingerprint` carries a `fire` key. Drawn by
  `FireField` (`scenes/terrain/fire_field.gd`), which `MapSourceLoader` adds to every map root
  whose ground is the document's; where flames may stand (not wet, not steep) is derived there,
  never saved ([fire.md](fire.md)).

## Painted surfaces (format 2)

Format 2 (2026-10-13, ground-layers card G2) stores hand-painted surfaces as entries, so the
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
- Format bump. The manifest `format` is 2, and the reader accepts 1 and 2. A format 1 build
  refuses a format 2 document instead of reading it as unpainted and dropping the paint on its
  next save (the additive-entry route of the water, crossings and fire entries would do exactly
  that here, since the format 1 entries are no longer written).
- Format 1 migration (`MapSurfacesIO`, `SurfaceEntries.from_slots`): `surfaces.png` (slots 0-3
  in R, G, B, A) and `surfaces_b.png` (slots 4-7), at most 8 surfaces. Per sample, the non-zero
  listed slots high to low, the strongest four kept and scaled to keep the sample's painted
  total (capped at 255); one warning counts the samples that painted five or more. The old
  fixes stay: paint in an unlisted slot cleared, an over-full sample scaled, a missing
  `surfaces_b.png` keeps slots 0-3. A format 1 document saves as format 2.
- Validation of a format 2 document, caps before allocation: both images within 4 MB and the
  size of the sample grid (from the PNG header, before decoding), else the paint is dropped
  with a warning, as it is when one of the pair is missing or `surfaces.json` is malformed
  (more than 64, repeated or malformed ids). Then `SurfaceEntries.canonical()`: an entry naming
  an unlisted slot is dropped with a warning, a slot named twice is merged with a warning, the
  weights are re-sorted quietly, a sum over 255 is scaled with a warning, and loose unused
  entries become (0, 0). Unknown palette surface names stay readable and draw as the fallback
  earth. Format 1 entries in a format 2 document (and the reverse) are ignored.

## Libraries (format 3)

Step S4 of the content library ([library.md](library.md)). `manifest.json` gains an optional
`libraries: [{id, version, hash}]`: one entry for every content library whose biome, scatter or
prop asset, or painted surface the map holds, found from the id's prefix (a runtime id of
another library is `<library>__...`; no prefix is `core`). The writer recomputes it at every
save from the document and the libraries served now (`MapLibraries.record_for`), falling back
to what the file claimed for a library that is not served; the reader keeps at most
`MapDocument.MAX_LIBRARIES` = 16 well-formed entries in `MapDocument.libraries` and skips a
malformed one with a warning (a bad record never loses the map).

- Format number. 2 while only `core` is named, so an older build opens the map and ignores the
  key (core ids are unchanged); 3 (`MapDocument.FORMAT_LIBRARIES`) as soon as another library is
  named. The reader accepts 1 to `MapDocument.MAX_FORMAT` = 3; an older build refuses 3 instead
  of reading prefixed ids as unknown plants and dropping them on its next save (the reasoning
  of the format 2 bump). `MapLibraries.format_for` picks the number.
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
`test_map_document_validation.gd`, `test_map_document_surfaces.gd` (format 2: entries, the
fifth-surface rule, round trips, hostile input), `test_map_document_surfaces_format1.gd` (the
migration), `test_map_document_water.gd`, `test_map_document_crossings.gd`, `test_map_document_fire.gd`,
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
