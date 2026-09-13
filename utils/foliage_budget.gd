class_name FoliageBudget
extends RefCounted

## Fixed global cap on how many scattered-foliage primitives an imported map may render,
## with the arithmetic for thinning one that exceeds it. Pure statics only -- no node
## access and no side effects, so the whole allocator is unit-testable without a scene
## tree or a renderer. Applied by ScatterGlbUtils.process_scatter_instances().
##
## Why a cap is needed at all: a MultiMeshInstance3D is frustum-culled as a SINGLE AABB,
## and foliage is built as one MultiMesh per species spanning the whole map. If any part
## of a species is on screen, every one of its instances is vertex-processed. Measured on
## a dense forest map, visible-pass primitives read an identical 19,361,510 at every
## camera pose tried, and panning changed nothing. Total instance count per map -- not
## density per unit area, and not what happens to be in frame -- is the cost driver.
## See docs/PERFORMANCE.md for the full attribution.

## Maximum total foliage primitives (triangles) across all scatter species in one map.
##
## PROVISIONAL. Derived from one scene on one GPU: on a dense forest map an RTX 3080
## spent ~11 ms of a 14.5 ms frame on 16.3M foliage primitives, and hiding foliage
## entirely took the frame to 3.5 ms. 8M is roughly half that load, putting foliage at
## ~5-6 ms there and leaving headroom under a 60 FPS budget for a weaker GPU. This needs
## validating on slower hardware before release -- the mechanism is the deliverable, the
## threshold is a tunable. Deliberately NOT overridable per level: a budget a map can opt
## out of does not bound anything.
const PRIMITIVE_BUDGET: int = 8_000_000


## Triangles in one instance of `mesh`, summed over its triangle surfaces.
##
## Two paths because the cheap one does not exist on every Mesh: surface_get_array_*()
## and surface_get_primitive_type() are ArrayMesh methods, and calling them on a
## PrimitiveMesh fails outright. Imported glTF meshes are ArrayMesh, where reading the
## index length avoids copying any vertex data; BoxMesh and friends fall back to
## get_faces(), which materialises the whole face array but only ever runs on small
## fixtures. A mesh whose primitive count cannot be determined counts as 0 and is
## therefore never thinned -- an unknown mesh type must not cause silent content loss.
static func primitives_per_instance(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return mesh.get_faces().size() / 3
	var total := 0
	for surface in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var index_length := array_mesh.surface_get_array_index_len(surface)
		if index_length > 0:
			total += index_length / 3
		else:
			total += array_mesh.surface_get_array_len(surface) / 3
	return total
