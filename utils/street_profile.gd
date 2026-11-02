class_name StreetProfile
extends RefCounted

## Pure: the cross-section of a street (a row Wall) from its species (`Wall.preset`) and setback
## (`Wall.height_m`, how far its facades stand from the centre line). One place answers it, so the
## frontage strip the kit dresses (SettlementFrontage), the road a Dress paints
## (SettlementGround), the gates of a boundary (VillageBoundary) and the bridges and dry ground of
## a crossing (VillageBridges, VillageDryGround) always agree.
##
## A profile is {"setback", "strip", "road_half", "pavement"} in metres (pavement a bool):
## - `strip`: the paved frontage between facade and kerb (procgen's ProcgenFrontage.gap_m);
## - `road_half`: the painted road's full-cover half width either side of the centre line;
## - `pavement`: whether the Dress paves the strip (the kit's door_path surface laid over it).
##
## Two shapes. A lane street (every species but the wide ones) draws both from the setback as it
## always has: strip STRIP_SHARE of it (STRIP_MIN_M..STRIP_MAX_M), road ROAD_HALF_SHARE of it
## (ROAD_HALF_MIN_M..ROAD_HALF_MAX_M), so the road paint runs under most of the strip; a cottage
## lane is a lane. A wide street (StreetSpeciesInfo `wide`: the modern row) is a two-lane road
## between pavements: the road takes WIDE_ROAD_SHARE of the setback each side (at most
## WIDE_ROAD_HALF_MAX_M, an 8.6 m road of two lanes) and the strip is the rest, kerb to facade, so
## road half and strip add up to the setback. At the modern row's 8.4 m setback that is the
## cross-section procgen's kit is tuned for (docs/modern_town.md section 15): pavement 4.1, road
## 8.6, pavement 4.1. An author who moves the setback keeps the shape: both parts scale with it.

const STRIP_SHARE := 0.75
const STRIP_MIN_M := 1.0
const STRIP_MAX_M := 4.0
## All about a third more than villages2's 0.58 and 0.9..2.4 m: at home zoom the road hid behind
## the near house rows.
const ROAD_HALF_SHARE := 0.77
const ROAD_HALF_MIN_M := 1.2
const ROAD_HALF_MAX_M := 3.2
## A wide street's road: this share of the setback each side, within the limits; its pavement
## keeps at least WIDE_STRIP_MIN_M.
const WIDE_ROAD_SHARE := 0.512
const WIDE_ROAD_HALF_MAX_M := 4.3
const WIDE_STRIP_MIN_M := 1.0


## The profile of a street of species `preset` with setback `setback_m`.
static func of(preset: int, setback_m: float) -> Dictionary:
	if StreetSpeciesInfo.is_wide(preset):
		var road := clampf(setback_m * WIDE_ROAD_SHARE, ROAD_HALF_MIN_M, WIDE_ROAD_HALF_MAX_M)
		return {
			"setback": setback_m,
			"strip": maxf(setback_m - road, WIDE_STRIP_MIN_M),
			"road_half": road,
			"pavement": true,
		}
	return {
		"setback": setback_m,
		"strip": clampf(setback_m * STRIP_SHARE, STRIP_MIN_M, STRIP_MAX_M),
		"road_half": clampf(setback_m * ROAD_HALF_SHARE, ROAD_HALF_MIN_M, ROAD_HALF_MAX_M),
		"pavement": false,
	}


## The profile of row `wall` (its preset and setback).
static func of_wall(wall: Wall) -> Dictionary:
	return of(wall.preset, wall.height_m)


## The frontage strip (metres) of row `wall`.
static func strip_m(wall: Wall) -> float:
	return float(of_wall(wall)["strip"])


## The road's full-cover half width (metres) of row `wall`.
static func road_half_m(wall: Wall) -> float:
	return float(of_wall(wall)["road_half"])
