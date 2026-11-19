extends GutTest

## A waterfall's crest under the carve (card painter-fall-lip): the crest is the channel's own
## depth under the upper level, between CREST_M's 5 cm and FALL_CREST_DEPTH_M. It was always
## CREST_M deep, which the top-of-bank easing (blend_with_ground) turned into a sill at the
## ground's height beside the channel, so the lip was a narrow notch and the pool above ended
## short of the curtain.


func test_a_falls_crest_is_the_channels_depth_between_five_and_twelve_centimetres() -> void:
	assert_almost_eq(
		WaterCarve.fall_crest_depth(0.02), -WaterCarve.CREST_M, 1e-6, "never under 5 cm"
	)
	assert_almost_eq(WaterCarve.fall_crest_depth(0.08), 0.08, 1e-6, "a shallow channel's own depth")
	assert_almost_eq(
		WaterCarve.fall_crest_depth(0.9), WaterCarve.FALL_CREST_DEPTH_M, 1e-6, "never past the cap"
	)


func test_the_lip_the_pool_tail_and_the_face_agree_on_the_crest() -> void:
	for depth in [0.1, 0.45, 0.9]:
		var crest := 3.0 - WaterCarve.fall_crest_depth(depth)
		var shaped := WaterCarve.fall_shape(0.0, 3.0, 0.0, depth)
		assert_almost_eq(shaped.y, crest, 1e-6, "the face starts at the crest")
		assert_almost_eq(shaped.x, 3.0, 1e-6, "the bank at the lip is the upper level")
		var tail := WaterCarve.step_shape(3.0, 0.0, depth, true)
		assert_almost_eq(tail.x, shaped.y, 1e-6, "the pool tail rises to the same crest")
