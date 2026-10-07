class_name SkillData
extends RefCounted
## Skill numbers and formulas (SPEC_SKILLS.md S10). Every chance roll goes through
## SkillsManager.chance() so tests can make luck deterministic.

const SKILLS := ["attack", "woodcutting", "fishing", "firemaking", "cooking"]
const SKILL_NAMES := {"attack": "Attack", "woodcutting": "Woodcutting", "fishing": "Fishing",
		"firemaking": "Firemaking", "cooking": "Cooking"}
const MAX_LEVEL := 99
const MAX_HITPOINTS := 10
const HP_REGEN_SECONDS := 30.0

const TREES := {
	"normal": {"level": 1, "xp": 25.0, "seconds": 2.0, "deplete": 1.0, "regrow": 20.0, "log": "logs"},
	"oak": {"level": 5, "xp": 40.0, "seconds": 2.6, "deplete": 0.30, "regrow": 25.0, "log": "oak_logs"},
	"willow": {"level": 10, "xp": 65.0, "seconds": 3.0, "deplete": 0.25, "regrow": 30.0, "log": "willow_logs"},
}
const STEEL_AXE_MULTIPLIER := 0.70

const FISH_CAST_SECONDS := 2.4
const FISH := {
	"raw_shrimp": {"level": 1, "xp": 10.0},
	"raw_trout": {"level": 5, "xp": 50.0},
}
const OAK_ROD_BONUS := 0.15

const LIGHT_SECONDS := 1.8
const FIRE_LOGS := {
	"logs": {"level": 1, "xp": 40.0},
	"oak_logs": {"level": 5, "xp": 60.0},
	"willow_logs": {"level": 10, "xp": 90.0},
}
const FIRE_BURN_SECONDS := 60.0
const FIRE_FADE_SECONDS := 3.0

const COOK_SECONDS := 1.8
const COOKING := {
	"raw_trout": {"level": 5, "xp": 70.0, "stop_burn": 20, "cooked": "trout", "burnt": "burnt_trout"},
	"raw_shrimp": {"level": 1, "xp": 30.0, "stop_burn": 16, "cooked": "shrimp", "burnt": "burnt_shrimp"},
}
const SINGE_CHANCE := 0.35

const EAT_SECONDS := 1.0

const ATTACK_SECONDS := 1.2
const ATTACK_XP := 8.0
const DUMMY_MAX_LEVEL := 10

static var _thresholds: PackedFloat64Array


## XP needed for a level: floor(sum(floor(i + 300 * 2^(i/7)), i = 1..n-1) / 4).
static func xp_for_level(level: int) -> float:
	_ensure_table()
	return _thresholds[clampi(level, 1, MAX_LEVEL)]


static func _ensure_table() -> void:
	if not _thresholds.is_empty():
		return
	_thresholds.resize(MAX_LEVEL + 1)
	_thresholds[0] = 0.0
	_thresholds[1] = 0.0
	var points := 0.0
	for n in range(2, MAX_LEVEL + 1):
		var i := n - 1
		points += floor(i + 300.0 * pow(2.0, i / 7.0))
		_thresholds[n] = floor(points / 4.0)


## Total XP is capped at 1.5 x the level-99 threshold (13,034,431), i.e. 19,551,646.5.
static func xp_cap() -> float:
	return xp_for_level(MAX_LEVEL) * 1.5


static func level_for_xp(xp: float) -> int:
	_ensure_table()
	var lvl := 1
	for n in range(2, MAX_LEVEL + 1):
		if xp >= _thresholds[n]:
			lvl = n
		else:
			break
	return lvl


## Fraction of the way from the current level to the next (1.0 at level 99).
static func level_progress(xp: float) -> float:
	var lvl := level_for_xp(xp)
	if lvl >= MAX_LEVEL:
		return 1.0
	var lo := xp_for_level(lvl)
	var hi := xp_for_level(lvl + 1)
	return clampf((xp - lo) / (hi - lo), 0.0, 1.0)


static func chop_seconds(tree: String, level: int, steel_axe: bool) -> float:
	var t: Dictionary = TREES[tree]
	var f := clampf(1.0 - 0.03 * (level - t.level), 0.55, 1.0)
	return t.seconds * f * (STEEL_AXE_MULTIPLIER if steel_axe else 1.0)


static func catch_chance(level: int, oak_rod: bool) -> float:
	var c := clampf(0.40 + 0.04 * (level - 1), 0.40, 0.85)
	if oak_rod:
		c += OAK_ROD_BONUS
	return minf(c, 1.0)


static func trout_chance(level: int) -> float:
	if level < 5:
		return 0.0
	return clampf(0.25 + 0.03 * (level - 5), 0.25, 0.60)


static func light_chance(level: int, required: int) -> float:
	return clampf(0.60 + 0.05 * (level - required), 0.60, 1.0)


static func burn_chance(raw_id: String, level: int) -> float:
	var c: Dictionary = COOKING[raw_id]
	if level >= c.stop_burn:
		return 0.0
	return 0.55 * float(c.stop_burn - level) / float(c.stop_burn - c.level)
