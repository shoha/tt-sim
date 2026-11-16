class_name TokenRosterModel
extends RefCounted

## What the token roster lists, as pure functions over the board's tokens: which a peer may see,
## in what order, and how each one's health reads. No scene tree, so the rules are unit-tested.
##
## A player sees only the tokens the GM has not hidden (UI_TASTE G14: a roster must never leak
## what the board hides) and finds the ones they control first; the GM sees every token, the
## hidden ones marked. Rows are sorted by name with numbers in natural order, so "Goblin 2" comes
## before "Goblin 10".

enum Health { HEALTHY, HURT, DOWN }

## HP at or under this share of the maximum reads as hurt (the bar turns to the danger role and
## the words say so; colour is never the only cue, UI_TASTE C7).
const HURT_SHARE := 0.4


## The rows for `tokens` (BoardToken nodes) as one peer sees them. `is_gm` lists every token;
## otherwise a hidden one is left out. `controls` is called with a token and answers whether
## this peer controls it (a Callable(BoardToken) -> bool); controlled tokens sort first. Each
## row is {"token", "id", "name", "hp", "max_hp", "hidden", "yours", "health"}.
static func rows(tokens: Array, is_gm: bool, controls: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in tokens:
		var token := node as BoardToken
		if token == null or not is_instance_valid(token) or token.is_queued_for_deletion():
			continue
		var hidden := not token.is_visible_to_players
		if hidden and not is_gm:
			continue
		(
			out
			. append(
				{
					"token": token,
					"id": token.network_id,
					"name": token.token_name,
					"hp": token.current_health,
					"max_hp": token.max_health,
					"hidden": hidden,
					"yours": controls.is_valid() and bool(controls.call(token)),
					"health": health_of(token.current_health, token.max_health),
				}
			)
		)
	out.sort_custom(_before)
	return out


## Whether row `a` sorts before row `b`: yours first, then name (natural, case-insensitive),
## then network id so equal names keep a stable order.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["yours"] != b["yours"]:
		return a["yours"]
	var by_name := String(a["name"]).naturalnocasecmp_to(String(b["name"]))
	if by_name != 0:
		return by_name < 0
	return String(a["id"]) < String(b["id"])


## How `hp` of `max_hp` reads: DOWN at 0 or less, HURT at HURT_SHARE of the maximum or under,
## else HEALTHY. A token with no maximum is healthy. Pure.
static func health_of(hp: int, max_hp: int) -> Health:
	if max_hp <= 0:
		return Health.HEALTHY
	if hp <= 0:
		return Health.DOWN
	if float(hp) / float(max_hp) <= HURT_SHARE:
		return Health.HURT
	return Health.HEALTHY


## The words under a token's name: "HP 40/100", "Down" at zero, with ", hidden" after it for
## a hidden token (GM view; the row also wears an icon). Whole translatable sentences, no
## concatenation (W6).
static func status_text(row: Dictionary) -> String:
	var health: Health = row["health"]
	var hp_text := (
		_t("Down")
		if health == Health.DOWN
		else _t("HP %d/%d") % [int(row["hp"]), int(row["max_hp"])]
	)
	if row["hidden"]:
		return _t("%s, hidden") % hp_text
	return hp_text


## The count line over the list: "8 tokens", "1 token", "No tokens on the table".
static func count_text(count: int) -> String:
	if count == 0:
		return _t("No tokens on the table")
	if count == 1:
		return _t("1 token")
	return _t("%d tokens") % count


static func _t(message: String) -> String:
	return TranslationServer.translate(message)
