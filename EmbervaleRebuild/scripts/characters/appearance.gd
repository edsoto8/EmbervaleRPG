class_name Appearance
extends RefCounted
## Character appearance palettes, defaults, validation and randomisation (base spec, M2).

const BODY_TYPES := ["Slim", "Average", "Broad"]
const HAIR_STYLES := ["Bald", "Short", "Long", "Ponytail", "Mohawk"]
const SKIN := ["f3d2b3", "e0b48f", "c68e63", "9c6a43", "6e4a2f", "4a3121"]
const HAIR := ["2b2018", "5a3a1e", "a5662f", "d8b45a", "b8452c", "8c8c8c", "f0ead6"]
const CLOTH := ["7a2e2e", "2f4f7a", "3e6b35", "8a6a2f", "5b3d6e", "c9c1a8", "3a3a3a", "b5622a"]

const NAME_PATTERN := "^[A-Za-z0-9]+( [A-Za-z0-9]+)*$"
const NAME_MAX := 12
const DEFAULT_NAME := "Adventurer"
const SUGGESTED_NAMES := ["Rowan", "Elara", "Bram", "Wren", "Tamsin", "Corin", "Isolde", "Fenn",
		"Maren", "Oswin", "Lyra", "Gareth", "Nessa", "Tobias", "Ailsa", "Darian"]

static var _regex: RegEx


static func defaults() -> Dictionary:
	return {
		"body_type": 1,
		"skin_tone": "e0b48f",
		"hair_style": 1,
		"hair_color": "5a3a1e",
		"shirt_color": "2f4f7a",
		"pants_color": "8a6a2f",
	}


## Returns a complete, valid appearance; each invalid or missing field independently takes its default.
static func sanitize(data: Variant) -> Dictionary:
	var out := defaults()
	if not data is Dictionary:
		return out
	var d: Dictionary = data
	if _is_int_in(d.get("body_type"), 0, BODY_TYPES.size() - 1):
		out.body_type = int(d.body_type)
	if _is_int_in(d.get("hair_style"), 0, HAIR_STYLES.size() - 1):
		out.hair_style = int(d.hair_style)
	for pair in [["skin_tone", SKIN], ["hair_color", HAIR], ["shirt_color", CLOTH], ["pants_color", CLOTH]]:
		var v: Variant = d.get(pair[0])
		if v is String and (v as String).to_lower() in pair[1]:
			out[pair[0]] = (v as String).to_lower()
	return out


static func _is_int_in(v: Variant, lo: int, hi: int) -> bool:
	if v is int:
		return v >= lo and v <= hi
	if v is float:
		return is_finite(v) and v == floorf(v) and v >= lo and v <= hi
	return false


static func randomized(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"body_type": rng.randi_range(0, BODY_TYPES.size() - 1),
		"skin_tone": SKIN[rng.randi_range(0, SKIN.size() - 1)],
		"hair_style": rng.randi_range(0, HAIR_STYLES.size() - 1),
		"hair_color": HAIR[rng.randi_range(0, HAIR.size() - 1)],
		"shirt_color": CLOTH[rng.randi_range(0, CLOTH.size() - 1)],
		"pants_color": CLOTH[rng.randi_range(0, CLOTH.size() - 1)],
	}


## Empty string when the (already trimmed) name is valid, otherwise the reason it is not.
static func name_error(name: String) -> String:
	if _regex == null:
		_regex = RegEx.create_from_string(NAME_PATTERN)
	if name.is_empty():
		return "Enter a name."
	if name.length() > NAME_MAX:
		return "Names can be at most %d characters." % NAME_MAX
	if name.begins_with(" ") or name.ends_with(" "):
		return "Names can't start or end with a space."
	if name.contains("  "):
		return "Use single spaces between words."
	if _regex.search(name) == null:
		return "Use only letters, numbers and single spaces."
	return ""


static func clean_name(raw: String) -> String:
	return raw.strip_edges()


static func is_valid_name(name: String) -> bool:
	return name_error(name) == ""
