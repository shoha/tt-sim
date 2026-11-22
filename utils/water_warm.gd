class_name WaterWarm
extends RefCounted

## The water conditioner's lazily loaded parts, compiled ahead of the first stroke (card
## painter-edit-hitch3). WaterEdit loads them by path on first use (named as classes they would
## join the start-up script graph, test_boot_graph), and their first compile landed in the frame
## that plans the stroke: the first river's release cost about 53 ms more than the next one's
## (water_ports 33.5 ms, water_course_fit 19.6; water_refit and water_pond_fit 23 to 24 ms more
## on their own first use, the pond fit on the edit's worker). BootPrecompile compiles them behind
## the title (its ROOTS list them); warm(), at a map's opening under its loading screen, loads
## whatever that left, and holds them so they stay compiled.

## The scripts WaterEdit loads by path (its *_PATH constants).
const PATHS: PackedStringArray = [
	WaterEdit.COURSE_FIT_PATH,
	WaterEdit.CONDITIONER_PATH,
	WaterEdit.PORTS_PATH,
	WaterEdit.HINTS_PATH,
	WaterEdit.REFIT_PATH,
	WaterEdit.POND_FIT_PATH,
]

## How long the last warm() took (usec; probes: the time it adds to a map's opening).
static var last_usec: int = 0
## The scripts warm() loaded, held so they stay compiled.
static var _held: Array[GDScript] = []


## Loads every PATHS script and holds it; returns how many were not loaded yet (0 when
## BootPrecompile or an earlier call had them all).
static func warm() -> int:
	var started := Time.get_ticks_usec()
	var loaded := 0
	for path in PATHS:
		if not ResourceLoader.has_cached(path):
			loaded += 1
		var script := load(path) as GDScript
		if script != null and not _held.has(script):
			_held.append(script)
	last_usec = Time.get_ticks_usec() - started
	return loaded
