# Press bench

How long a press made right after a river release or a held raise holds the frame, with the
terraforming core off (today's game) and on. Cards noblock2 to noblock4; the model is
`docs/systems/terraform.md` "Never blocking" and `scenes/states/authoring/ground_presses.gd`.

- `noblock_bench.json`: the job. Per switch (off, then on): a new 320 ft hilltop map (seed 1234,
  the landform's own river and pond), `ground` (a ROW street, a standing fire, the river line a
  trial releases and the crossing over the landform's river), then 20 trials: the release (`river`:
  a river carved on the Water tool's path, on its worker; `raise`: the end of a 20-frame held
  Raise) and in the same frame one press: none, structure, crossing, settlement, fire, put out,
  save, table (the table move's settle and `TableMover.document_of`, in authoring), undo, redo
  (undo and redo in one frame), paint and pond (a Paint or pond stroke begun, dabbed once and
  ended in the frame; card noblock6). The map is put back between trials. A row's `waits` counts
  its frames by the height work that held them (`work_codes`: snap, coll, terr, rock, water,
  land, terra), `work_ms` the terrain and collision time spent.
- `noblock_probe.gd`: the probe (its header lists the actions and the row's fields).

Run it as a render job, windowed, holding the lane, after `docs/PERFORMANCE.md`'s quiet check:

```
godot --path D:/dev/tabletop/tt-sim --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_jobs/run.gd -- res://tools/bench/noblock_bench.json
```

Each trial appends one JSON row to `user://noblock_bench.jsonl` (the checkout's own user folder);
the `report` step logs every run so far grouped by switch, release and press (min-max over runs).
Delete the rows file before a new series. The save press writes the test level
`_noblock4_bench`, which the job's last step deletes. For a before / after comparison, run the
same files in a detached worktree of the older commit with its own user folder (copy this folder
there; the probe only reads APIs that existed since GroundPresses, d29db9c0).

Columns: `call ms` is the press call; `delay ms (frames)` runs from the press to its result (a
queued press running, a save or settle finishing; the call itself when it ran at once); `worst ms`,
`over33 n` and `over33 ms` are whole frames (process to process) from the press frame until the map
is idle. A river release computes on the Water tool's worker for about 0.3-0.7 s, so a press queued
behind it shows that as its delay, where it used to show it as one frozen frame.
