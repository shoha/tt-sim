extends RefCounted

## Headless scatter numbers for the performance audit's foliage stream (perfaudit, 2026-11-09), run
## through tools/foliage_bench_run.gd. CPU only; other work may share the machine, so every timing
## alternates native and GDScript in the same run and the report gives their ratio as well.
##   build  per map size (--sizes=100,200,400; temperate forest, seed 1234, valley): the document
##          build (NewMap.create), the whole scatter build through ScatterRegen's jobs as
##          AuthoredScatter runs them (min(cores / 2, 6) at once; native --runs times, GDScript
##          --gd_runs times), then a census of the rows: instances, cells and row bytes per asset,
##          per library category and per size class.

const BIOME := "temperate_forest_summer_s1"
const SEED := 1234
const LANDFORM := "valley"


func run(args: Dictionary) -> void:
	var sizes := String(args.get("sizes", "100,200,320")).split(",")
	var runs := int(args.get("runs", "3"))
	var gd_runs := int(args.get("gd_runs", "1"))
	var fill: bool = String(args.get("fill", "0")) == "1"
	print(
		(
			"FB| cores %d, native library %s, active %s"
			% [OS.get_processor_count(), ScatterNative.version(), ScatterNative.active()]
		)
	)
	if String(args.get("task", "build")) == "assets":
		_assets()
		return
	for size_text in sizes:
		_build(int(size_text), runs, gd_runs, fill)
	ScatterNative.force_gdscript = false


## Triangles, vertices, surfaces and textures of every asset the palette serves (each GLB loaded
## as the game resolves it), sorted by triangles.
func _assets() -> void:
	var assets: Dictionary = PaletteLibrary.get_palette()["assets"]
	var lines: Array[String] = []
	var seen_tex := {}
	var tex_bytes := 0
	for asset_id in assets:
		var entry: Dictionary = assets[asset_id]
		var got := PaletteLibrary.resolve(asset_id)
		if got.is_empty():
			continue
		var mesh: Mesh = got.mesh
		var verts := 0
		var texs: Array[String] = []
		for s in mesh.get_surface_count():
			verts += mesh.surface_get_array_len(s)
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				for tex: Texture2D in [
					(mat as BaseMaterial3D).albedo_texture,
					(mat as BaseMaterial3D).normal_texture,
					(mat as BaseMaterial3D).orm_texture if mat is ORMMaterial3D else null
				]:
					if tex == null:
						continue
					var img := tex.get_image()
					var fmt := img.get_format() if img else -1
					var mips := img.has_mipmaps() if img else false
					texs.append("%dx%d f%d m%s" % [tex.get_width(), tex.get_height(), fmt, str(mips)])
					var key := "%s|%d" % [str(tex.get_rid()), tex.get_width()]
					if img and not seen_tex.has(key):
						seen_tex[key] = true
						tex_bytes += img.get_data().size()
		lines.append(
			(
				"FB| asset %-50s %-7s %-6s tris %6d verts %6d surf %d dims %s tex %s"
				% [
					asset_id,
					String(entry.get("size_class", "")),
					String(entry.get("wind_category", "")),
					FoliageBudget.primitives_per_instance(mesh),
					verts,
					mesh.get_surface_count(),
					str(entry.get("dimensions_m", "")),
					", ".join(texs)
				]
			)
		)
	for l in lines:
		print(l)
	print(
		(
			"FB| assets %d, distinct texture images %d, %.1f MB of image data as loaded"
			% [lines.size(), seen_tex.size(), tex_bytes / 1048576.0]
		)
	)


func _build(size_ft: int, runs: int, gd_runs: int, fill: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var doc := NewMap.create(size_ft, BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, LANDFORM)
	var doc_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if fill:
		for i in doc.sample_count():
			doc.biome_slots[i] = 1
			doc.biome_density[i] = 255
		print("FB| filled %d samples with %s at 255" % [doc.sample_count(), doc.biome_ids[0]])
	var native_ms := PackedFloat64Array()
	var gd_ms := PackedFloat64Array()
	var result := {}
	for r in maxi(runs, gd_runs):
		if r < runs:
			ScatterNative.force_gdscript = false
			result = _scatter(doc)
			native_ms.append(result.ms)
		if r < gd_runs:
			ScatterNative.force_gdscript = true
			gd_ms.append(_scatter(doc).ms)
	ScatterNative.force_gdscript = false
	print(
		(
			(
				"FB| size %d ft: %d x %d cells, %d samples, extent %s m; document %.0f ms;"
				+ " scatter native median %.0f ms %s, GDScript median %.0f ms %s, %d jobs (%d workers)"
			)
			% [
				size_ft,
				doc.size_cells.x,
				doc.size_cells.y,
				doc.sample_count(),
				str(doc.extent_m()),
				doc_ms,
				_median(native_ms),
				str(native_ms),
				_median(gd_ms),
				str(gd_ms),
				result.jobs,
				result.workers
			]
		)
	)
	_census(size_ft, result.rows_by_cell)


## Every cell of `doc` through ScatterRegen's jobs: {ms, jobs, workers, rows_by_cell}.
func _scatter(doc: MapDocument) -> Dictionary:
	var regen := ScatterRegen.for_document(doc)
	for biome_id in doc.biome_ids:
		regen.set_biome(biome_id, PaletteLibrary.species(biome_id))
	regen.built_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("built"))
	regen.cliff_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	var snapshot := ScatterRegen.snapshot(doc)
	var limit := clampi(OS.get_processor_count() >> 1, 1, AuthoredScatter.MAX_JOBS)
	var started := Time.get_ticks_usec()
	regen.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var running: Array[Dictionary] = []
	var jobs := 0
	var rows_by_cell := {}
	while regen.has_pending() or not running.is_empty():
		while running.size() < limit:
			var job := regen.take_job()
			if job.is_empty():
				break
			var holder := {"job": job, "result": {}}
			holder["id"] = WorkerThreadPool.add_task(
				func() -> void: holder.result = ScatterRegen.run(snapshot, job.work)
			)
			running.append(holder)
			jobs += 1
		var first: Dictionary = running.pop_front()
		WorkerThreadPool.wait_for_task_completion(first.id)
		regen.accept(first.job)
		var got: Dictionary = first.result.get("rows_by_cell", {})
		for cell in got:
			rows_by_cell[cell] = got[cell]
	return {
		"ms": (Time.get_ticks_usec() - started) / 1000.0,
		"jobs": jobs,
		"workers": limit,
		"rows_by_cell": rows_by_cell
	}


func _census(size_ft: int, rows_by_cell: Dictionary) -> void:
	var per_asset := {}
	for cell in rows_by_cell:
		var assets: Dictionary = rows_by_cell[cell]
		for asset_id in assets:
			var n: int = (assets[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
			if n == 0:
				continue
			var rec: Dictionary = per_asset.get(asset_id, {"instances": 0, "cells": 0})
			rec.instances += n
			rec.cells += 1
			per_asset[asset_id] = rec
	var per_cat := {}
	var total := 0
	var nodes := 0
	var tris_total := 0
	var ids := per_asset.keys()
	ids.sort_custom(func(a, b): return per_asset[a].instances > per_asset[b].instances)
	for asset_id in ids:
		var entry := PaletteLibrary.asset(asset_id)
		var cat := String(entry.get("category", entry.get("size_class", "?")))
		var tris := int(entry.get("triangles", 0))
		var rec: Dictionary = per_asset[asset_id]
		total += rec.instances
		nodes += rec.cells
		tris_total += rec.instances * tris
		var c: Dictionary = per_cat.get(cat, {"instances": 0, "nodes": 0, "tris": 0, "assets": 0})
		c.instances += rec.instances
		c.nodes += rec.cells
		c.tris += rec.instances * tris
		c.assets += 1
		per_cat[cat] = c
		print(
			(
				"FB| size %d asset %-36s %-12s %-7s tris %6d inst %6d cells %4d prims %9d"
				% [
					size_ft,
					asset_id,
					cat,
					String(entry.get("size_class", "")),
					tris,
					rec.instances,
					rec.cells,
					rec.instances * tris
				]
			)
		)
	for cat in per_cat:
		var c: Dictionary = per_cat[cat]
		print(
			(
				"FB| size %d category %-12s assets %3d instances %7d nodes %5d primitives %10d"
				% [size_ft, cat, c.assets, c.instances, c.nodes, c.tris]
			)
		)
	print(
		(
			(
				"FB| size %d total: %d instances, %d (asset, cell) nodes, %d primitives at full"
				+ " density, rows %.2f MB (40 B each), MultiMesh transforms %.2f MB (48 B each,"
				+ " held twice: CPU cache and GPU buffer)"
			)
			% [
				size_ft,
				total,
				nodes,
				tris_total,
				total * 40.0 / 1048576.0,
				total * 48.0 / 1048576.0
			]
		)
	)


func _median(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]
