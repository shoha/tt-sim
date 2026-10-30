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

## Open follow-ups, ranked

1. Procgen: profile and speed up `evaluate_structure` on the facade, layout and courtyard nodes, starting
   with `hof_farm`, `coaching_inn`, `dutch_bell_house`, `canal_house`. Digests must stay identical.
2. Vectorise `StructurePaint.paint` and `split_surface` (not done in struct_perf2; needs a gain of 20
   percent of build time and byte-identical output).
3. Builds scale badly past 4 to 6 threads (allocator contention); a build that allocates less would help
   edits and loads alike.
4. structgen: the size sweep's mesh check dominates (2.6 s for the inn up to 22.6 s for `townhouse`,
   already on a worker). A coarser or early-out `ProcgenMeshCheck.holes` would help. Edit evaluation runs
   on the main thread behind a 50 ms debounce and costs 13 to 80 ms.
