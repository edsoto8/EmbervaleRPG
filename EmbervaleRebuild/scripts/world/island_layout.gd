class_name IslandLayout
extends RefCounted
## Fixed layout of Driftwood Isle (metres; +X east, -Z north, Y up). Quests, tests and the minimap
## depend on these positions, so cosmetic changes must not move them.

const ISLAND_SEED := 4242
const NOISE_SEED := 1987
const COVER_SEED := 4343
const SKILL_SEED := 4444

const SEA_LEVEL := 0.0
const POND_LEVEL := 0.18
const DOCK_DECK := 0.42

const PLAZA := Vector2(0, 18)
const PLAZA_RADIUS := 6.5
const COTTAGES := [Vector2(-11, 12), Vector2(-12, 24), Vector2(11, 25), Vector2(-7, 33), Vector2(12, 14.5)]
const COTTAGE_SIZE := Vector2(5.0, 4.4)

const COURTYARD_MIN := Vector2(17, -2.5)
const COURTYARD_MAX := Vector2(33, 10.5)
const COURTYARD_ENTRANCE := Vector2(18, 4)
const COURTYARD_GAP := 3.2 # width of the west fence opening, centred on the entrance Z
const INSTRUCTOR := Vector2(21.5, 4)
const DUMMIES := [Vector2(27.6, 4), Vector2(27.6, 0.4), Vector2(27.6, 7.6)]
const WEAPON_RACK := Vector2(31.2, 4)

const FOREST := Vector2(-24, -12)
const FOREST_RADIUS := 6.5
## The five normal choppable trees (Milestone 3) stand in the open clearing.
const CHOPPABLE_TREES := [Vector2(-26.4, -14.6), Vector2(-21.2, -15.0), Vector2(-27.4, -9.4),
		Vector2(-23.6, -8.3), Vector2(-20.1, -11.0)]

const POND := Vector2(20, -22)
const POND_RADIUS := 6.5
const FISHER := Vector2(19.4, -14.3)

const DOCK_X := 4.0
const DOCK_HALF_WIDTH := 1.5
const DOCK_START_Z := 40.0
const DOCK_END_Z := 57.0
const SPAWN := Vector2(4.0, 51.0)
const MOVE_MARKER := Vector2(4.0, 42.5)
const BOAT := Vector2(7.6, 52.5)

const GATE := Vector2(0, -41.5)
const EXIT_GATE_POINT := Vector2(0, -37.5)
const GATE_WALL_HALF := 10.0

const MARKET_STALL := Vector2(-4.6, 21.8)   # Marla's stall, facing the plaza centre
const MERCHANT := Vector2(-5.3, 22.7)       # Marla stands behind her counter
const SECOND_STALL := Vector2(-5.6, 14.4)
const WELL := Vector2(-1.6, 16.2)
const WANDERER_HOME := Vector2(2.6, 14.6)
const SIGNPOST := Vector2(3.4, 26.4)
const GARDEN := Vector2(-15.5, 31.5)
const GARDEN_SIZE := Vector2(5.0, 4.0)

## Path polylines (XZ), village to every region.
const PATHS := [
	[Vector2(4, 41), Vector2(3.2, 34), Vector2(1.2, 24.5)],                       # dock -> village
	[Vector2(5.5, 15.5), Vector2(8.5, 9.5), Vector2(13, 5.2), Vector2(18.5, 4)],  # village -> courtyard
	[Vector2(-6, 17.5), Vector2(-16, 17), Vector2(-22, 8), Vector2(-23.6, -5)],   # village -> forest
	[Vector2(1.5, 11.6), Vector2(6, -2), Vector2(13, -10.5), Vector2(19, -14)],   # village -> pond
	[Vector2(-0.8, 11.6), Vector2(-2.2, 0), Vector2(-2.2, -20), Vector2(0, -37)], # village -> gate
]
const PATH_HALF_WIDTH := 1.25


## Irregular coastline radius for an angle (atan2(z, x)).
static func coast_radius(angle: float) -> float:
	var r := 46.0 + 2.0 * sin(3.0 * angle + 0.7) + 1.5 * sin(5.0 * angle + 2.1) + 1.0 * sin(7.0 * angle + 0.3)
	# Keep the dock (south, +Z) and gate (north, -Z) coasts at a fixed distance.
	for target in [PI * 0.5, -PI * 0.5]:
		var d := wrapf(angle - target, -PI, PI)
		var w := exp(-pow(d / 0.32, 2.0))
		r = lerpf(r, 46.0, w)
	return r


static func distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static var _path_bounds: Array[Rect2] = []


## Distance to the nearest path. Each path's bounding box is tested first, which skips most segment
## tests during generation (this runs tens of thousands of times).
static func distance_to_paths(p: Vector2) -> float:
	if _path_bounds.is_empty():
		for path in PATHS:
			var r := Rect2(path[0], Vector2.ZERO)
			for q in path:
				r = r.expand(q)
			_path_bounds.append(r)
	var best := INF
	for k in PATHS.size():
		var r := _path_bounds[k]
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		if dx * dx + dy * dy >= best * best:
			continue
		var path: Array = PATHS[k]
		for i in path.size() - 1:
			best = minf(best, distance_to_segment(p, path[i], path[i + 1]))
	return best


static func in_courtyard(p: Vector2, margin: float = 0.0) -> bool:
	return p.x >= COURTYARD_MIN.x - margin and p.x <= COURTYARD_MAX.x + margin \
			and p.y >= COURTYARD_MIN.y - margin and p.y <= COURTYARD_MAX.y + margin


static func in_plaza(p: Vector2, margin: float = 0.0) -> bool:
	return p.distance_to(PLAZA) <= PLAZA_RADIUS + margin


static func on_dock(p: Vector2, margin: float = 0.0) -> bool:
	return absf(p.x - DOCK_X) <= DOCK_HALF_WIDTH + margin and p.y >= DOCK_START_Z - margin \
			and p.y <= DOCK_END_Z + margin


## Yaw (radians) for a model facing local -Z to look from `from` towards `to`.
static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)
