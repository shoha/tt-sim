class_name VersionGate

## Same-version rule for multiplayer: a player can only join a game hosted on exactly
## the same game version (application/config/version, see UpdateVersion.get_current()).
## Host and clients share level data, RPC signatures and asset formats with no
## compatibility layer, so any difference -- even a dev-build suffix -- is a mismatch.
##
## The rule is checked twice. The joining client reads the host's version from Steam
## lobby data before connecting, which lets it fail fast with a clear message. The host
## re-checks the version each client reports in its player info, because lobby data is
## advisory and only the host is authoritative about who gets in. Both decisions live
## here as pure static functions so they can be unit-tested without Steam or a peer.
##
## The network protocol. Development builds share one version string (every build of a
## cycle is 0.4.2 until the release bump), so the version alone let two builds with
## different wire formats into one room, where their RPCs fail or misread each other. PROTOCOL
## is compared beside the version, at both checks: bump it in any change that alters what
## goes over the wire (an RPC added, removed, renamed or with other arguments; a message
## layout such as TokenStateWire or TokenTransformPack; the meaning of a field). A build from
## before the number published none and reads as 0, which never matches.

## The wire format this build speaks (see the header). 1 was everything before it (implicit,
## never published); 2: perfaudit netspawn's token add, TokenStateWire chunks and packed
## reconcile, and netverify's packed single drag transform.
const PROTOCOL := 2

## Steam lobby data key the host publishes its version under.
const LOBBY_DATA_KEY := "tt_version"

## Steam lobby data key the host publishes PROTOCOL under (a decimal string).
const LOBBY_PROTOCOL_KEY := "tt_protocol"

## Player-info Dictionary key a client reports its version under.
const PLAYER_INFO_KEY := "version"

## Player-info Dictionary key a client reports its PROTOCOL under (an int).
const PLAYER_INFO_PROTOCOL_KEY := "protocol"


## Player-facing reason a client on local_version and local_protocol cannot join a host on
## host_version and host_protocol, or "" when both match exactly. An empty host_version means
## the host predates this gate (it published no version), which is always a mismatch and is
## worded as an older version since its real number is unknown. With the versions equal, a
## different protocol is a different build of that version (protocol_message()).
static func mismatch_message(
	host_version: String,
	local_version: String,
	host_protocol: int = PROTOCOL,
	local_protocol: int = PROTOCOL,
) -> String:
	if host_version == local_version:
		return protocol_message(local_version, host_protocol, local_protocol)
	if host_version.is_empty():
		return (
			(
				"The host is running an older version of TTSim than yours (%s). "
				+ "Both of you need the same version to play together."
			)
			% local_version
		)
	var advice := "Both of you need the same version to play together."
	if UpdateVersion.is_newer(host_version, local_version):
		advice = "Update TTSim to join this room."
	elif UpdateVersion.is_newer(local_version, host_version):
		advice = "The host needs to update TTSim before you can join."
	return (
		"The host is running TTSim %s, but you have %s. %s" % [host_version, local_version, advice]
	)


## Player-facing reason two builds of one version cannot play together, or "" when their
## protocols match. A host protocol of 0 or less published none (a build from before it).
static func protocol_message(version: String, host_protocol: int, local_protocol: int) -> String:
	if host_protocol == local_protocol:
		return ""
	var advice := "Both of you need the same build to play together."
	if host_protocol <= 0:
		return (
			"The host is running an older build of TTSim %s, from before network protocol %d. %s"
			% [version, local_protocol, advice]
		)
	return (
		"The host is running a different build of TTSim %s (network protocol %d, yours is %d). %s"
		% [version, host_protocol, local_protocol, advice]
	)


## The protocol a host published in its lobby data (a decimal string), or 0 when it published
## none or something that is not a number.
static func lobby_protocol(value: String) -> int:
	return int(value) if value.is_valid_int() else 0


## Host-side decision: whether a client's reported player info carries exactly the
## host's version and protocol. A missing or non-String version, or a missing or non-int
## protocol (a client from before either, or a malformed payload), is rejected rather than
## trusted.
static func is_player_info_accepted(
	info: Dictionary, host_version: String, host_protocol: int = PROTOCOL
) -> bool:
	var reported: Variant = info.get(PLAYER_INFO_KEY, "")
	return reported is String and reported == host_version and reported_protocol(info) == host_protocol


## The protocol a client reported in its player info, or 0 when it is missing or not an int.
static func reported_protocol(info: Dictionary) -> int:
	var reported: Variant = info.get(PLAYER_INFO_PROTOCOL_KEY, 0)
	return int(reported) if reported is int else 0


## What a client shows when the host rejected it (NetworkManager._rpc_version_rejected): the
## version message, or with equal versions the protocol one. The rejection carries only the
## host's version, so the host's protocol is unknown here and worded as different.
static func rejection_message(host_version: String, local_version: String) -> String:
	var message := mismatch_message(host_version, local_version)
	if not message.is_empty():
		return message
	return (
		(
			"The host is running a different build of TTSim %s (its network protocol is not %d). "
			+ "Both of you need the same build to play together."
		)
		% [local_version, PROTOCOL]
	)


## The version a client reported in its player info, for the host's rejection log.
## Returns "" when it is missing or not a String.
static func reported_version(info: Dictionary) -> String:
	var reported: Variant = info.get(PLAYER_INFO_KEY, "")
	return reported if reported is String else ""
