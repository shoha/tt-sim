# tools/roster: building a built-in token pack from a CC0 source

The Folk pack (`builtin_packs/folk/`, provenance in `docs/licences/builtin_packs/folk.md`) is
reproducible from its two Quaternius downloads:

```
godot --headless --path <tt-sim> --script res://tools/roster/build_folk.gd -- \
  --ubc "<dir>/Universal Base Characters[Standard]" \
  --mof "<dir>/Modular Character Outfits - Fantasy[Standard]" \
  --out <tt-sim>/builtin_packs/folk/models [--only villager_man]

godot --path <tt-sim> --resolution 520x520 --script res://tools/roster/render_icons.gd -- \
  --pack <tt-sim>/builtin_packs/folk [--only villager_man]
```

The build writes each `models/<id>.glb` and its `importer="keep"` sidecar; the icon tool (needs a
window) writes `icons/<id>.png` and its sidecar. The manifest is hand-written. Run
`godot --headless --import` after, and the gate (`tests/unit/test_folk_pack.gd` checks the pack).

- `folk_recipes.gd`: the roster (body, outfit, colourway, hood, hair, tints).
- `folk_bake.gd`: A-pose skinning, head cut, merge and triangle reduction.
- `folk_glb.gd`: the minimal GLB writer (no tangents) and the keep sidecar writer.
- The downloads are untrusted data: extract them somewhere outside the project and pass the paths.
  The free Standard packs hold two outfits per sex, so the roster is limited to what they contain.
