class_name LibraryVersions
extends RefCounted

## Semantic versions and the version ranges of library `dependencies` (design doc 2.3 and 2.9):
## `^1.0` (caret), `~1.2` (tilde), `1.4.0` (exact; a partial `1.4` matches 1.4.x), comparators
## `>=1.0`, `>1`, `<=2`, `<2.0.0`, `=1.2.3`, several separated by spaces (all must hold), and
## `*` or "" for any version. Pure statics. Prerelease tags (`1.0.0-dev`) are read but IGNORED
## by every comparison, so plantgen's `1.0.0-dev` core satisfies `^1.0` (strict semver would put
## it below 1.0.0, which only gets in the way of a library under development).

const MAX_RANGE_LENGTH := 64


## {major, minor, patch, parts (1 to 3, how many were written), pre} of `text`, or {} when it is
## not a version. A partial version ("1.0") is accepted for ranges; is_full tells the difference.
static func parse(text: String) -> Dictionary:
	var core := text.strip_edges()
	var pre := ""
	if "-" in core:
		pre = core.substr(core.find("-") + 1)
		core = core.substr(0, core.find("-"))
	if core.begins_with("v"):
		core = core.substr(1)
	var pieces := core.split(".")
	if pieces.size() < 1 or pieces.size() > 3:
		return {}
	var numbers: Array[int] = []
	for piece in pieces:
		if piece == "" or not piece.is_valid_int() or piece.length() > 9 or piece.begins_with("-"):
			return {}
		numbers.append(int(piece))
	var parts := numbers.size()
	while numbers.size() < 3:
		numbers.append(0)
	return {
		"major": numbers[0], "minor": numbers[1], "patch": numbers[2], "parts": parts, "pre": pre
	}


static func is_full(text: String) -> bool:
	var parsed := parse(text)
	return not parsed.is_empty() and int(parsed["parts"]) == 3


## -1, 0 or 1 comparing `a` with `b` (prerelease ignored); 0 when either does not parse.
static func compare(a: String, b: String) -> int:
	var left := parse(a)
	var right := parse(b)
	if left.is_empty() or right.is_empty():
		return 0
	return _cmp(_tuple(left), _tuple(right))


## The text of `range_text` when it is a usable range, else a one-line problem ("" when fine).
static func range_problem(range_text: String) -> String:
	if range_text.length() > MAX_RANGE_LENGTH:
		return "range is over %d characters" % MAX_RANGE_LENGTH
	var bounds := _bounds(range_text)
	return "" if bounds.has("any") or bounds.has("clauses") else String(bounds.get("error", ""))


## Whether `version` satisfies `range_text`. A version or range that does not parse satisfies
## nothing, except that "" and "*" accept every parseable version.
static func satisfies(version: String, range_text: String) -> bool:
	var parsed := parse(version)
	if parsed.is_empty():
		return false
	var bounds := _bounds(range_text)
	if bounds.has("any"):
		return true
	if not bounds.has("clauses"):
		return false
	var at := _tuple(parsed)
	for clause: Dictionary in bounds["clauses"]:
		var order := _cmp(at, clause["version"])
		match String(clause["op"]):
			">=":
				if order < 0:
					return false
			">":
				if order <= 0:
					return false
			"<=":
				if order > 0:
					return false
			"<":
				if order >= 0:
					return false
			"=":
				if order != 0:
					return false
	return true


## The range as a human line for messages: "^1.0" is "1.0 or newer, below 2.0.0".
static func describe(range_text: String) -> String:
	var text := range_text.strip_edges()
	return "any version" if text == "" or text == "*" else text


# ---- internals ----


static func _tuple(parsed: Dictionary) -> Array:
	return [int(parsed["major"]), int(parsed["minor"]), int(parsed["patch"])]


static func _cmp(a: Array, b: Array) -> int:
	for i in 3:
		if a[i] != b[i]:
			return -1 if a[i] < b[i] else 1
	return 0


## {"any": true}, {"clauses": [{op, version: [major, minor, patch]}]} or {"error": text}.
static func _bounds(range_text: String) -> Dictionary:
	var text := range_text.strip_edges()
	if text == "" or text == "*":
		return {"any": true}
	var clauses: Array = []
	for token in text.split(" ", false):
		var made := _clauses_of(token)
		if made.has("error"):
			return made
		clauses.append_array(made["clauses"])
	return {"clauses": clauses}


static func _clauses_of(token: String) -> Dictionary:
	var op := ""
	var rest := token
	for candidate in [">=", "<=", ">", "<", "=", "^", "~"]:
		if token.begins_with(candidate):
			op = candidate
			rest = token.substr(candidate.length())
			break
	var parsed := parse(rest)
	if parsed.is_empty():
		return {"error": "'%s' is not a version range" % token}
	var low := _tuple(parsed)
	var parts := int(parsed["parts"])
	match op:
		"^":
			return {"clauses": [_clause(">=", low), _clause("<", _caret_upper(low, parts))]}
		"~":
			var upper: Array = [low[0], low[1] + 1, 0] if parts >= 2 else [low[0] + 1, 0, 0]
			return {"clauses": [_clause(">=", low), _clause("<", upper)]}
		">=", ">", "<=", "<":
			return {"clauses": [_clause(op, low)]}
		_:
			# Exact: a partial version matches every version that starts with it.
			if parts == 3:
				return {"clauses": [_clause("=", low)]}
			var upper: Array = [low[0], low[1] + 1, 0] if parts == 2 else [low[0] + 1, 0, 0]
			return {"clauses": [_clause(">=", low), _clause("<", upper)]}


static func _clause(op: String, version: Array) -> Dictionary:
	return {"op": op, "version": version}


## npm's caret: nothing left of the first non-zero part may change.
static func _caret_upper(low: Array, parts: int) -> Array:
	if low[0] > 0 or parts == 1:
		return [low[0] + 1, 0, 0]
	if low[1] > 0 or parts == 2:
		return [0, low[1] + 1, 0]
	return [0, 0, low[2] + 1]
