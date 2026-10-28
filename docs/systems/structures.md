# Structures

Status: data layer only (2026-10-28, topic `structures`, card S1, branch `structures-s1`). A
structure is a building recorded as a library recipe plus the author's inputs; every peer rebuilds
it, as walls, crossings and avatar tokens are. This card adds the record, the `structures.json`
entry of `map.ttmap`, the editor's data calls, the live edit and the fingerprint key. There is no
geometry, no node, no tool and no library kind yet: the cards that add them grow this page. The
design is the gitignored `docs/plans/2026-10-28-structures/design.md`; the contract with procgen and
structgen is `ASSET_PIPELINE.md` section 12.

## Data

`Structure` (`resources/structure.gd`) is one structure in `MapDocument.structures` (at most
`MAX_STRUCTURES` = 128):

| Field | Meaning |
|-------|---------|
| `id` | 1..255, stable, unique in the document |
| `recipe` | `<library id>:<structure id>`, the cross-library reference grammar (`LibraryIds`: library `[a-z][a-z0-9_-]{1,31}`, structure `[a-z][a-z0-9_]*` without `__`); at most 100 characters. Whether the recipe exists is the registry's question at build time |
| `footprint` | the closed plan polygon in map XZ metres, 3 to 24 points, `PackedVector2Array` (float32); edge 0 (point 0 to point 1) is the front and carries the door |
| `seed_value` | 0..1e9, stored, never derived from an engine hash |
| `params` | only the values that differ from the recipe's interface defaults: at most 16 entries, name `[a-z][a-z0-9_]*` (32 characters), a bool or a finite number within 1e6, rounded to 0.01 |
| `style` | palette biome id whose rock tints the walls, or "" (as `Wall.style`) |

There is no transform and no baked mesh. Position and rotation are the points, and height is read
from the document's ground when built (the Build card), exactly as a wall's is.

## The map entry

`MapStructureIO` (`utils/map_structure_io.gd`) owns `structures.json`, in the way `MapWallIO` owns
`walls.json`; `MapDocumentIO` owns the archive, the 1 MB entry cap and the warning log:

```
{"version": 1, "structures": [
  {"footprint": [[-3.0, -2.0], [3.0, -2.0], [3.0, 2.0], [-3.0, 2.0]],
   "id": 1, "params": {"floors": 2.0, "height": 2.6}, "recipe": "core:cottage",
   "seed": 482113907, "style": ""}]}
```

- **Reading is untrusted.** A structure is skipped with a warning when: its id is outside 1..255 or
  repeated; the recipe is not a well formed `<library>:<structure>`; the footprint has fewer than 3
  or more than 24 points (checked on the raw list before any point is built), a point NaN, Inf or
  off the map, or a bounding box wider than `MAX_SPAN_M` (64 m); the plan rules refuse it (below);
  the seed is not a whole number in 0..1e9; params are not an object of at most 16 well named
  numbers and bools; the style is not a short string. Lists past 128 are cut with one warning.
  `structure_problem()` is the one rule set, shared by the reader, the writer and the editor.
- **The writer refuses** a document breaking any rule (`MapDocumentIO.write` fails, as for walls).
  A document with no structure writes no entry; an older build ignores the entry (and drops the
  buildings on its next save, accepted as for walls).
- **Byte-identical re-save.** The text is written with sorted keys and the default float
  precision. Footprint points are float32, which print with 14 digits and parse back to the same
  float32 (measured 2026-10-28 in the design probe: 0 mismatches in 20000 points, while float64
  values mismatched 1838 times), so they are never rounded by the I/O. Numeric params are float64
  and are rounded to 0.01 on every read and write. `test_map_document_structures.gd` checks the
  entry's bytes across a save and load, and 40 random plans (snapped and unsnapped).
- **The plan rules are not here yet.** `MapStructureIO._plan_problem()` is the seam for procgen's
  `ProcgenPlan` (simple polygon, edge length, corner angle), which did not exist in the procgen pin
  (`dcf0c4d`) when S1 was written. It accepts everything until the pin moves; S2 wires it in. Until
  then only the record's caps run (count, finite, on the map, span).

`MapLibraries.record_for` and `LibraryRegistry.assets_used_by` do not count structure refs yet
(the library card does that); a map with a non-core recipe will then list its library.

## Editor and history

`StructureEditor` (`scenes/states/authoring/structure_editor.gd`, `AuthoringEditor.structures`):
`list()`, `get_structure()`, `add()` (a new id is taken from `MapDocument.next_structure_id()`; an
existing id replaces; -1 with `last_refusal` `full` or `invalid`), `remove()` and `apply_list()`.
Every change is one history entry holding the whole list before and after. `apply_list()` is the
one method the history's undo and redo and a live edit call; it only sets the document's list now,
and the Build card refreshes the nodes from it.

## Live edit and fingerprint

- The live-edit kind `"structures"` (`LiveEditCodec`, `LiveEditReader`) carries
  `[structure JSON forms, area]`, the whole list, as walls do; the reader runs
  `MapStructureIO.parse_list`, so a hostile peer's list is refused with the same rules as a file.
  It takes no direction: an undo is the same op with the list before. 128 structures are at most
  about 128 KB of JSON-shaped values, sent once per committed edit, never per drag frame.
- `MapFingerprint` has the key `structures`: `record <id> <recipe> <sha prefix of the record's
  JSON>` per document record (moves with any change of footprint, seed, param, style or recipe
  before geometry exists), plus `node <name> <verts> <aabb>` per child of `AuthoredStructures`
  once the Build card adds that node. Design note: the design named only the node part; the record
  part is what makes the key useful now.

## Not yet

- Geometry (`StructureGeometry`), the nodes and collision (`AuthoredStructures`), the load prep.
- The library kind (`structures/` folder, index, registry, partial bundles), so recipes cannot be
  resolved yet; `ProcgenPlan` for the footprint rules.
- The tool, the palette, handles, variants; retiring `Wall.Kind.BUILDING`.
- Scatter clearance under the footprint, following sculpt and water edits.

Tests: `tests/unit/test_map_document_structures.gd` (in the authoring subset).
