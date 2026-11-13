class_name PainterTreeMass
extends RefCounted
## One semantic mass: the only thing a generator emits. The painter turns it into a block-in
## mesh and brush strokes; it carries no colour, only a role.
##
## Shapes (local space, before `xform`):
##   ELLIPSOID  centred on the origin, radii = size
##   CAPSULE    a tapered trunk along +Y from 0 to size.y, base radius size.x, params.taper
##   BOX        base-centred: x and z span +-size/2, y spans 0..size.y
##              params.no_caps skips top and bottom, params.top_only keeps only the top
##   PRISM      a roof on a size.x by size.z base, ridge along X at height size.y;
##              params.hip (0..1) shortens the ridge from both ends (0 = gable, >0 = hipped)

##   STRAND     (round 2) a tapered tube along params.pts (PackedVector3Array, asset space) with
##              params.radii (PackedFloat32Array); xform is ignored. PainterTreePack packs it.

enum Shape { ELLIPSOID, CAPSULE, BOX, PRISM, STRAND }
enum Role { LEAF, BARK, STONE, WALL, ROOF, TRIM, GROUND, COUNT }

var shape: int = Shape.ELLIPSOID
var xform: Transform3D = Transform3D.IDENTITY
var size: Vector3 = Vector3.ONE
var role: int = Role.STONE
var params: Dictionary = {}


static func make(
	p_shape: int, p_xform: Transform3D, p_size: Vector3, p_role: int, p_params: Dictionary = {}
) -> PainterTreeMass:
	var m := PainterTreeMass.new()
	m.shape = p_shape
	m.xform = p_xform
	m.size = p_size
	m.role = p_role
	m.params = p_params
	return m
