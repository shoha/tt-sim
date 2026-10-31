# Structure performance (measured 2026-10-30, card struct_perf)

What building, placing and drawing structures costs, and where the time goes. Numbers are from the
render-job harness and headless probes on a shared GPU (40 to 42 percent busy), with other agents
running: indicative, not the pinned `docs/PERFORMANCE.md` procedure. Re-measure before relying on a
number for a decision. Probes: render-job action `village` (`tools/render_jobs/probes/structures.gd`)
and job `tools/render_jobs/jobs/struct_perf_village.json` (needs a 320 ft map: the largest map is 97 m).

## Build cost per structure

`StructureGeometry.build_one` (evaluate, split, paint, walkable, dressing) at each structure's default
size, median of 5 after a warm-up, 64 core structures:

- Triangles: 147,005 in all, median 1,838, max 6,696 (`coaching_inn`). None near the 12,000 soft budget.
- Time: mean 41 ms, median 35, p90 68, min 12. Only `hof_farm` (126) and `coaching_inn` (110) pass 100 ms.
  Cost follows facade detail and layout, not triangle count alone (about 17 ms per 1,000 triangles).
- Stage split, cottage (41 ms): evaluate 23.5, paint 6.4, dressing 5.4, split 4.7. A 20 by 16 m `coaching_inn`
  (211 ms): evaluate 125, paint 34, split 22, dressing 9, recipe parse 4.6 (repeated on every build).
- Procgen `evaluate_structure` is about 60 percent of a build, so the largest remaining gain is in procgen
  (facade, layout and courtyard nodes), not in the host.
- `StructurePaint.paint` is 15 to 20 percent of a build and `split_surface` about 10 percent, both
  per-vertex GDScript loops that could be vectorised without changing output.

## The live drag preview

`StructureEditor.preview` -> `AuthoredStructures.refresh`. The build is already off the main thread (one
`WorkerThreadPool` task per structure, results cached by key). The main thread pays `keys_of`,
`ground_snapshot` and the node install: 0.6 ms for a cottage and 2 ms for a 20 by 16 m courtyard with one
structure standing, and `keys_of` scales with the number of structures (0.36 ms each, 36 ms at 100).

The real stall was feedback: the old code dropped the running build for every newer edit, so a build
slower than the drag interval never landed. Over 4 s of drag at 10 Hz, `coaching_inn` landed 0 previews
(a 4 s gap), `castle_keep` 8. Now the newest edit waits behind the running build, so they land 19 and 35
times, with the longest gap 0.34 s and 0.31 s. A test fails on the old behaviour.

## Load, instancing, materials, draw calls

- Materials are shared, one per (kind, role, style, tone): 24 for 100 structures. Shader count does not
  grow with the number of structures.
- No instancing is possible as built: every structure has its own footprint, seed, yaw and ground, so all
  mesh instances are unique (7.1 per structure, surfaces already merged by role and kind).
- No LOD and no culling beyond the engine's frustum culling.
- 100 structures add about 700 visible draws and 440 shadow draws, and cost 0.4 ms of CPU and no GPU time
  (their footprints clear scatter, so a village is cheaper than the forest it replaces). Merging or LOD
  would save at most that 0.4 ms and give up per-structure picking, so it is not worth doing now. Revisit
  if 128 or more structures run on the Mobile renderer.
- Load (struct_perf2): `StructureGeometry.build` now builds a document's structures as a
  `WorkerThreadPool` group in document order: 100 structures 3.1 s on one thread, 0.90 s on 6 threads
  (`AuthoredStructures.load_threads()`, a quarter of the logical cores). More threads are slower (1.16 s
  on 3, 1.37 s on 12 or 24): builds allocate heavily and fight over the allocator. Digests are identical
  to the sequential build (test). Probe: job `struct_perf2_load_seq` / `_par`, action `load_build`.
- Memory: static 446 MB for an empty map and about 530 MB with 100 structures (+83; main at the same
  commit measured +46 in the same job, an unexplained difference that does not depend on the build cap or
  the key memo). The 882 MB peak of the first report is not reproduced: the peak is about 530 MB in both.
  The 48-entry parts cache holds only 13 MB of arrays and collision faces (measured), so dropping
  `arrays` would save at most 13 MB and make undo rebuild nodes from nothing: not done.
- `StructureWalkable` collision: 570 faces across all 64 structures (max 234) against 20,286 for the hull
  collision, and 0.6 to 1.9 ms per structure on the worker. Negligible.

## Adding a structure while many stand

Profiled (struct_perf2, job `struct_perf2_add`): of 2.3 s for 100 adds, `keys_of` was 2.0 s, scatter
`request_region` 23 ms, the history and area work 11 ms. Two causes:

- Each add re-sampled the ground under every standing structure, and every add changes the keys of the
  dozen structures around it. `StructureGeometry.keys_memoised` (used by `AuthoredStructures.refresh`)
  keeps each structure's key and its ground samples between refreshes. A hash of the heights, pond mask
  and every water body field (`ground_fingerprint`, 0.17 ms for a 97 m map) is part of the signature, so
  any ground edit invalidates it by content and no writer of those public fields has to bump a version
  counter. Tests cover sculpts, in-place height writes, rivers, ponds and the pond mask.
- With builds on every core the main thread ran 14 times slower (a 4 ms refresh took 57 ms; builds
  allocate heavily and share cores and locks with it). `AuthoredStructures.max_running()` now lets a
  sixth of the logical cores build at once (4 on 24), and a build still queued is replaced by the newer
  edit instead of running first.

100 sequential adds, queue time on the main thread: 2.3 to 3.0 s before, 0.49 s after (2 to 8 ms per add,
was up to 60 ms at 90 standing). Time until the last of the 100 builds lands: 1.2 s before, 0.8 s after
the queued-replace change. The remaining growth with N is the signature loop (about 4 ms at 100).

## Third round: 128 structures (perf3, 2026-10-30)

Job `tools/render_jobs/jobs/perf3_village.json`, probe `probes/structure_perf3.gd`: 128 structures (the
cap), the 64 core recipes twice with an ornament mix (ivy, flower boxes, banner, vane, awning, sign),
97 m map, 1920 by 1080, vsync off. Indicative only: GPU 37 to 42 percent busy before the run, a procgen
agent running headless tests on the same machine, one run each (run-to-run spread of the small CPU
numbers was about 1.7 times). Before = main at `ee56d459`; after = this branch up to the neighbour grid
and the decor plan and install queue (the 8 m neighbour range came after the after run, see below).

| Measure | Before | After |
|---|---|---|
| Empty map, CPU / GPU median ms | 5.26 / 4.76 | 5.33 / 4.80 |
| 128, home zoom (60), CPU median / p95 / worst ms | 7.20 / 10.55 / 13.06 | 6.65 / 9.71 / 12.21 |
| 128, home zoom, GPU median ms | 4.47 | 4.57 |
| 128, close zoom (20), CPU / GPU median ms | 4.08 / 3.54 | 4.11 / 3.57 |
| Draws, home zoom (empty map 3,396) | 4,755 (+1,359) | 4,791 |
| Shadow draws (empty 923) | 1,618 | 1,622 |
| Primitives (empty 1.67 M) | 2.13 M | 2.13 M |
| Static memory (empty 471.6 MB) / video | 571.8 / 1,689.8 MB | 573.2 / 1,690.4 MB |
| Load of 128: worker build / main-thread `create` | 1,094 / 753 ms (5.9 ms each) | 1,157 / 578 ms (4.5 ms each) |
| Add at 100 standing, main thread per add, median / max | 109 / 139 ms | 36 / 48 ms |
| The 128th add / edit (turn) / removal, main ms | 150.7 / 71.9 / 171.5 | 39.5 / 31.8 / 61.0 |
| The 129th add (refused at the cap) | 0.2 ms | 0.2 ms |
| Landing of the 128th / of an edit | 1.7 s / 1.2 s | 1.9 s / 1.5 s (workers busy with the neighbours) |
| Hitch: 20 adds in 10 s at 100 standing: frames over 20 ms / over 33 ms / worst | 33 / 26 / 159.8 ms | 22 / 20 / 62.9 ms |
| Consumers, all on screen: Wind.publish / 40 vanes / 2 mills | 43 us / 1.30 ms / 76 us | 25 us / 0.75 ms / 37 us |

Ranked hotspots at village scale, by what a player feels:

1. **Every add, edit and removal cost 90 to 170 ms on the main thread at 120 standing**, not the 2 to 8
   ms of the second round (that job had no ornaments and fewer neighbours). `StructureDressing.neighbours`
   tested every structure against every other (14,400 pair tests, 91 ms measured in the render run) on
   every refresh, and `key_of` ran it again for each changed structure. Fixed: a uniform grid
   (`neighbour_grid`, 8 m cells) and the list passed into `key_of`; a warm `keys_memoised` at 126
   structures is 3.9 ms (was 93 to 97), a cold one 30 ms (was 390 to 470). Same lists, same order (test).
2. **One add rebuilt about 19 neighbours.** A yard reads the footprints within `NEIGHBOUR_RANGE_M` (14 m)
   and the key includes them, so each add queued 19 builds of 40 to 130 ms; with four workers busy the
   main thread stays contended (the remaining 36 ms per add above is mostly that, not code on the main
   thread). A yard reaches `REACH_MAX_M + NEIGHBOUR_CLEAR_M` = 7.5 m at most, so the range is now 8 m
   (about 8 neighbours at 7.3 m spacing). Checked: a dense 8 by 8 village (8.5 m spacing) gives the
   same digest of every mesh and yard at 8 m and at 14 m. This came after the after run, so the table
   does not include it; the render job should be repeated for it.
3. **Vanes: 32 us each when all stand on screen** (40 vanes 0.75 to 1.3 ms a frame; they only run on
   screen). Mills 19 to 38 us each. Wind itself 25 to 43 us. Particles were not measured.
4. **Draws: about 10.6 visible and 5.4 shadow draws per structure**, +1.3 to 1.9 ms CPU and no GPU time
   (the GPU median did not move). Not merged: a 30 percent cut would save about 0.5 ms and cost per-
   structure picking and edits; the earlier verdict stands (item 5 of the card, not prototyped).
5. **Main-thread node making on a load: 4.5 ms per structure** (586 ms for 128 in one frame). Meshes,
   materials, collision shapes and the decor bake, not the decor placement, dominate; the card's target
   of 1.5 ms per building was not met (5.9 to 4.5 ms). `AuthoredStructures.create(..., staged = true)`
   spreads them (not wired into `MapSourceLoader`, see below).
6. `StructurePaint.paint` and `split_surface` (15 to 20 percent and 10 percent of a worker build):
   not vectorised in this round (no budget left); the workers are not the felt cost.

What changed in the code:

- **Decor plan on the worker** (`StructureDecor.plan`, `parts.decor_plan`, not in `digest_of`): placement,
  the 4,500 triangle cap and the grouping run in `build_one` from a `info` dictionary (rows, plant
  triangle costs and their hash `sig`) that `AuthoredStructures._decor_info` makes once per batch on the
  main thread. `_add_decor` uses the plan, or makes it again when it is missing or its `sig` is stale (a
  loader's parts, a synchronous build, a changed library); `create` places a loader's missing plans as
  a worker group. Tests: equal to the old path (ids, placements, triangles), deterministic, not in the
  digest, same nodes with a plan, without and with a stale one.
- **Install queue** (`StructureInstallQueue`, `INSTALL_BUDGET_MS` 3): a landed build waits and `_process`
  makes nodes until 3 ms are spent (at least one a frame). Order: `prioritize(id)`, then an install that
  replaces a standing node (an edit or a drag preview), then the newest build, so the placement ghost
  and the selected structure do not wait behind a burst. `flush()` makes all at once. Cache hits in
  `refresh` still install at once. The load keeps the synchronous `create` (a token that lands on a
  roof needs its collision at once); `staged` is there for the owner to wire if a loading screen can
  wait for `pending_count() == 0`.
- Hitch result: the worst frame while 20 structures were added fell from 160 to 63 ms and the frames
  over 20 ms from 33 to 22. It is not zero: the remaining hitches are the main thread waiting on the
  allocator while four workers rebuild neighbours, and the add itself (36 ms).

## Fourth round: the staged load (perf4, 2026-10-31)

A play load now makes the structures' nodes a few a frame. `MapSourceLoader.staged_structures` (set by
`LevelPlayLoader.load_map_sources_async` only; authoring and tools keep the synchronous create) passes
`staged = true` to `AuthoredStructures.create`, and `LevelPlayLoader._finalize_map_loading` then waits in
`StructureLoadWait.wait_async` until `pending_count() == 0`, reporting "Building structures... (n/total)" on
the loading bar (the 0.05 to 0.2 share). So play never starts with a structure missing, the grid-ground fit
and the token grounding see every roof's collision, and a superseded load cancels the queue
(`StructureLoadWait.cancel`). `StructureLoadWait.settle` installs the queue at once before an edit
(`StructureEditor.apply_list`), so a refresh never rebuilds a structure whose finished build is queued. The
wait is bounded: at least one structure a frame, and after `MAX_FRAMES` (600) or when the node is outside
the tree the rest is made at once. (The client download path called `_finalize_map_loading` without awaiting
it, so the wait ran behind the play start; fixed in the fifth round.)

Measured with `probes/structure_perf3.gd` `load` and `load_staged` (job `perf4_staged`, 128 lots of the
core recipes with ornament masks, 320 m map; indicative, the GPU was shared), two runs each:

| | main-thread make | worst frame while installing | frames |
|---|---|---|---|
| before (synchronous create) | 612 ms, 339 ms in one frame | the same frame | 1 |
| after (staged) | create 159 and 165 ms, then 3 ms a frame | 116 and 58 ms (the first installs) | 51 |

Paint and split, kept (perf4): `StructurePaint.paint` with one palette (every structure; a street row's
several palettes keep the per-vertex path `_paint_groups`) reads the palette, the mesh's role and kind tests and
the height limits once per mesh and runs one tight loop per mode; `split_surface` finds each tag's material slot
once, deals the triangles into per-role buckets in one pass and copies a role's vertices as runs of neighbours.
Output is byte-identical: `tests/unit/test_structure_paint_equal.gd` keeps the old implementations as the
reference and compares every array of every mesh over the 100 structures and 72 prop draws (also with two
palettes), and the pinned digests did not move. `build_one` on the main thread over those 172 builds, best of
three passes (indicative, shared machine): 3,198 and 3,313 ms before, 2,435 ms twice after (24 to 26 percent
less); the worst ten (`hof_farm`, `coaching_inn`, `riad`, `siheyuan`, `hanseatic`, `chapel`, `flemish_stepped`,
`castle_keep`, ...) summed 650 and 672 ms before, 488 and 486 ms after (25 to 27 percent). Alone, split fell from
370 to 170 ms and paint from 719 to 153 ms over the 172. Over the 15 percent bar, so kept.

What was left in the one create frame (headless probe, 128 cottages with ornaments): the decor library info
(`_decor_info`, 108 ms the first time, loading plant meshes), the plant plans for a loader's parts (44 ms,
`plan_missing`) and the keys (25 ms, the ground under every footprint). The fifth round took all three off
the main thread.

## Fifth round: the create frame goes to the worker, the client waits too (staged_load2, 2026-10-31)

**Worker prep.** `AuthoredLoadPrep`'s `STRUCTURES` task now runs `StructureLoadInfo.prepare`: the decor
library info (`StructureLoadInfo.info_of`: `AssetStore.decor_rows`, the triangle cost of each plant's source
mesh, `sig`), `StructureGeometry.build` with that info (so each part carries its `decor_plan`), and
`StructureGeometry.keys_of`. `AuthoredStructures.create` reuses them (`info_for`, `keys_for`) when they still
match the library's rows and the document's structure ids, else makes them itself as before; `_decor_info`
is the same `info_of` (the cost is the source mesh's triangle count, equal to its wind-dressed copy's). The
wind-dressed copies and baked surfaces (`_decor_entry`) stay main-thread resources, made per structure as its
node installs. `AssetStore` already guards its tables with a mutex and parses a GLB on any thread; a worker
parses only where `GlbUtils.threaded_loads_safe()` (not the headless dummy renderer), otherwise `create`
reads the library as before. Unchanged: the parts, keys and digests (test
`test_structure_load_info.gd`: costs equal the old path's, keys equal `keys_of`, plans and node vertices equal
a create that made them itself, stale info or ids are made again; `tests/fixtures` digests did not move).

Measured with `jobs/staged_load2.json` (after) and `staged_load2_before.json` (`"prepared": false` on the
probe's `load_staged`, the geometry alone as before), a rendered window, 128 lots, 320 m map, shared GPU
(indicative); two runs each, the first staged load of a process (cold: the plant meshes unparsed) and the second:

| main-thread `create`, 128 structures | cold | warm |
|---|---|---|
| before | 169.0 and 179.3 ms | 105.4 and 109.6 ms |
| after | 1.2 ms (run 1) and 1.1 ms (run 2) | 1.1 and 1.1 ms |

The work moved to the worker (the probe runs `prepare` itself on the main thread before `create`, so the cold
parse is paid once there). The staged frames after `create` are unchanged within noise: worst frame 226 and
227 ms cold before, 226 and 248 ms after (the first installs, with the shader compile and the first
wind-dressed copies); warm 99.5 ms before, 76 and 74 ms after; 76 to 82 frames, median 22 to 26 ms
(the 128 lots, unpinned machine).

**Client download path.** `MapDownloadCoordinator._load_downloaded_map` now awaits the finalise, and
`is_busy()` is true from the request until the downloaded map is built, finalised and its structures stand
(a reset, a replaced request or a failure ends it). `LevelPlayLoader._play_level_async` waits right after the
map step in `MapDownloadWait.wait_async` ("Downloading map..." on the loading bar) before it preloads models or
sets any token down, so a client's tokens no longer land before the map exists or before the last roof has
collision (before, the client spawned its tokens while the files were still coming). The structure wait
inside the finalise is still bounded (`MAX_FRAMES`, 600); it now logs a warning when it hits the cap and then
makes the rest at once. The download itself is not time-limited by the wait: the streamer's failure
signals, a level change or a reset end it, and the loader then goes on without the map as before.
Tests: `test_map_download_wait.gd` (the wait ends with the finalise, before the first token; one
announcement; a superseded load drops), `test_map_download_coordinator.gd` (`is_busy` over download, load,
finalise, reset, failure).

**Live edits during the wait.** No gap: a client's `LiveEdits` service is made only after the structures
stand (`start_live_edits`, last in `_finalize_map_loading`), so ops the host broadcasts earlier reach no
listener, and the service's first act is `request_live_edit_log`, which the host answers with the whole log
(the late-joiner path, `test_live_edits_table.gd`: "an op before the header is dropped", then the header and
every op catch the map up at once). Nothing is lost; nothing needs queuing.

## Open follow-ups, ranked

1. Procgen: profile and speed up `evaluate_structure` on the facade, layout and courtyard nodes, starting
   with `hof_farm`, `coaching_inn`, `dutch_bell_house`, `canal_house`. Digests must stay identical.
2. (Done in perf4: paint and split, 24 to 27 percent of build time, byte-identical; done in staged_load2:
   the one-frame `create` of a staged load, now about 1 ms.) Left: the first install frames of a cold
   load (worst frame about 230 ms: shader compile and the first wind-dressed copies).
3. Builds scale badly past 4 to 6 threads (allocator contention); a build that allocates less would help
   edits and loads alike.
4. structgen: the size sweep's mesh check dominates (2.6 s for the inn up to 22.6 s for `townhouse`,
   already on a worker). A coarser or early-out `ProcgenMeshCheck.holes` would help. Edit evaluation runs
   on the main thread behind a 50 ms debounce and costs 13 to 80 ms.
