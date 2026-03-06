class_name LobbyCode

## Base-36 encode/decode for Steam lobby IDs.
## Produces lowercase alphanumeric codes; decoding is case-insensitive.

const ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyz"
const BASE := 36


static func encode(lobby_id: int) -> String:
	if lobby_id == 0:
		return "0"
	var result := ""
	var value := lobby_id
	while value > 0:
		@warning_ignore("integer_division")
		var remainder := value % BASE
		result = ALPHABET[remainder] + result
		value = value / BASE
	return result


static func decode(code: String) -> int:
	if code.is_empty():
		return -1
	var lower := code.to_lower()
	var result := 0
	for i in range(lower.length()):
		var c := lower[i]
		var index := ALPHABET.find(c)
		if index == -1:
			return -1
		result = result * BASE + index
	return result
