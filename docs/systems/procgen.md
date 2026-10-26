# procgen (shared generator module)

`procgen/` is a git submodule shared with plantgen (repo `D:/dev/procgen`; the `.gitmodules` url
is a local path until the repo has a remote, change it before pushing this branch). It holds the
node-graph document, the pull evaluator, `ProcgenRegistry`, the generator nodes and meshers and the
geometry primitives, as pure GDScript with no scene tree, so it can run on worker threads like
`CrossingGeometry`. Plan and rationale: plantgen `docs/parametric_structures_research.md`.

Status (2026-10-26): mounted and tested, nothing in the game uses it yet.

- `tests/unit/test_procgen_module.gd` runs the module's `ProcgenSelfCheck` here: a graph built in
  code evaluates, repeats exactly, builds the same mesh on `WorkerThreadPool` as on one thread, and
  matches the digest pinned in `procgen/tests/expected_digest.txt` (the same digest plantgen
  gets, so the two projects build identical meshes).
- No global `class_name` clashes (80 plantgen core names against this project's, checked by name),
  and the GDScript analyzer reports nothing from `procgen/`.
- Rules: nothing inside `procgen/` may reference a class from either host; a host supplies its own
  node types and `output_rules` by subclassing `ProcgenRegistry`. Keep the `.gd.uid` files.

Next: a structure Output node and a bridge graph, then `CrossingGeometry` calling the module.
