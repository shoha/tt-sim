extends RefCounted
## The terrace brush (kind 16, the first kind added through the registry): dabs [cx, cz, radius,
## tier_m, softness]. Under each dab the composed height is pulled toward tiers of tier_m, each a
## flat tread and a soft riser (softness is the riser's share of a tier), by the dab's falloff. It
## reads the height composed so far, so a terrace drawn after a hill steps that hill. Kernel:
## native/src/kinds/terra_kind_terrace.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "terrace"
const ID := 16
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 0
const STRIDE := 5
const MIN_ITEMS := 1
const LABEL := "Terrace"
const DEFAULTS := {"radius": 3.0, "tier_m": 0.6, "softness": 0.35}


## True when `data` holds at least one dab, each with a positive radius and tier and a softness
## in (0, 1].
static func validate(data: PackedFloat32Array) -> bool:
	if not Layout.fits(data, HEADER, STRIDE, MIN_ITEMS):
		return false
	for k in [2, 3, 4]:
		if not Layout.item_positive(data, HEADER, STRIDE, k):
			return false
	for i in Layout.items(data, HEADER, STRIDE):
		if data[i * STRIDE + 4] > 1.0:
			return false
	return true


## The world box a terrace changes: its dabs' discs.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.dab_bounds(data, STRIDE)


static func describe() -> String:
	return "Step the ground into flat treads and soft risers, as fields on a hillside."
