extends GutTest

## Unit tests for SplashBurst -- confirms entry vs exit produce different intensity
## (particle count/lifetime), matching the bigger-splash-on-entry, smaller-on-exit design
## (see the design spec's "Particle burst modularity" section).


func test_entry_splash_has_more_particles_and_longer_lifetime_than_exit() -> void:
	var entry := SplashBurst.create_at(Vector3.ZERO, true)
	add_child_autofree(entry)
	var exit := SplashBurst.create_at(Vector3.ZERO, false)
	add_child_autofree(exit)

	assert_gt(entry.amount, exit.amount)
	assert_gt(entry.lifetime, exit.lifetime)


func test_create_at_sets_spawn_position() -> void:
	var splash := SplashBurst.create_at(Vector3(2, 0, 5), true)
	add_child_autofree(splash)

	assert_eq(splash.global_position, Vector3(2, 0, 5))
