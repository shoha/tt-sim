extends GutTest
## The golden digests of the derive (docs/systems/terraform.md): the corpus on a square 200 ft map
## and on a 200 x 240 ft one (whose two axes have different steps) must derive to exactly the
## digests in tests/fixtures/terra_corpus_digests.json. CI runs this on Windows, Linux and macOS
## (.github/native/parity.sh), so it proves the derive gives the same bits on every platform: a
## platform that disagrees is a bug in native/src/terra_math.h, never in the fixture.
##
## A change that moves the derive on purpose (a stage, a constant, the ground rules) regenerates
## the fixture: the failure prints the new cases as JSON, which replace the file's "cases".

const FIXTURE := "res://tests/fixtures/terra_corpus_digests.json"
## The cases: name -> map size in cells (x, z).
const CASES := {"square_40": Vector2i(40, 40), "wide_40x48": Vector2i(40, 48)}


func _digests(cells: Vector2i) -> Dictionary:
	var n := TerraCorpus.build(cells).make_derive()
	n.call("derive_full")
	var d: Dictionary = n.call("digests")
	var out := {}
	for k in d:
		out[k] = str(d[k])
	return out


func test_version() -> void:
	if not ClassDB.class_exists(TerraCore.CLASS_NAME):
		pending(TerraCorpus.NO_LIBRARY)
		return
	var n: RefCounted = ClassDB.instantiate(TerraCore.CLASS_NAME)
	assert_eq(n.call("version"), TerraCore.NATIVE_VERSION, "rebuild native/ (AGENTS.md)")


func test_golden_digests() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var want: Dictionary = fixture.get("cases", {}) if fixture is Dictionary else {}
	var got := {}
	var matched := 0
	var bad: Array = []
	for name: String in CASES:
		got[name] = _digests(CASES[name])
		var w: Dictionary = want.get(name, {})
		for k: String in got[name]:
			if w.get(k) == got[name][k]:
				matched += 1
			else:
				bad.append("%s.%s" % [name, k])
		assert_eq(w.size(), got[name].size(), "%s: the fixture has every digest" % name)
	assert_eq(fixture.get("version") if fixture is Dictionary else null, TerraCore.NATIVE_VERSION)
	assert_eq(bad, [], "digests that differ from the fixture")
	if not bad.is_empty():
		gut.p("terra golden: new cases %s" % JSON.stringify(got, "", true))
	if bad.is_empty():
		var where := "%s %s" % [OS.get_name(), Engine.get_architecture_name()]
		gut.p("terra golden: %d digests matched on %s" % [matched, where])
