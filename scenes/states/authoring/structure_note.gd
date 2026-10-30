class_name StructureNote
extends RefCounted

## The live note beside the Structure tool's ghost lot (StructureBrush.draw): in plain words why the
## lot is not exactly what the author asked for, with a level that colours the note and the ghost.
## BLOCKED: nothing within reach can hold the lot (red; a release lays nothing and toasts the same
## words). NOTE: the lot was eased off bad ground or held to the recipe's size range (amber; a
## release still lays it). Pure: no nodes, so tests call it directly. The brush works it out once
## per ghost position (its cache), not per frame. docs/systems/structures.md "The tool".

enum Level { NONE, NOTE, BLOCKED }

## What a lot that was eased away was moved off, by StructurePlacement's reasons.
const MOVED_WATER := "Moved clear of the water."
const MOVED_STEEP := "Moved to flatter ground."
const MOVED_OFF_MAP := "Moved back onto the map."
const MOVED_OCCUPIED := "Moved clear of the next building."
const MOVED_ELSEWHERE := "Moved to the nearest good ground."
const BIGGEST := "Biggest size this building goes: %d x %d %s."
const SMALLEST := "Smallest size this building goes: %d x %d %s."
## A side asked for must differ from the one given by more than this (metres) to count as held.
const CLAMP_EPSILON_M := 0.01


## Why a lot moved: the reason the pointer's own spot failed (a StructurePlacement problem), in
## plain words.
static func moved_text(why: String) -> String:
	match why:
		StructurePlacement.WATER:
			return MOVED_WATER
		StructurePlacement.STEEP:
			return MOVED_STEEP
		StructurePlacement.OFF_MAP:
			return MOVED_OFF_MAP
		StructurePlacement.OCCUPIED:
			return MOVED_OCCUPIED
	return MOVED_ELSEWHERE


## The size stop ("Biggest size this building goes: 62 x 40 ft.") when `got` is not what was
## `asked` (map metres, both), else "". A side shrunk means the biggest was hit, else the smallest.
## The sizes read in the level's units (`cell_m` metres a cell, `per_cell` units a cell, `label`).
static func clamp_text(
	asked: Vector2, got: Vector2, cell_m: float, per_cell: float, label: String
) -> String:
	if absf(asked.x - got.x) < CLAMP_EPSILON_M and absf(asked.y - got.y) < CLAMP_EPSILON_M:
		return ""
	var a := roundi(ScaleUtils.world_to_display(got.x, cell_m, per_cell))
	var b := roundi(ScaleUtils.world_to_display(got.y, cell_m, per_cell))
	var shrunk := asked.x > got.x + CLAMP_EPSILON_M or asked.y > got.y + CLAMP_EPSILON_M
	return (BIGGEST if shrunk else SMALLEST) % [a, b, label]


## The note for a ghost lot: {"text", "level"}. `problem` is what stops the lot (BLOCKED, its
## refusal words), else a held size (`clamp`, from clamp_text) or a move (`moved` and its `why`)
## is a NOTE, in that order; else no note.
static func live(problem: String, why: String, moved: bool, clamp: String) -> Dictionary:
	if problem != "":
		var words := StructureBrush.refusal_text(problem)
		return {"text": words if words != "" else StructureBrush.INVALID_TEXT, "level": Level.BLOCKED}
	if clamp != "":
		return {"text": clamp, "level": Level.NOTE}
	if moved:
		return {"text": moved_text(why), "level": Level.NOTE}
	return {"text": "", "level": Level.NONE}


## The colour a note's pill and the ghost's lines wear at `level`: the readout's own at NONE.
static func colour(level: int) -> Color:
	match level:
		Level.BLOCKED:
			return WallBrush.REFUSED_COLOR
		Level.NOTE:
			return StructureBrush.CUE_TINT
	return WallBrush.READOUT_COLOR


## The tint of the ghost's footprint and lines at `level`.
static func ghost_tint(level: int) -> Color:
	match level:
		Level.BLOCKED:
			return WallBrush.REFUSED_COLOR
		Level.NOTE:
			return StructureBrush.CUE_TINT
	return WallBrush.STONE_TINT
