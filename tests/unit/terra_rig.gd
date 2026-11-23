class_name TerraRig
extends RefCounted
## A map with the terrain corpus loaded through MapSourceLoader and an authoring editor over it, as
## authoring and the play side make one (test_terra_editor, test_terra_live_edits). Build with
## the switch set as the test needs (TerraCore.switch_override); with it on the map has a
## TerraSession and its bridge, whose editor is this rig's.

const CELLS := Vector2i(24, 24)
const MAX_FRAMES := 900

var root: Node3D = null
var doc: MapDocument = null
var corpus: TerraCorpus = null
var editor: AuthoringEditor = null
var history: AuthoringHistory = null


## The corpus map under `parent` (in the tree, so the session polls), `with_section` false for the
## same flat map without its terrain section.
static func build(parent: Node, with_section := true) -> TerraRig:
	var rig := TerraRig.new()
	rig.corpus = TerraCorpus.build(CELLS)
	rig.doc = MapDocument.create_flat(CELLS, "grass", "v", 3)
	if with_section:
		rig.doc.terra = rig.corpus.terra
	rig.root = await MapSourceLoader.new(parent.get_tree()).build_async("", rig.doc)
	parent.add_child(rig.root)
	var scatter := rig.root.get_node_or_null(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	if scatter != null:
		scatter.attach_document(rig.doc)
	rig.history = AuthoringHistory.new()
	rig.editor = AuthoringEditor.create(rig.doc, rig.root, rig.history)
	return rig


func session() -> TerraSession:
	return root.get_node_or_null(TerraSession.NODE_NAME) as TerraSession


## True while anything of the map is still working: the editor's height work (the terrain's
## landings included), the session's derive, the scatter's regeneration and grow-in, and the
## structure builds in flight (a press that waited starts its build late; on 4 worker threads
## it landed after the rest, card noblock3).
func busy() -> bool:
	var s := session()
	var scatter := root.get_node_or_null(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	var water := root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	var structures := AuthoredStructures.of_map(root)
	return (
		editor.has_height_work()
		or editor.water.is_working()
		or (structures != null and structures.pending_count() > 0)
		or (water != null and water.is_refreshing())
		or (s != null and not s.is_ready())
		or (scatter != null and (scatter.is_regenerating() or scatter.is_growing()))
	)


## Frames, stepping the editor (and `queue`, a peer's LiveEditCodec.Queue, which applies its ops)
## until every rig in `rigs` is idle. False past MAX_FRAMES.
static func settle(tree: SceneTree, rigs: Array, queue: LiveEditCodec.Queue = null) -> bool:
	for i in MAX_FRAMES:
		var busy := queue != null and not queue.is_idle()
		for rig: TerraRig in rigs:
			if queue == null or rig.editor != queue.editor:
				rig.editor.step_height_work()
			busy = busy or rig.busy()
		if queue != null:
			queue.step()
		if not busy:
			return true
		await tree.process_frame
	return false


## Every digest of the settled derive and the document's digest: {"doc", "arrays"}.
func digests() -> Dictionary:
	return {"doc": doc.terra.call("digest_for", doc), "arrays": session().digests()}


## The id of the corpus's `n`th primitive of `kind` (0 the first).
func prim_of(kind: int, n := 0) -> int:
	for p in (doc.terra as TerraDoc).prims:
		if int(p["kind"]) == kind:
			if n == 0:
				return int(p["id"])
			n -= 1
	return -1


## The scripted gesture of both tests, through `editor.terra`: add a stroke and append to it, remove
## a hill, and splice another hill out for a lower one in its place under a new id. Returns the
## gesture.
func scripted_gesture(label := "Terrain test") -> Dictionary:
	var terra := editor.terra
	var t := doc.terra as TerraDoc
	terra.begin_gesture()
	var dab := corpus.dabs([[20.0, 22.0, 3.0, 0.2, 0]])
	var id := terra.edit({"op": "add", "kind": TerraCore.STROKE, "data": dab})
	terra.edit({"op": "append", "id": id, "data": corpus.dabs([[22.0, 23.0, 3.0, 0.2, 0]])})
	terra.edit({"op": "append", "id": id, "data": corpus.dabs([[24.0, 24.0, 3.0, 0.2, 1]])})
	terra.edit({"op": "remove", "id": prim_of(TerraCore.HILL, 1)})
	var hill := prim_of(TerraCore.HILL, 2)
	var data: PackedFloat32Array = (t.find(hill)["data"] as PackedFloat32Array).duplicate()
	data[2] *= 0.5
	var lower := {"id": t.next_id, "kind": TerraCore.HILL, "flags": 0, "data": data}
	var spliced := {
		"op": "splice",
		"remove": [hill],
		"insert": [lower],
		"at": t.index_of(hill),
		"next_id": t.next_id + 1,
	}
	terra.edit(spliced)
	return terra.end_gesture(label)
