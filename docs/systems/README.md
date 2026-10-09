# System docs

One document per system, each the single home for that system's map (which files and classes
make it up) and its model (the rules, constants and invariants the code keeps). `ARCHITECTURE.md`
keeps one paragraph and a link per system, so a reader coming from the architecture overview
finds the system by name and follows the link; `AGENTS.md` holds rules and pointers and never a
system's map. When a change touches one of these systems, the system doc is what gets updated;
the paragraph in `ARCHITECTURE.md` changes only when the system's one-paragraph description or
its main classes change.

Every system doc follows the same headings, in this order:

1. `# <System>`, then one paragraph of purpose that states the visual or authoring bar the
   system is judged against.
2. `## Map`: a table of file, class and role. Every file the system owns or materially extends.
3. `## Model`: the rules, constants and invariants, with the measured numbers that justify them.
4. `## Runtime`: nodes, meshes, shaders and the load path; what every peer builds from the
   document.
5. `## Authoring`: the editor API, the tools that call it, undo and erase.
6. `## Verification`: unit tests by file, render jobs by name, and the `PERFORMANCE.md` sections
   that pin the system's numbers, as relative links (`../PERFORMANCE.md`).
7. `## Open work`: one line pointing at `../MAP_AUTHORING.md` "Open work". The hub owns the
   list; a system doc never duplicates it.
8. `## History`: one line per phase, with the commit hashes.

Documents here:

- [water.md](water.md): the water model and flow bake, authored water at runtime, carving and
  wet dressing, rivers and ponds past the map edge.
- [waterfalls.md](waterfalls.md): the fall-or-riffle rule, the plan-time lips and set-back, the
  fall carve, the curtain / foam ring / mist mesh and shader, the fall material.
- [crossings.md](crossings.md): plank bridges, stepping stones, stone arches and fords,
  including the refusal by a waterfall and the per-crossing rebuild cache.
- [landforms.md](landforms.md): the starting landforms a new map opens with (Valley, Hilltop,
  Terraces, Lakeshore, Gorge): the seeded frame, the shared steps, each recipe, the stage and
  the open path.
- [palette.md](palette.md): the built-in palette (`PaletteLibrary`): validation, read access,
  `resolve()`, the import sidecars.
- [map_document.md](map_document.md): `map.ttmap` (`MapDocument`, `MapDocumentIO`), levels
  with `map.glb`, `map.ttmap` or both, the play-time load and map downloads.
- [scatter.md](scatter.md): the scatter generator (region independence, thinning, density
  response, clumps) and authored scatter (per-cell builds, worker regeneration, warm-up).
- [authored_terrain.md](authored_terrain.md): the ground of a map without `map.glb`: chunks,
  collision, ground layers, the self-dressing rules, height and ground refresh calls.
- [authoring.md](authoring.md): authoring mode (entry, controller, new maps, save, autosave,
  undo) and the brushes (mask, Paint and Sculpt strokes, flush, history).

The last five were moved out of `AGENTS.md` Key Conventions on 2026-10-09 and are first cuts:
they hold the map and the rules, use only the headings they have content for, and leave the
long form in their `ARCHITECTURE.md` sections until that is migrated here.
