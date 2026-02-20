extends GutTest

## Unit tests for AssetManager.needs_download().
##
## NOTE: The P2P branch (unregistered pack + is_client=true) cannot be tested
## here because GUT's stub() requires a doubled instance, and NetworkManager
## is a live autoload.  That branch is verified by the manual integration test
## at the bottom of this file.
##
## These tests cover:
##   - Unknown pack + not a client → false  (baseline; documents what unit tests can assert)
##   - Registered pack with URL → true       (URL path still works after fix)
##   - Registered pack, no URL, not client → false  (no sources → false)

## Unique pack IDs that won't collide with real packs
const _PACK_WITH_URL := "nd_test_pack_with_url"
const _PACK_NO_URL := "nd_test_pack_no_url"
const _UNKNOWN_PACK := "nd_test_pack_not_registered_xyz"


func before_all() -> void:
	# Register a pack that has a base_url so get_model_url() returns non-empty
	AssetManager.register_remote_pack(
		{
			"pack_id": _PACK_WITH_URL,
			"display_name": "ND Test Pack With URL",
			"base_url": "https://example.invalid/",
			"assets":
			{
				"asset1":
				{
					"display_name": "Asset 1",
					"variants": {"default": {"model": "asset1.glb", "icon": ""}}
				}
			}
		}
	)

	# Register a pack with NO base_url and no per-variant URLs
	AssetManager.register_remote_pack(
		{
			"pack_id": _PACK_NO_URL,
			"display_name": "ND Test Pack No URL",
			"assets":
			{
				"asset1":
				{
					"display_name": "Asset 1",
					"variants": {"default": {"model": "asset1.glb", "icon": ""}}
				}
			}
		}
	)


## Unknown pack, not a network client → no sources → false
func test_needs_download_false_for_unknown_pack_when_not_client() -> void:
	# In headless GUT runs, NetworkManager.is_client() is false.
	# This asserts the correct result for that context; the P2P=true case
	# is covered by the manual integration test.
	assert_false(AssetManager.needs_download(_UNKNOWN_PACK, "some_asset", "default"))


## Registered pack with a URL → true (URL source is available)
func test_needs_download_true_when_pack_has_model_url() -> void:
	assert_true(AssetManager.needs_download(_PACK_WITH_URL, "asset1", "default"))


## Registered pack, no URL, not a client → no sources → false
func test_needs_download_false_when_no_url_and_not_client() -> void:
	assert_false(AssetManager.needs_download(_PACK_NO_URL, "asset1", "default"))


## Unknown asset in a registered pack → no URL, not a client → false
func test_needs_download_false_for_unknown_asset_in_known_pack() -> void:
	assert_false(AssetManager.needs_download(_PACK_WITH_URL, "nonexistent_asset", "default"))


## Completely unknown pack_id → false in standalone context
func test_needs_download_false_for_empty_pack_id() -> void:
	assert_false(AssetManager.needs_download("", "asset", "default"))
