# procgen (shared generator module)

`procgen/` is a git submodule shared with plantgen (`github.com/shoha/procgen`, private). It holds the
node-graph document, the pull evaluator, `ProcgenRegistry`, the generator nodes and meshers and the
geometry primitives, as pure GDScript with no scene tree, so it can run on worker threads like
`CrossingGeometry`. Plan and rationale: plantgen `docs/parametric_structures_research.md`.

Status (2026-10-26): mounted and tested, nothing in the game uses it yet. The module now has the
structure foundation (`ProcgenGuide`, `ProcgenEnvironment`, `ProcgenStructureInputs`, document
parameters bound by `"@name"`, `collision`/`top` on the geometry) and the first bridge nodes (Guide,
Planks, Deck Collision); the self-check also builds a 6 m bridge sample and pins its mesh and deck
collision. Design: plantgen `docs/structures_design.md`.

- `tests/unit/test_procgen_module.gd` runs the module's `ProcgenSelfCheck` here: a graph built in
  code evaluates, repeats exactly, builds the same mesh on `WorkerThreadPool` as on one thread, and
  matches the digest pinned in `procgen/tests/expected_digest.txt` (the same digest plantgen
  gets, so the two projects build identical meshes).
- No global `class_name` clashes (80 plantgen core names against this project's, checked by name),
  and the GDScript analyzer reports nothing from `procgen/`.
- Rules: nothing inside `procgen/` may reference a class from either host; a host supplies its own
  node types and `output_rules` by subclassing `ProcgenRegistry`. Keep the `.gd.uid` files.

Next: a structure Output node and a bridge graph, then `CrossingGeometry` calling the module.

## Plank bridge parity (2026-10-26)

`ProcgenCrossing` (`utils/procgen_crossing.gd`, pure and worker-safe) turns a `Crossing` and the
document into the recipe's inputs (a span guide from the length and three levels, `width_m` as the
`width` parameter, the document's ground as the environment, a seed from map seed, id and kind) and
returns the module's geometry in the map frame. The recipe is `procgen/recipes/plank_bridge.json`
(planks, stringers, sills, posts and rail, piles, deck collision).

`tests/unit/test_procgen_bridge_parity.gd` compares it with `CrossingGeometry.build_one` on
`test_crossings.gd`'s rivers (narrow, wide, a diagonal with a 2.6 m deck): the deck collision is the
same faces in the same order to 0.1 mm, `top` is equal, the number of boxes (boards, beams, sills,
posts, rails, piles) is equal, the wood bounds agree within a hand's width (the jitter streams
differ), every triangle is clockwise, and the build repeats on four worker threads. Nothing in the
game calls `ProcgenCrossing` yet: `CrossingGeometry` still builds every crossing itself.

Not covered by the parity test: tangents (the module writes none), the moss split, the wood UVs
(the module uses the copied swatch table, see procgen `README.md`), `deck_field`, collapse, the
cache key.

## The switch (2026-10-26)

`ProcgenCrossing.enabled` (a static var, off by default) routes `CrossingGeometry.build_one`'s plank
bridge through the module: the wood, the deck collision and the top come from the recipe, with
tangents added by the adapter for the normal-mapped `planks` surface (`_quad_tangents`); an arch,
ford or stones are untouched. `CrossingCache.key_of` includes the switch for planks, so flipping it
rebuilds them. It is per machine, and a rollout must make it a map or library fact: peers that
disagree would see different boards (the walking surface is identical).

Verified end to end on 2026-10-26 with the switch forced on: `test_crossings`, `test_crossing_cache`,
`test_crossing_editor`, `test_map_document_crossings`, `test_bridge_tool`, `test_authored_load_prep`,
`test_authored_terrain`, `test_terrain_event(s)` and `test_play_events` all pass (the last two build
the collapse), and with it off nothing changed. In the game (render job `procgen_bridge_look`,
captures in `user://render_jobs/procgen_bridge_look`): the bridge reads as the house plank bridge
(boards, stringers, posts and rail, sills, the arch), the grid runs across its deck, and tokens
stand on the deck and at its end in play after a save and reload. Not compared pixel for pixel with
the code-built bridge: the jitter streams differ and the first capture of the old bridge was behind
a tree.

