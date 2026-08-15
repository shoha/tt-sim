extends GutTest

## Regression tests for the OneShotParticleBurst3D base-class extraction -- confirms
## DustBurst and SparkleBurst still configure the same particle settings after being
## refactored to subclass the shared base.


func test_dust_burst_configures_expected_particle_settings() -> void:
	var dust := DustBurst.create_at(Vector3(1, 2, 3))
	add_child_autofree(dust)

	assert_eq(dust.global_position, Vector3(1, 2, 3))
	assert_eq(dust.amount, DustBurst.PARTICLE_COUNT)
	assert_eq(dust.lifetime, DustBurst.LIFETIME)
	assert_true(dust.one_shot)
	assert_true(dust.process_material is ParticleProcessMaterial)
	assert_true(dust.draw_pass_1 is SphereMesh)
	assert_eq(dust.process_material.color, Color(0.55, 0.50, 0.42, 0.6))


func test_sparkle_burst_configures_expected_particle_settings() -> void:
	var sparkle := SparkleBurst.create_at(Vector3(4, 5, 6))
	add_child_autofree(sparkle)

	assert_eq(sparkle.global_position, Vector3(4, 5, 6))
	assert_eq(sparkle.amount, SparkleBurst.PARTICLE_COUNT)
	assert_eq(sparkle.lifetime, SparkleBurst.LIFETIME)
	assert_true(sparkle.one_shot)
	assert_true(sparkle.process_material is ParticleProcessMaterial)
	assert_true(sparkle.draw_pass_1 is SphereMesh)
	assert_eq(sparkle.process_material.color, Color(1.0, 0.9, 0.5, 0.9))
