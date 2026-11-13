class_name PainterMannerBake
extends RefCounted

## PROBE (card painter-manner, candidate C; delete with the probe if it is not chosen): a building's
## face strokes (PainterMannerStrokes.face) baked ONCE into a small texture, so the painted pass
## samples it instead of drawing strokes. Each wall face, roof slope and gable end gets its own
## rectangle at PX_M pixels a metre in its own (u, v) metres (the record's frame is a natural
## unwrap); a stroke is a stamp blended in (Image.blend_rect, native), red the darkening, green the
## lightening, alpha its brush (dry gaps, tapered ends), so a later stroke covers an earlier one as
## paint does. Mipmapped: a far view reads the average and costs one texture read like a near one.
## Pure and worker-safe (Images only).

const PX_M := 32.0
const PAD := 2
const WIDTH := 1024
const LEN_STEP := 4
## Stamps are made per (length px, width px, along v, dark) and kept per bake.


## Shelf-packs the face records `recs` (largest first). Returns {"size": Vector2i, "rects": {id:
## Rect2i}}; the first PAD pixels of the first row stay blank (where a piece with no face reads).
## Pure.
static func pack(recs: Array) -> Dictionary:
	var order := recs.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["v_len"] > b["v_len"])
	var rects: Dictionary = {}
	var x := PAD * 4
	var y := PAD
	var shelf := 0
	for rec: Dictionary in order:
		var w := ceili(float(rec["u_len"]) * PX_M) + PAD * 2
		var h := ceili(float(rec["v_len"]) * PX_M) + PAD * 2
		w = mini(w, WIDTH - PAD * 2)
		if x + w > WIDTH:
			x = PAD
			y += shelf
			shelf = 0
		rects[str(rec["id"])] = Rect2i(x + PAD, y + PAD, w - PAD * 2, h - PAD * 2)
		x += w
		shelf = maxi(shelf, h)
	return {"size": Vector2i(WIDTH, maxi(4, nearest_po2(y + shelf))), "rects": rects}


## The baked texture: `strokes` id -> strokes of that face record, `packing` from pack(). Pure.
static func bake(strokes: Dictionary, packing: Dictionary) -> Image:
	var size: Vector2i = packing["size"]
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	var stamps: Dictionary = {}
	for id: String in strokes:
		var rect: Rect2i = packing["rects"].get(id, Rect2i())
		if rect.size == Vector2i.ZERO:
			continue
		for s: Array in strokes[id]:
			var along_v := absf(sin(float(s[PainterMannerStrokes.ANG]))) > 0.7
			var len_px := maxi(LEN_STEP, snappedi(float(s[PainterMannerStrokes.LEN]) * PX_M, LEN_STEP))
			var wid_px := maxi(2, roundi(float(s[PainterMannerStrokes.WID]) * PX_M))
			var value := float(s[PainterMannerStrokes.VAL])
			var dark := value < 1.0
			var key := Vector4i(len_px, wid_px, int(along_v), int(dark))
			if not stamps.has(key):
				stamps[key] = _stamp(len_px, wid_px, along_v, dark)
			var stamp: Image = stamps[key]
			var cx := rect.position.x + float(s[PainterMannerStrokes.U]) * PX_M
			var cy := rect.position.y + float(s[PainterMannerStrokes.V]) * PX_M
			var at := Vector2i(roundi(cx - stamp.get_width() * 0.5), roundi(cy - stamp.get_height() * 0.5))
			var src := Rect2i(Vector2i.ZERO, stamp.get_size())
			# Clipped to the piece's own rectangle.
			var clip := Rect2i(at, stamp.get_size()).intersection(rect)
			if clip.size.x <= 0 or clip.size.y <= 0:
				continue
			src.position = clip.position - at
			src.size = clip.size
			image.blend_rect(stamp, src, clip.position)
	# Two channels are all the shader reads: half the memory of RGBA.
	image.convert(Image.FORMAT_RG8)
	image.generate_mipmaps()
	return image


## One stroke's stamp: tapered ends, a soft edge across, dry gaps along it. Pure.
static func _stamp(len_px: int, wid_px: int, along_v: bool, dark: bool) -> Image:
	var w := wid_px if along_v else len_px
	var h := len_px if along_v else wid_px
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var amount := 0.55 if dark else 0.45
	for y in h:
		for x in w:
			var t := (float(y) + 0.5) / h if along_v else (float(x) + 0.5) / w
			var s := (float(x) + 0.5) / w if along_v else (float(y) + 0.5) / h
			var along := minf(t, 1.0 - t)
			var mask := smoothstep(0.0, 0.18, along) * (1.0 - smoothstep(0.32, 0.5, absf(s - 0.5)))
			var grain := float(hash(Vector2i(roundi(s * 5.0), roundi(t * len_px * 0.5))) % 100) / 100.0
			mask *= 1.0 if grain > 0.22 else 0.25
			var c := Color(amount, 0.0, 0.0, mask) if dark else Color(0.0, amount, 0.0, mask)
			image.set_pixel(x, y, c)
	return image
