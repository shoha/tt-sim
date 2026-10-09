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
`test_map_document_validation.gd`, `test_map_document_surfaces.gd`,
`test_map_document_water.gd`, `test_map_document_crossings.gd`, `test_level_map_streaming.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
