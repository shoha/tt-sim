class_name ScatterMass
extends RefCounted

## Grass gathered into masses (contract: docs/ASSET_PIPELINE.md section 9, "Species clump, mass
## fields"). A clumped species whose clump sets `mass` 1 (ScatterPlan.MASS_FIELDS) keeps the
## union of its clumps (never the additive sum), its clumps may be ellipses turned per parent,
## its tufts grow toward each clump's core into one mound, and each placed row remembers its
## clump parent, the mass anchor, where the grass shader reads the zone colour so every tuft of
## one mass takes one hue. Fewer, larger swathes are dropped whole by the zones the ground draws
## (GroundZones, through the entry's zone record: zone_keep, zone_family, zone_core, zone_share,
## zone_fill) and kept off the biome's bare openings (`bare`) and back from where the ground
## thins (`shoulder_m`).
##
## Anchors. The rows (MapDocument.ROW_STRIDE) have no slot for the anchor, so the anchors travel
## beside them as a table keyed by the row's saved (x, z) position, its value the offset from the
## row to its parent: ScatterGenerator.generate_species_cells fills a caller's table (collect),
## ScatterRegen.run returns it as "anchors", and AuthoredScatter keeps one table on the main
## thread and hands it to ScatterGlbUtils.build_multimesh, which writes each offset into the
## instance's custom data as Color(0, dx, dz, 1) (.x stays 0: wind_foliage_burn reads it on
## burning trees; .w 1 marks an anchored instance). A level saves the table as its optional
## anchors entry (anchors_entry, MapDocument.mass_anchors) and a load rebuilds it (table_of).
##
## Every function here is pure or writes only a caller-owned table, and reads the zone record
## from the plan entry, so the worker threads share nothing mutable.

## Past this many anchors a holder's table starts over (a long session of regenerated maps).
const MAX_ANCHORS := 2000000
## The hash salt of a mass parent's zone keep (zone_kept).
const SALT_ZONE := 0x4C957F2D
## Each zone its own family (clump zone_family when absent).
const FAMILY_SELF := [0, 1, 2, 3]
## The shoulder's four probe directions and its ease (shoulder_keep).
const SHOULDER_DIRS := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
const SHOULDER_LO := 0.5
const SHOULDER_HI := 0.9
## The rings (shares of the swathe's reach) and spokes a parent's fill is sampled on, and the
## rings under FILL_CORE_RING that drop their parent when in a bare opening (filled).
const FILL_RINGS := [0.0, 0.45, 0.85]
const FILL_SPOKES := 8
const FILL_CORE_RING := 0.5
## Slack (metres) over a rule's reach a loaded anchor offset may have (float32 rounding).
const ANCHOR_SLACK_M := 0.01


## The offset from a placed mass row at `origin` (the rows' frame) to its clump parent in
## `table` (collect's form), or null.
static func anchor_in(table: Dictionary, origin: Vector3) -> Variant:
	if table.is_empty():
		return null
	return table.get(Vector2(origin.x, origin.z))


## The instance custom data of `transforms` under `table` (ScatterGlbUtils.build_multimesh):
## Color(0, dx, dz, 1) for an anchored instance, null for one without an anchor, or [] when none
## is anchored (the MultiMesh then has no custom data).
static func custom_data(table: Dictionary, transforms: Array[Transform3D]) -> Array:
	if table.is_empty():
		return []
	var out := []
	out.resize(transforms.size())
	var any := false
	for i in transforms.size():
		var offset: Variant = anchor_in(table, transforms[i].origin)
		if offset != null:
			out[i] = Color(0.0, offset.x, offset.y, 1.0)
			any = true
	return out if any else []


## Adds each placed row's offset to its parent to `out` (caller-owned, never shared between
## threads): `anchors` holds one parent (x, z) per row of `placed`, keyed by the row's saved
## position (MapDocumentIO.snap_rows, idempotent).
@warning_ignore("integer_division")
static func collect(
	placed: PackedFloat32Array, anchors: PackedFloat32Array, out: Dictionary
) -> void:
	var rows := placed.duplicate()
	MapDocumentIO.snap_rows(rows)
	var stride := MapDocument.ROW_STRIDE
	for r in anchors.size() / 2:
		var x := rows[r * stride]
		var z := rows[r * stride + 2]
		out[Vector2(x, z)] = Vector2(anchors[r * 2] - x, anchors[r * 2 + 1] - z)


## Merges a job's `fresh` anchors into a holder's `table`, starting over past MAX_ANCHORS.
static func merge_into(table: Dictionary, fresh: Dictionary) -> void:
	if fresh.is_empty():
		return
	if table.size() + fresh.size() > MAX_ANCHORS:
		table.clear()
	table.merge(fresh, true)


## A level's anchors entry for `rows_by_asset` (MapDocument.scatter's form) under `table`: per
## asset id with any anchored row, (dx, dz) per row in row order. A row of such an asset without
## an anchor (a row no mass placed) gets (0, 0), its own anchor. Pure.
@warning_ignore("integer_division")
static func anchors_entry(
	table: Dictionary, rows_by_asset: Dictionary
) -> Dictionary[String, PackedFloat32Array]:
	var out: Dictionary[String, PackedFloat32Array] = {}
	if table.is_empty():
		return out
	var stride := MapDocument.ROW_STRIDE
	for asset_id: String in rows_by_asset:
		var rows: PackedFloat32Array = rows_by_asset[asset_id]
		var offsets := PackedFloat32Array()
		offsets.resize(rows.size() / stride * 2)
		var any := false
		for r in rows.size() / stride:
			var offset: Variant = table.get(Vector2(rows[r * stride], rows[r * stride + 2]))
			if offset != null:
				offsets[r * 2] = offset.x
				offsets[r * 2 + 1] = offset.y
				any = true
		if any:
			out[asset_id] = offsets
	return out


## The anchor table of a level's anchors `entry` over its `rows_by_asset`: an asset's offsets are
## dropped with a warning when their count is not two per row, when the asset belongs to no mass
## rule (`reach_by_asset`, reach_by_asset()'s form) or when one lies beyond its rule's reach.
@warning_ignore("integer_division")
static func table_of(
	entry: Dictionary,
	rows_by_asset: Dictionary,
	reach_by_asset: Dictionary,
	warnings: Array[String]
) -> Dictionary:
	var table := {}
	var stride := MapDocument.ROW_STRIDE
	for asset_id: String in entry:
		var offsets: PackedFloat32Array = entry[asset_id]
		var rows: PackedFloat32Array = rows_by_asset.get(asset_id, PackedFloat32Array())
		var reach := float(reach_by_asset.get(asset_id, 0.0))
		var problem := ""
		if offsets.size() != rows.size() / stride * 2:
			problem = "%d offsets for %d rows" % [offsets.size() / 2, rows.size() / stride]
		elif reach <= 0.0:
			problem = "not a grass-mass asset"
		elif _farthest(offsets) > reach + ANCHOR_SLACK_M:
			problem = "an offset beyond the reach of %.2f m" % reach
		if problem != "":
			warnings.append("mass anchors of '%s' dropped: %s" % [asset_id, problem])
			continue
		for r in rows.size() / stride:
			var key := Vector2(rows[r * stride], rows[r * stride + 2])
			table[key] = Vector2(offsets[r * 2], offsets[r * 2 + 1])
	return table


## Asset id -> the reach (metres) of its mass rule, the farthest a row can stand from its parent,
## over the palette biomes `biome_ids`: the parent's largest radius plus the transition, times
## the ellipse's long half-axis.
static func reach_by_asset(
	biome_ids: PackedStringArray, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	var out := {}
	for biome_id in biome_ids:
		for rule in PaletteLibrary.species(biome_id, root):
			var clump: Variant = rule.get("clump")
			if not clump is Dictionary or float(clump.get("mass", 0.0)) < 0.5:
				continue
			var jitter := float(clump.get("radius_jitter", ScatterPlan.CLUMP_RADIUS_JITTER))
			var reach := (
				(float(clump.radius_m) * (1.0 + jitter) + float(clump.transition_m))
				* sqrt(maxf(float(clump.get("stretch", 1.0)), 1.0))
			)
			for asset_id: String in rule.assets:
				out[asset_id] = maxf(float(out.get(asset_id, 0.0)), reach)
	return out


static func _farthest(offsets: PackedFloat32Array) -> float:
	var most := 0.0
	for i in range(0, offsets.size(), 2):
		most = maxf(most, Vector2(offsets[i], offsets[i + 1]).length())
	return most


## Appends a row's scale (x, y, z) to `rows`: `scale` on every axis, except that a mass tuft
## (the plan entry's mass_core and mass_core_y: clump core_scale and core_height) grows toward
## its clump centre by 1 + (core - 1) * (1 - edge^2), its width by mass_core and its height by
## mass_core_y, so the core tufts overlap into one mound and the rim ones stay the size of fine
## cover. `edge` is 0 at the clump centre, 1 at its rim. The height is held at most
## mass_core_y_max (clump core_height_m over the rule's tallest asset), never below the tuft's own
## scale, so a mass grows wide and stays low.
static func append_scale(
	rows: PackedFloat32Array, scale: float, entry: Dictionary, edge: float
) -> void:
	var core: float = entry.get("mass_core", 1.0)
	var core_y: float = entry.get("mass_core_y", 1.0)
	if not entry.get("mass", false) or (core == 1.0 and core_y == 1.0):
		rows.append(scale)
		rows.append(scale)
		rows.append(scale)
		return
	var dome := _dome(edge)
	var width := scale * (1.0 + (core - 1.0) * dome)
	var height := scale * (1.0 + (core_y - 1.0) * dome)
	var cap: float = entry.get("mass_core_y_max", 0.0)
	if cap > 0.0:
		height = minf(height, maxf(cap, scale))
	rows.append(width)
	rows.append(height)
	rows.append(width)


## The growth profile over clump edge distance: 1 at the centre, 0 at the rim.
static func _dome(edge: float) -> float:
	var e := clampf(edge, 0.0, 1.0)
	return 1.0 - e * e


## Clump membership at (x, z) over `parents` ([x, z, radius, angle] records): x = 0..1 (1
## inside a parent's radius, smoothly to 0 across the transition), y = the distance to that
## parent over its reach (0 at the centre, 1 at the outer edge). Additive clumps
## (ScatterPlan.additive_clumps, never for a mass species) sum every clump over
## ScatterPlan.CLUMP_SATURATION and take the nearest centre's y. With `stretch` > 1 each clump
## is an ellipse of the same area along its parent's angle. The chosen parent goes to ctx.anchor.
static func membership(
	ctx: Dictionary, entry: Dictionary, parents: PackedFloat64Array, x: float, z: float
) -> Vector2:
	var transition: float = entry.rule.clump.transition_m
	var best := Vector2(0.0, 1.0)
	var stretch: float = entry.get("mass_stretch", 1.0)
	var root := sqrt(stretch)
	var mass: bool = entry.get("mass", false)
	var additive: bool = ScatterPlan.additive_clumps and not mass
	var total := 0.0
	for i in range(0, parents.size(), 4):
		var dx := parents[i] - x
		var dz := parents[i + 1] - z
		if stretch > 1.0:
			# Into the ellipse's frame: the long axis shrunk, the short one grown.
			var ca := cos(parents[i + 3])
			var sa := sin(parents[i + 3])
			var along := (dx * ca + dz * sa) / root
			dz = (dz * ca - dx * sa) * root
			dx = along
		var radius := parents[i + 2]
		var d := sqrt(dx * dx + dz * dz)
		var inside := 1.0
		if d > radius:
			if transition <= 0.0 or d >= radius + transition:
				continue
			inside = 1.0 - smoothstep(radius, radius + transition, d)
		var edge := d / (radius + transition)
		total += inside
		if additive:
			if edge < best.y:
				best.y = edge
				ctx.anchor = Vector2(parents[i], parents[i + 1])
		elif inside > best.x or (inside == best.x and edge < best.y):
			best = Vector2(inside, edge)
			ctx.anchor = Vector2(parents[i], parents[i + 1])
	if additive:
		best.x = minf(1.0, total / ScatterPlan.CLUMP_SATURATION)
	elif mass:
		best.y = held_edge(entry, best.y)
		if best.x > 0.0:
			best.x *= zone_share_keep(ctx, entry, x, z)
		if best.x > 0.0:
			best.x *= shoulder_keep(ctx, entry, x, z)
	return best


## A mass child's clump edge distance with its core held (clump core_hold, 0..0.95): 0 out to
## that share of the reach, then rising to 1 at the rim, so the tufts of a lone swathe grow
## (append_scale) and shrink (edge_shrink) as at its centre out to near its rim and it reads as
## solid as several overlapping ones; unchanged at 0.
static func held_edge(entry: Dictionary, edge: float) -> float:
	var hold: float = entry.get("mass_core_hold", 0.0)
	if hold <= 0.0:
		return edge
	return clampf((edge - hold) / (1.0 - hold), 0.0, 1.0)


## 0 where the rule's ground thins within clump shoulder_m of (x, z): the least of the species
## density at four points that far along the axes, over the density here, eased from SHOULDER_LO
## to SHOULDER_HI. A swathe so stands back from a path (and a rock or the water) by about that
## much beyond the ground's own fringe (ScatterGround); 1 without shoulder_m.
static func shoulder_keep(ctx: Dictionary, entry: Dictionary, x: float, z: float) -> float:
	var rule: Dictionary = entry.get("mass_zone", {})
	var reach := float(rule.get("shoulder", 0.0))
	if reach <= 0.0 or not ctx.has("species_density_at"):
		return 1.0
	var at := Vector2(x, z)
	var role: int = entry.ground_role
	var own: float = ctx.species_density_at.call(at, role)
	if own <= 0.0:
		return 1.0
	var least := 1.0
	for dir: Vector2 in SHOULDER_DIRS:
		least = minf(least, float(ctx.species_density_at.call(at + dir * reach, role)) / own)
	return smoothstep(SHOULDER_LO, SHOULDER_HI, least)


## A mass rule's zone fields (clump zone_keep, zone_family, zone_core, zone_share, zone_fill and
## shoulder_m) for its plan entry: {keep: PackedFloat32Array of four, family: PackedInt32Array of
## four, shoulder, core, share, fill}, or {} when the clump sets none of them.
static func zone_rule(clump: Dictionary) -> Dictionary:
	var keep := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var family := PackedInt32Array(FAMILY_SELF)
	var raw_keep: Variant = clump.get("zone_keep")
	var raw_family: Variant = clump.get("zone_family")
	for k in 4:
		if raw_keep is Array and raw_keep.size() == 4:
			keep[k] = clampf(float(raw_keep[k]), 0.0, 1.0)
		if raw_family is Array and raw_family.size() == 4:
			family[k] = clampi(int(raw_family[k]), 0, 3)
	var shoulder := float(clump.get("shoulder_m", 0.0))
	var core := float(clump.get("zone_core", 0.0))
	var share := float(clump.get("zone_share", 0.0))
	var fill := float(clump.get("zone_fill", 0.0))
	var any := raw_keep is Array or raw_family is Array
	if not any and maxf(maxf(shoulder, fill), maxf(core, share)) <= 0.0:
		return {}
	return {
		"keep": keep,
		"family": family,
		"shoulder": shoulder,
		"core": core,
		"share": share,
		"fill": fill,
	}


## Whether a mass parent (the candidate at cands[c]) survives its zone: kept with the share
## zone_keep of the zone that draws strongest at it, only where that zone's family holds at least
## zone_core of the drawn colour, and only when its swathe fills (filled). So whole swathes are
## dropped zone by zone (calm ground without thinning any swathe). True without zone fields or a
## zone record.
static func zone_kept(entry: Dictionary, cands: PackedFloat64Array, c: int) -> bool:
	var rule: Dictionary = entry.get("mass_zone", {})
	var zones: Dictionary = entry.get("mass_zones", {})
	if rule.is_empty() or zones.is_empty():
		return true
	var keep: PackedFloat32Array = rule.keep
	var u := ScatterGenerator._unit(int(cands[c + 5]), SALT_ZONE)
	var w := GroundZones.zone_weights(zones, cands[c], cands[c + 1])
	var zone := _strongest(w)
	var family: int = rule.family[zone]
	if u >= keep[zone] or family_share(w, rule.family, family) < float(rule.core):
		return false
	return filled(entry, family, cands[c], cands[c + 1])


## 1 where the family of the zone at the child's clump parent (ctx.anchor, set by membership)
## holds at least clump zone_share of the drawn zone weights at (x, z), else 0, so a stand stays
## where its ground mostly shows its own hue's strokes. The parents' families are memoized in
## ctx. 1 without zone_share or a zone record.
static func zone_share_keep(ctx: Dictionary, entry: Dictionary, x: float, z: float) -> float:
	var rule: Dictionary = entry.get("mass_zone", {})
	var zones: Dictionary = entry.get("mass_zones", {})
	var share := float(rule.get("share", 0.0))
	if share <= 0.0 or zones.is_empty():
		return 1.0
	var memo: Dictionary = ctx.get_or_add("mass_zones", {})
	var anchor: Vector2 = ctx.anchor
	var family: PackedInt32Array = rule.family
	var home: Variant = memo.get(anchor)
	if home == null:
		home = family[_strongest(GroundZones.zone_weights(zones, anchor.x, anchor.y))]
		memo[anchor] = home
	var w := GroundZones.zone_weights(zones, x, z)
	return 1.0 if family_share(w, family, int(home)) >= share else 0.0


## Whether at least clump zone_fill of a mass parent's swathe at (x, z) stands on ground its zone
## family `family` holds at zone_share or more and outside the bare openings (bare_keep a half or
## more): its centre and FILL_SPOKES points on each of FILL_RINGS over its ellipse (radius_m,
## stretch, turned as parent_angle turns it, without the jitter). A parent whose swathe a zone
## edge or a clearing would clip to a few fans is so dropped whole, and one with its centre or an
## inner-ring point (rings under FILL_CORE_RING) in a bare opening is dropped outright, so no
## swathe's body is cut along a clearing's rim. True without zone_fill.
static func filled(entry: Dictionary, family: int, x: float, z: float) -> bool:
	var rule: Dictionary = entry.get("mass_zone", {})
	var fill := float(rule.get("fill", 0.0))
	if fill <= 0.0:
		return true
	var zones: Dictionary = entry.get("mass_zones", {})
	var clump: Dictionary = entry.rule.clump
	var radius := float(clump.radius_m)
	var root := sqrt(maxf(float(entry.get("mass_stretch", 1.0)), 1.0))
	var angle := parent_angle(entry, x, z, deg_to_rad(float(clump.get("angle_deg", 0.0))))
	var along := Vector2(cos(angle), sin(angle)) * radius * root
	var across := Vector2(-sin(angle), cos(angle)) * radius / root
	var bare: Array = entry.get("mass_bare", [])
	var hits := 0
	var total := 0
	for ring: float in FILL_RINGS:
		for i in 1 if ring <= 0.0 else FILL_SPOKES:
			var t := TAU * i / FILL_SPOKES
			var p := Vector2(x, z) + (along * cos(t) + across * sin(t)) * ring
			total += 1
			if bare_keep(bare, p.x, p.y) < 0.5:
				if ring < FILL_CORE_RING:
					return false
				continue
			var w := GroundZones.zone_weights(zones, p.x, p.y)
			if family_share(w, rule.family, family) >= float(rule.share):
				hits += 1
	return hits >= fill * total


## The summed share of the zones of family `family` (zone_family) in weights `w`.
static func family_share(w: PackedFloat64Array, families: PackedInt32Array, family: int) -> float:
	var total := 0.0
	for k in 4:
		total += w[k] if families[k] == family else 0.0
	return total


static func _strongest(w: PackedFloat64Array) -> int:
	var best := 0
	for k in range(1, 4):
		if w[k] > w[best]:
			best = k
	return best


## A kept clump parent's long axis at (x, z) (radians; 0 for a rule that is not a mass): clump
## angle_deg turned by angle_jitter_deg times `turn` (the parent's hashed -1..1), then
## parent_angle.
static func parent_spin(entry: Dictionary, x: float, z: float, turn: float) -> float:
	if not entry.get("mass", false):
		return 0.0
	var clump: Dictionary = entry.rule.clump
	var angle := deg_to_rad(float(clump.get("angle_deg", 0.0)))
	angle += deg_to_rad(float(clump.get("angle_jitter_deg", 0.0))) * turn
	return parent_angle(entry, x, z, angle)


## A clump parent's long-axis angle (radians from +X toward +Z). A mass rule with clump `follow`
## 1 runs its swathes along the contour of the nearest zone edge at the parent
## (GroundZones.zone_flow), turned by its own angle_deg and jitter (`angle`), when the biome has a
## zone record.
static func parent_angle(entry: Dictionary, x: float, z: float, angle: float) -> float:
	var zones: Dictionary = entry.get("mass_zones", {})
	if not entry.get("mass_follow", false) or zones.is_empty():
		return angle
	return GroundZones.zone_flow(zones, x, z) + angle


## ScatterPlan.respond (the painted density through the size class's response) times bare_keep
## over the entry's mass_bare: a biome whose mass rule sets clump `bare` keeps all its grass off
## the bare openings (ScatterPlan.build), not only the masses, so no lone tuft stands in a dirt
## clearing. Called once per candidate (ScatterGenerator._evaluate).
static func respond_bare(entry: Dictionary, painted: float, x: float, z: float) -> float:
	var keep := ScatterPlan.respond(painted, entry.response_lead, entry.response_lag)
	var bare: Array = entry.get("mass_bare", [])
	if keep <= 0.0 or bare.is_empty():
		return keep
	return keep * bare_keep(bare, x, z)


## The biome's ground accents (PaletteLibrary.ground_accents, the bare openings the ground
## shader draws: GroundAccents' CPU twin of its patch mask) as [threshold, scale_m, offset,
## margin, stretch, stretch angle, break, seed] records on map seed `map_seed`, each threshold set
## for its drawn coverage as GroundAccents.row_params does; `margin` is the clump's `bare`. The
## patch shape is the zone record's accent shape, or today's round patches without one.
static func bare_params(biome_id: String, map_seed: int, margin: float, zones: Dictionary) -> Array:
	var accents := PaletteLibrary.ground_accents(biome_id)
	var count := mini(accents.size(), GroundAccents.PER_COMPONENT)
	var coverages := PackedFloat32Array()
	for i in count:
		coverages.append(float(accents[i].get("coverage", 0.0)))
	var drawn := GroundAccents.drawn_coverages(coverages)
	var shape := [
		float(zones.get("accent_stretch", 1.0)),
		float(zones.get("accent_stretch_angle", 0.0)),
		float(zones.get("accent_break", 0.0)),
		map_seed & 0x7fffffff,
	]
	var out := []
	for i in count:
		var offset := GroundAccents.surface_offset(String(accents[i].get("surface", "")), map_seed)
		var scale_m := float(accents[i].get("scale_m", 6.0))
		out.append([GroundAccents.threshold(drawn[i]), scale_m, offset, margin] + shape)
	return out


## The share of a mass child kept at (x, z) under `bare` (bare_params): 0 inside a drawn accent
## patch, rising to 1 over `margin` accent-noise units outside its drawn edge, so a mass stops
## short of a bare opening instead of growing across it. 1 with no records.
static func bare_keep(bare: Array, x: float, z: float) -> float:
	var keep := 1.0
	for record: Array in bare:
		var t: float = float(record[0]) - GroundAccents.EDGE
		keep *= 1.0 - smoothstep(t - float(record[3]), t, _accent_noise(Vector2(x, z), record))
	return keep


## The ground's accent noise (the accent domain with the look's stretch and break, then
## GroundAccents' three octaves) at world `xz` for one bare_params record.
static func _accent_noise(xz: Vector2, record: Array) -> float:
	var rot := GroundAccents.ROTATION
	var q := Vector2(rot.x * xz.x - rot.y * xz.y, rot.y * xz.x + rot.x * xz.y)
	var stretch := float(record[4])
	var warp := float(record[6])
	var p: Vector2 = q / float(record[1]) + Vector2(record[2])
	if stretch != 1.0 or warp > 0.0:
		var cs := Vector2(cos(float(record[5])), sin(float(record[5])))
		var r := Vector2(cs.x * q.x - cs.y * q.y, cs.y * q.x + cs.x * q.y)
		r.x /= maxf(stretch, 0.1)
		p = r / float(record[1]) + Vector2(record[2])
		var s := int(record[7])
		var w := Vector2(
			TerrainRules.value_noise(p * 2.7 + Vector2(5.3, 1.7), s),
			TerrainRules.value_noise(p * 2.7 + Vector2(-8.1, 4.4), s)
		)
		p += warp * (w - Vector2(0.5, 0.5))
	var broad := GroundAccents.octave(p, 0) * (1.0 - GroundAccents.DETAIL - GroundAccents.FINE)
	var detail := GroundAccents.octave(
		p * GroundAccents.DETAIL_SCALE + GroundAccents.DETAIL_OFFSET, 1
	)
	var fine := GroundAccents.octave(p * GroundAccents.FINE_SCALE + GroundAccents.FINE_OFFSET, 2)
	return broad + detail * GroundAccents.DETAIL + fine * GroundAccents.FINE
