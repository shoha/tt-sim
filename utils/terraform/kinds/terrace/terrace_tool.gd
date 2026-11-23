extends RefCounted
## The Terrace tile of the Sculpt tool (card terraform-p2-sculpt): the tool half of the terrace
## kind's folder (terrace_kind.gd is the kind half). A stroke is one terrace primitive (kind 16);
## TerraSculpt adds it on the stroke's first frame and appends each later frame's frame_dabs().
## A terrace dab pulls the ground fully onto its tiers at its centre, so a still brush adds
## nothing: the dabs follow the path travelled, at most radius / 4 apart. The treads are half a
## map tier high (MapDocument.tier_height_m), so two terraces step up one tier.

const Kind := preload("res://utils/terraform/kinds/terrace/terrace_kind.gd")

## The Sculpt pane's tile (SculptTool.TERRA_TILES; "op" is TerraSculpt.TERRACE).
const TILE := {
	"label": "Terrace",
	"icon": "landform-terraces",
	"tooltip": "Step a slope into flat treads and soft risers, as fields on a hillside",
}
## Treads per map tier, and the riser's share of a tread.
const TREADS_PER_TIER := 2.0
const SOFTNESS := 0.35
## The longest gap between dabs, in radii.
const SPACING := 0.25


## The tread height of a map whose tier is `tier_height_m` (map frame).
static func tread_m(tier_height_m: float) -> float:
	return maxf(0.05, tier_height_m / TREADS_PER_TIER)


## One held frame's dabs from `from` to `to` (map XZ) of `radius` for treads of `tread`: a dab at
## the press (`last` is INF), then one every SPACING radii along the path from the last dab.
## Returns {"data": the dabs (maybe none), "last": the newest dab's centre}. Pure.
static func frame_dabs(
	from: Vector2, to: Vector2, radius: float, tread: float, last: Vector2
) -> Dictionary:
	var out := PackedFloat32Array()
	var step := maxf(radius * SPACING, 1e-3)
	var at := last
	if not at.is_finite():
		at = from
		out.append_array(PackedFloat32Array([at.x, at.y, radius, tread, SOFTNESS]))
	# Walk from the last dab toward `to` in steps of `step`.
	while at.distance_to(to) >= step:
		at = at.move_toward(to, step)
		out.append_array(PackedFloat32Array([at.x, at.y, radius, tread, SOFTNESS]))
	return {"data": out, "last": at}


static func describe() -> String:
	return Kind.describe()
