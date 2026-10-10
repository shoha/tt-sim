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

## Steam lobby data key the host publishes its version under.
const LOBBY_DATA_KEY := "tt_version"

## Player-info Dictionary key a client reports its version under.
const PLAYER_INFO_KEY := "version"


## Player-facing reason a client on local_version cannot join a host on host_version,
## or "" when the versions match exactly. An empty host_version means the host predates
## this gate (it published no version), which is always a mismatch and is worded as an
## older version since its real number is unknown.
static func mismatch_message(host_version: String, local_version: String) -> String:
	if host_version == local_version:
		return ""
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


## Host-side decision: whether a client's reported player info carries exactly the
## host's version. A missing or non-String version (a client from before this gate, or
## a malformed payload) is rejected rather than trusted.
static func is_player_info_accepted(info: Dictionary, host_version: String) -> bool:
	var reported: Variant = info.get(PLAYER_INFO_KEY, "")
	return reported is String and reported == host_version


## The version a client reported in its player info, for the host's rejection log.
## Returns "" when it is missing or not a String.
static func reported_version(info: Dictionary) -> String:
	var reported: Variant = info.get(PLAYER_INFO_KEY, "")
	return reported if reported is String else ""
