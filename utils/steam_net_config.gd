class_name SteamNetConfig

## Global Steam networking settings the game applies once Steam is initialised, before any
## connection exists.
##
## Steam sends each connection at about 256 KB/s by default, so a 13 MB (compressed) level
## map took 51 s to reach a client. Global config values do reach SteamMultiplayerPeer
## connections, and in practice SendRateMin is the rate Steam sends at: raising only
## SendRateMax to 4 MB/s changed nothing (51 s), raising both to 4 MB/s brought the map
## in 3.4 s (tests/net/steam_map_download.gd, two accounts on one machine, 2026-10-09).
## A rate above a player's real uplink makes Steam overrun it and lose packets, so the
## floor stays at a rate most home uplinks carry (8 Mbit/s) and the ceiling leaves room
## should Steam's estimate ever grow past it.

## Values of ESteamNetworkingConfigValue (steamnetworkingtypes.h), used when GodotSteam
## does not expose the constant by name.
const CONFIG_SEND_RATE_MIN := 10
const CONFIG_SEND_RATE_MAX := 11

## Bytes per second.
const SEND_RATE_MIN := 1024 * 1024
const SEND_RATE_MAX := 4 * 1024 * 1024


## Applies the game's send rates. Returns false when Steam refused either value.
static func apply_defaults() -> bool:
	return apply_send_rates(SEND_RATE_MIN, SEND_RATE_MAX)


## Sets Steam's global SendRateMin and SendRateMax in bytes per second; a value of zero or
## less leaves that setting at Steam's default. Returns false when Steam refused a value.
static func apply_send_rates(rate_min: int, rate_max: int) -> bool:
	var ok := true
	if rate_min > 0:
		ok = _set_int("NETWORKING_CONFIG_SEND_RATE_MIN", CONFIG_SEND_RATE_MIN, rate_min) and ok
	if rate_max > 0:
		ok = _set_int("NETWORKING_CONFIG_SEND_RATE_MAX", CONFIG_SEND_RATE_MAX, rate_max) and ok
	return ok


static func _set_int(constant_name: String, fallback: int, value: int) -> bool:
	var setting := fallback
	if ClassDB.class_has_integer_constant("Steam", constant_name):
		setting = ClassDB.class_get_integer_constant("Steam", constant_name)
	return bool(Steam.setGlobalConfigValueInt32(setting, value))
