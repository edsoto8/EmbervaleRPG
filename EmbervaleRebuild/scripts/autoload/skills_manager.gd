extends Node
## Experience, levels and hitpoints. Numbers and formulas live in SkillData. Every skill check rolls
## through chance(), so tests make luck deterministic with `roll_override`. Levels are never stored;
## they are derived from (fractional) XP.

signal xp_gained(skill: String, amount: float)
signal level_up(skill: String, level: int)
signal hitpoints_changed(current: int, maximum: int)

var xp := {}
var hitpoints := SkillData.MAX_HITPOINTS
## Test hook: when set to a float in [0, 1), chance(p) returns override < p instead of rolling.
var roll_override: Variant = null
var _rng := RandomNumberGenerator.new()
var _regen_time := 0.0


func _init() -> void:
	_rng.randomize()
	reset()


func reset() -> void:
	xp = {}
	for s in SkillData.SKILLS:
		xp[s] = 0.0
	hitpoints = SkillData.MAX_HITPOINTS
	_regen_time = 0.0
	hitpoints_changed.emit(hitpoints, SkillData.MAX_HITPOINTS)


func to_dict() -> Dictionary:
	return {"xp": xp.duplicate(), "hitpoints": hitpoints}


## Loads validated data (no level-up events are emitted).
func from_dict(data: Dictionary) -> void:
	reset()
	var sx: Dictionary = data.get("xp", {})
	for s in SkillData.SKILLS:
		xp[s] = minf(float(sx.get(s, 0.0)), SkillData.xp_cap())
	hitpoints = clampi(int(data.get("hitpoints", SkillData.MAX_HITPOINTS)), 1, SkillData.MAX_HITPOINTS)
	_regen_time = 0.0
	hitpoints_changed.emit(hitpoints, SkillData.MAX_HITPOINTS)


func level(skill: String) -> int:
	return SkillData.level_for_xp(xp.get(skill, 0.0))


func highest_level() -> int:
	var best := 1
	for s in SkillData.SKILLS:
		best = maxi(best, level(s))
	return best


## Adds XP (capped). A gain that crosses several levels emits one level_up with the final level.
func add_xp(skill: String, amount: float) -> void:
	if not xp.has(skill) or amount <= 0.0:
		return
	var before := level(skill)
	xp[skill] = minf(xp[skill] + amount, SkillData.xp_cap())
	xp_gained.emit(skill, amount)
	var after := level(skill)
	if after > before:
		GameManager.post_message("Congratulations, your %s level is now %d." % [SkillData.SKILL_NAMES[skill], after])
		level_up.emit(skill, after)


## True with probability p. Every skill roll goes through here.
func chance(p: float) -> bool:
	if roll_override != null:
		return float(roll_override) < p
	return _rng.randf() < p


func heal(amount: int) -> int:
	var before := hitpoints
	hitpoints = mini(hitpoints + amount, SkillData.MAX_HITPOINTS)
	if hitpoints != before:
		hitpoints_changed.emit(hitpoints, SkillData.MAX_HITPOINTS)
	if hitpoints >= SkillData.MAX_HITPOINTS:
		_regen_time = 0.0
	return hitpoints - before


## Hitpoints never drop below 1 (there is no combat or death).
func damage(amount: int) -> void:
	var before := hitpoints
	hitpoints = maxi(hitpoints - amount, 1)
	if hitpoints != before:
		hitpoints_changed.emit(hitpoints, SkillData.MAX_HITPOINTS)


## One hitpoint per uninterrupted 30 s of PLAYING while hurt; pausing freezes the timer (this node is
## pausable), full health resets it. No offline regeneration.
func _physics_process(delta: float) -> void:
	if hitpoints >= SkillData.MAX_HITPOINTS:
		_regen_time = 0.0
		return
	if not GameManager.adventure_loaded and GameManager.world() == null:
		return
	if GameManager.state != GameManager.State.PLAYING:
		return
	_regen_time += delta
	if _regen_time >= SkillData.HP_REGEN_SECONDS:
		_regen_time -= SkillData.HP_REGEN_SECONDS
		heal(1)


func regen_progress() -> float:
	return _regen_time
