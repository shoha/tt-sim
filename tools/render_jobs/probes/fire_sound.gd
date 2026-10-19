extends RefCounted

## Render-job probe (`call` op) for the persistent fire's sound (FireSound, cards F7 and F7b):
## the map's players, each one's gain and place, and the SFX bus's peak over the last mix, so a
## job can show the bus carrying the roar with fire in view and falling silent away from it.
## The bus is read `step.reads` times (default 3), `step.gap_s` apart (default 0.25), on the
## main thread's clock, since one peak reading holds only the last mixed block.


static func run(base: Node, step: Dictionary) -> String:
	var field := base.get_tree().get_first_node_in_group(FireField.GROUP) as FireField
	var sound: FireSound = field.sound() if field != null else null
	var out := "no fire sound"
	if sound != null:
		var places := PackedStringArray()
		for player in sound.players():
			places.append("(%.1f, %.1f) %.1f dB" % [player.position.x, player.position.z, player.volume_db])
		out = "players %d, gains %s, %s" % [sound.players().size(), str(sound.gains()), ", ".join(places)]
	var bus := AudioServer.get_bus_index(AudioManager.BUS_SFX)
	var peaks := PackedStringArray()
	var reads := int(step.get("reads", 3))
	for k in reads:
		if k > 0:
			OS.delay_msec(int(1000.0 * float(step.get("gap_s", 0.25))))
		var left := AudioServer.get_bus_peak_volume_left_db(bus, 0)
		var right := AudioServer.get_bus_peak_volume_right_db(bus, 0)
		peaks.append("%.1f/%.1f" % [left, right])
	return "%s; SFX bus peak L/R dB: %s" % [out, " ".join(peaks)]
