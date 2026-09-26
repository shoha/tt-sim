class_name MaskBrush
extends RefCounted

## The pure rules behind authoring's Biome and Thin / Clear brushes: the falloff profile,
## how much one frame under the brush moves a sample, the replacement rule where a new
## biome is painted over another, and how the erase mask of a dressed Blender map thins.
## MaskStroke applies them to a MapDocument; everything here is a pure function so each
## rule is testable on its own.
##
## Falloff. A dab weighs a sample by falloff(distance / radius) = (1 - t^2)^2: 1 at the
## centre, 0.56 halfway, 0 at the rim, with a zero slope at both ends. A zero slope at the
## rim is what keeps a stroke from leaving a visible edge line (a linear or cone falloff
## has a crease there, and the painted density shows it as a ring of trees), and the flat
## top keeps the core of a stroke even.
##
## Exposure, not stamps. A sample under the brush for `seconds` (weighted by the falloff and
## by the dwell gain, see BrushTool) moves toward the brush's target by amount() =
## 1 - exp(-RATE * weight * seconds) of the remaining way. That makes painting frame-rate
## independent (two half frames equal one whole), asymptotic (a density approaches its
## target and never overshoots, so a second stroke over a first one fills in the soft
## edge instead of stacking a hard plateau on it), and gradual: a quick pass lays an open
## cover, lingering thickens it toward the full palette density.
##
## Replacement. A sample stores one biome slot and that biome's density. Painting biome B
## where biome A lives is a contest: A fades by the same amount B would grow on bare
## ground (owner * (1 - a)), and B's would-be density (the challenger, which the stroke
## keeps per sample) grows as on bare ground. The sample changes hands the moment the
## challenger is the denser of the two, and from then on B simply approaches its target.
## So the soft edge of a stroke thins A without replacing it, a light pass leaves a thinned
## A (an open ecotone), and a firm pass replaces A outright. The challenger lives only for
## one stroke; a later stroke starts it from zero against the thinned owner, which then
## yields sooner.
##
## Erase mask (a map.glb dressed by the document). The loader drops a Blender scatter
## instance whose origin falls on a sample above MapDocument.ERASE_THRESHOLD, which is all
## or nothing. The brushes store a thin amount below the threshold (0..ERASE_LEVELS means
## 0..1) and mark a sample erased (255) once that amount passes the sample's own noise
## threshold, a hash of the map seed and the sample. Each Blender instance is thus removed
## with a probability equal to how thinned its spot is, which reads as thinning at the game
## camera instead of a shrinking hole. Clearing compresses the noise thresholds below
## CLEAR_REACH, so a cleared core is erased completely.

const PAINT := 0
const THIN := 1
const CLEAR := 2

## Remaining-way fraction per second at the brush centre (see amount()). At 3 a sample
## that spends a third of a second under the centre of a passing brush reaches about 0.6 of
## the target: a sweep at a natural speed lays an open cover, dwelling fills it in.
const RATE := 3.0
## Clear moves this many times faster than thin, so one pass clears the core of a stroke.
const CLEAR_GAIN := 6.0
## Largest noise threshold a clearing stroke uses: a sample thinned past this is erased.
const CLEAR_REACH := 0.85
## Thin amounts stored in the erase mask: 0..ERASE_LEVELS, all at or below the threshold.
const ERASE_LEVELS := MapDocument.ERASE_THRESHOLD
const ERASED := 255
const _MASK32 := 0xFFFFFFFF


## Weight of a sample at `t` = distance / radius: (1 - t^2)^2, 0 at and beyond the rim.
static func falloff(t: float) -> float:
	if t >= 1.0:
		return 0.0
	var u := 1.0 - t * t
	return u * u


## The fraction of the remaining way to the target one exposure moves a sample:
## 1 - exp(-rate * weight * seconds). Composes: amount(w, a + b) is exactly applying
## amount(w, a) then amount(w, b).
static func amount(weight: float, seconds: float, rate: float = RATE) -> float:
	if weight <= 0.0 or seconds <= 0.0:
		return 0.0
	return 1.0 - exp(-rate * weight * seconds)


## `value` moved `step` (0..1) of the way to `target`.
static func approach(value: float, target: float, step: float) -> float:
	return value + (target - value) * step


## One contest step at a sample owned by another biome (see the header): returns
## Vector3(owner density after, challenger after, 1.0 if the challenger takes the sample).
static func contest(owner: float, challenger: float, target: float, step: float) -> Vector3:
	var faded := owner * (1.0 - step)
	var grown := approach(challenger, target, step)
	return Vector3(faded, grown, 1.0 if grown >= faded and grown > 0.0 else 0.0)


## The erase-mask byte for a thin amount `thinned` (0..1) at a sample whose noise threshold
## is `noise` (0..1): ERASED once the amount reaches the threshold (compressed by
## CLEAR_REACH when `clearing`), else the amount in 0..ERASE_LEVELS.
static func erase_byte(thinned: float, noise: float, clearing: bool) -> int:
	var threshold := noise * (CLEAR_REACH if clearing else 1.0)
	if thinned >= threshold and thinned > 0.0:
		return ERASED
	return clampi(roundi(thinned * ERASE_LEVELS), 0, ERASE_LEVELS)


## The thin amount (0..1) an erase-mask byte stands for; an erased sample is fully thinned.
static func erase_amount(byte: int) -> float:
	if byte > MapDocument.ERASE_THRESHOLD:
		return 1.0
	return float(byte) / float(ERASE_LEVELS)


## The noise threshold (0..1) of sample `index` on a map with `map_seed`: a hash, so the
## same map thins the same instances first every time.
static func sample_noise(map_seed: int, index: int) -> float:
	var h := (index * 0x9E3779B1 + map_seed * 0x85EBCA77) & _MASK32
	h ^= h >> 16
	h = (h * 0x7FEB352D) & _MASK32
	h ^= h >> 15
	h = (h * 0x1B873593) & _MASK32
	h ^= h >> 16
	return float(h) / 4294967296.0


## The samples (grid coordinates, position = first sample, size in samples) a capsule of
## `radius` around the segment `from`-`to` (document-local XZ metres) can touch, clipped to
## the grid of `doc`. Empty when it misses the map.
static func capsule_rect(doc: MapDocument, from: Vector2, to: Vector2, radius: float) -> Rect2i:
	var low := doc.world_to_sample(from.min(to) - Vector2(radius, radius)).floor()
	var high := doc.world_to_sample(from.max(to) + Vector2(radius, radius)).ceil()
	var rect := Rect2i(Vector2i(low), Vector2i(high - low) + Vector2i.ONE)
	return rect.intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))


## World (document-local XZ) rectangle spanned by the samples of `sample_rect`.
static func sample_rect_to_world(doc: MapDocument, sample_rect: Rect2i) -> Rect2:
	if not sample_rect.has_area():
		return Rect2()
	var low := doc.sample_to_world(Vector2(sample_rect.position))
	var high := doc.sample_to_world(Vector2(sample_rect.end - Vector2i.ONE))
	return Rect2(low, high - low)


## `a` merged with `b`, where an empty rectangle is no rectangle (Rect2i.merge would keep
## the origin of an empty one).
static func merge_rect(a: Rect2i, b: Rect2i) -> Rect2i:
	if not a.has_area():
		return b
	if not b.has_area():
		return a
	return a.merge(b)
