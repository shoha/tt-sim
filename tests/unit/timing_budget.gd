class_name TimingBudget
extends RefCounted
## Wall-clock limits in tests that hold on a slow machine without going blind on a fast one.
##
## A test that times something states its limit as tuned on the dev machine during the sharded
## gate (8 shards at once, the load the limits were set under) and asserts against
## `TimingBudget.limit(base)` instead. The limit is the base times this machine's factor: how much
## slower than the dev machine a fixed small workload runs here, timed once per process (the best
## of REPEATS runs, so one slow frame does not count), never below 1 and at most MAX_FACTOR. On the
## dev machine the factor is about 1 and the limits are what they were; on a CI runner 1.5 to 3
## times slower, every limit grows by the same ratio, so a test still fails at the same multiple of
## its usual time: a limit that caught a 2x regression on the dev machine catches it there too.
##
## Use it for budgets (a derive under N ms, a frame part near its budget). A bound that proves a
## call never waits for a held resource (a pool held for HOLD_MS, a bound of half that) does not
## scale: its margin is the hold, not the machine. Each shard's log carries one
## "TimingBudget: ..." line with the measurement, and tools/gut_shards.gd prints it per shard.

## The workload's best time on the dev machine (24 threads) inside an 8-shard gate, in ms
## (3.2 to 3.5 across the eight shards on 2026-11-23).
const REFERENCE_MS := 3.3
## A factor past this is a broken measurement, not a slow machine.
const MAX_FACTOR := 4.0
const REPEATS := 7
## Size of the workload: a GDScript loop over this many floats, then a native sort of them.
const WORK_SIZE := 20000

static var _calibration_ms := -1.0


## This machine's slowness against the reference: the workload's best time over REFERENCE_MS,
## clamped to [1, MAX_FACTOR]. Measured on the first call in a process, then kept.
static func factor() -> float:
	return clampf(calibration_ms() / REFERENCE_MS, 1.0, MAX_FACTOR)


## `base` (a limit tuned on the dev machine, any unit) scaled by factor().
static func limit(base: float) -> float:
	return base * factor()


## The workload's best time in ms in this process (measured once).
static func calibration_ms() -> float:
	if _calibration_ms < 0.0:
		var best := INF
		for _i in REPEATS:
			var t0 := Time.get_ticks_usec()
			workload()
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		_calibration_ms = best
		print(
			(
				"TimingBudget: calibration %.2f ms (reference %.2f), factor %.2f"
				% [best, REFERENCE_MS, clampf(best / REFERENCE_MS, 1.0, MAX_FACTOR)]
			)
		)
	return _calibration_ms


## A message tail naming a scaled limit: "limit 270.0 = 180 x 1.50".
static func describe(base: float) -> String:
	return "limit %.1f = %s x %.2f" % [limit(base), str(base), factor()]


## The fixed workload: interpreted float arithmetic into a packed array, then a native sort of it
## (the tests time both kinds of code). Returns a checksum so nothing is skipped.
static func workload() -> float:
	var values := PackedFloat32Array()
	values.resize(WORK_SIZE)
	var seed_value := 12345
	for i in WORK_SIZE:
		seed_value = (seed_value * 1103515245 + 12345) & 0x7FFFFFFF
		values[i] = sin(float(seed_value) * 1e-6) * float(i % 97)
	values.sort()
	return values[0] + values[WORK_SIZE - 1]
