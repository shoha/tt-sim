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
  wet dressing.
- [waterfalls.md](waterfalls.md): the fall-or-riffle rule, the plan-time lips and set-back, the
  fall carve, the curtain / foam ring / mist mesh and shader, the fall material.
- [crossings.md](crossings.md): plank bridges and stepping stones, including the refusal by a
  waterfall.
