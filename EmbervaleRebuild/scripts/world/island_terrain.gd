class_name IslandTerrain
extends RefCounted
## 128 x 128 m heightfield with 1 m tiles, centred on the origin. Generates heights, per-tile
## surface types and colours, the flat-shaded visible mesh and the walkable collision.

enum Tile { SEA, SAND, GRASS, FOREST, PATH, PLAZA, COURTYARD, POND_BED, MUD, DOCK_SAND }

const SIZE := 128
const HALF := 64
const VERTS := SIZE + 1
## Tiles further than this from the centre are not meshed (open sea is just water).
const MESH_RADIUS := 74.0

var noise := FastNoiseLite.new()
var heights := PackedFloat32Array()
var tiles := PackedByteArray()
## Fake ambient occlusion per tile (0 = none, 1 = fully dark), filled by TutorialIsland._occlude().
var occlusion := PackedFloat32Array()

var _flat_targets := {}


func _init() -> void:
	noise.seed = IslandLayout.NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2


func generate() -> void:
	# Flatten targets come from the unflattened ground at each zone's centre.
	_flat_targets = {
		"plaza": _raw_height(IslandLayout.PLAZA.x, IslandLayout.PLAZA.y),
		"courtyard": _raw_height(25, 4),
		"forest": _raw_height(IslandLayout.FOREST.x, IslandLayout.FOREST.y),
		"gate": _raw_height(IslandLayout.GATE.x, IslandLayout.GATE.y + 4.0),
		"cottages": IslandLayout.COTTAGES.map(func(c: Vector2) -> float: return _raw_height(c.x, c.y)),
	}
	heights.resize(VERTS * VERTS)
	for j in VERTS:
		for i in VERTS:
			heights[j * VERTS + i] = _shaped_height(float(i - HALF), float(j - HALF))
	tiles.resize(SIZE * SIZE)
	occlusion.resize(SIZE * SIZE)
	occlusion.fill(0.0)
	for j in SIZE:
		for i in SIZE:
			tiles[j * SIZE + i] = _classify(float(i - HALF) + 0.5, float(j - HALF) + 0.5)


func vertex_height(i: int, j: int) -> float:
	i = clampi(i, 0, SIZE)
	j = clampi(j, 0, SIZE)
	return heights[j * VERTS + i]


## Exact height of the triangulated surface (matches the mesh and the collision).
func height_at(x: float, z: float) -> float:
	var gx := clampf(x + HALF, 0.0, SIZE - 0.001)
	var gz := clampf(z + HALF, 0.0, SIZE - 0.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var a := vertex_height(i, j)
	var b := vertex_height(i + 1, j)
	var c := vertex_height(i + 1, j + 1)
	var d := vertex_height(i, j + 1)
	if fx >= fz:
		return a + (b - a) * fx + (c - b) * fz
	return a + (d - a) * fz + (c - d) * fx


func tile_at(x: float, z: float) -> int:
	var i := clampi(int(floor(x + HALF)), 0, SIZE - 1)
	var j := clampi(int(floor(z + HALF)), 0, SIZE - 1)
	return tiles[j * SIZE + i]


## Normal of the ground (approximate, from neighbouring heights).
func normal_at(x: float, z: float) -> Vector3:
	var hx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
	var hz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
	return Vector3(-hx, 1.0, -hz).normalized()


func is_land(x: float, z: float) -> bool:
	var t := tile_at(x, z)
	return t != Tile.SEA and t != Tile.POND_BED and height_at(x, z) > 0.12


# --- shape ---------------------------------------------------------------------------------------

func _coast_t(x: float, z: float) -> float:
	return IslandLayout.coast_radius(atan2(z, x)) - sqrt(x * x + z * z)


func _raw_height(x: float, z: float) -> float:
	var t := _coast_t(x, z)
	var h: float
	if t >= 0.0:
		h = minf(t * 0.11, 0.55)
	else:
		h = maxf(t * 0.13, -3.2)
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 1.15 * smoothstep(3.0, 14.0, t)
	return h + hills


func _shaped_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var t := _coast_t(x, z)
	if t < -6.0:
		return maxf(t * 0.13, -3.2)
	var h := _raw_height(x, z)
	var land := smoothstep(0.5, 4.0, t)
	# Paths are smoothed towards the coast profile so they read as worn, level ground.
	var dp := IslandLayout.distance_to_paths(p)
	var pw := (1.0 - smoothstep(IslandLayout.PATH_HALF_WIDTH, IslandLayout.PATH_HALF_WIDTH + 2.5, dp)) * land
	if pw > 0.0:
		var flat := minf(t * 0.11, 0.55) + (h - minf(t * 0.11, 0.55)) * 0.35
		h = lerpf(h, flat, pw)
	h = _flatten_disc(h, p, IslandLayout.PLAZA, IslandLayout.PLAZA_RADIUS + 1.0, 3.5, _flat_targets["plaza"])
	h = _flatten_disc(h, p, IslandLayout.FOREST, IslandLayout.FOREST_RADIUS + 1.5, 4.0, _flat_targets["forest"])
	var targets: Array = _flat_targets["cottages"]
	for k in IslandLayout.COTTAGES.size():
		h = _flatten_disc(h, p, IslandLayout.COTTAGES[k], 3.8, 2.5, targets[k])
	# Courtyard rectangle.
	var cd := _rect_distance(p, IslandLayout.COURTYARD_MIN - Vector2(1, 1), IslandLayout.COURTYARD_MAX + Vector2(1, 1))
	h = lerpf(h, _flat_targets["courtyard"], 1.0 - smoothstep(0.0, 3.5, cd))
	# Gate approach.
	h = _flatten_disc(h, p, IslandLayout.GATE + Vector2(0, 2), 6.0, 4.0, _flat_targets["gate"])
	# Pond: level surroundings, then a basin whose edge meets the 0.18 m surface at ~6.5 m.
	h = _flatten_disc(h, p, IslandLayout.POND, 8.0, 2.5, 0.55)
	var dpond := p.distance_to(IslandLayout.POND)
	h = lerpf(h, -0.7, smoothstep(7.2, 5.2, dpond))
	# Dock landing: level with the deck so the step onto it is tiny.
	var dock_d := _rect_distance(p, Vector2(IslandLayout.DOCK_X - 3.5, 33.0), Vector2(IslandLayout.DOCK_X + 3.5, 41.5))
	h = lerpf(h, 0.40, 1.0 - smoothstep(0.0, 3.0, dock_d))
	return h


func _flatten_disc(h: float, p: Vector2, centre: Vector2, radius: float, falloff: float, target: float) -> float:
	var d := p.distance_to(centre)
	return lerpf(h, target, 1.0 - smoothstep(radius, radius + falloff, d))


static func _rect_distance(p: Vector2, lo: Vector2, hi: Vector2) -> float:
	var dx := maxf(maxf(lo.x - p.x, 0.0), p.x - hi.x)
	var dz := maxf(maxf(lo.y - p.y, 0.0), p.y - hi.y)
	return sqrt(dx * dx + dz * dz)


func _classify(x: float, z: float) -> int:
	var p := Vector2(x, z)
	var h := height_at(x, z)
	if h < -0.6:
		return Tile.SEA
	var t := _coast_t(x, z)
	var dpond := p.distance_to(IslandLayout.POND)
	if dpond < 6.3 and h < IslandLayout.POND_LEVEL + 0.02:
		return Tile.POND_BED
	if h < -0.02:
		return Tile.SEA
	if IslandLayout.in_courtyard(p):
		return Tile.COURTYARD
	if IslandLayout.in_plaza(p):
		return Tile.PLAZA
	if IslandLayout.distance_to_paths(p) <= IslandLayout.PATH_HALF_WIDTH:
		return Tile.PATH
	if dpond < 7.6:
		return Tile.MUD
	if t < 5.5 or h < 0.3:
		return Tile.SAND
	if p.distance_to(IslandLayout.FOREST) < 15.0:
		return Tile.FOREST
	return Tile.GRASS


# --- colours -------------------------------------------------------------------------------------

func tile_color(i: int, j: int) -> Color:
	var x := float(i - HALF) + 0.5
	var z := float(j - HALF) + 0.5
	var t: int = tiles[j * SIZE + i]
	var jitter := _hash01(i, j) - 0.5
	var n := noise.get_noise_2d(x * 2.3, z * 2.3)
	var c: Color
	match t:
		Tile.SEA:
			var depth := clampf(-height_at(x, z) / 3.0, 0.0, 1.0)
			c = Color("d9c48f").lerp(Color("6f7f6a"), depth)
		Tile.SAND, Tile.DOCK_SAND:
			c = Color("e2cf98").lerp(Color("d5bd82"), 0.5 + n * 0.5)
		Tile.GRASS:
			c = Color("6e9e45").lerp(Color("5a8a3a"), 0.5 + n * 0.5)
			if _hash01(i * 7, j * 13) > 0.93:
				c = c.lerp(Color("8fb052"), 0.5)
		Tile.FOREST:
			c = Color("4f7a35").lerp(Color("5d6e34"), 0.5 + n * 0.5)
		Tile.PATH:
			c = Color("b0915f").lerp(Color("9f8152"), 0.5 + n * 0.5)
		Tile.PLAZA:
			c = Color("aaa496") if (i + j) % 2 == 0 else Color("9a9588")
		Tile.COURTYARD:
			c = Color("a59c86") if (i / 2 + j / 2) % 2 == 0 else Color("958d78")
		Tile.POND_BED:
			c = Color("7b7350")
		Tile.MUD:
			c = Color("7d8a48").lerp(Color("8f7d55"), 0.5 + n * 0.5)
	c = c.lightened(jitter * 0.06) if jitter > 0.0 else c.darkened(-jitter * 0.06)
	# Wet sand at the waterline.
	if t == Tile.SAND and height_at(x, z) < 0.2:
		c = c.lerp(Color("b89a62"), 0.55)
	# Steeper tiles are slightly darker.
	var tn := tile_normal(i, j)
	c = c.darkened(clampf((1.0 - tn.y) * 3.0, 0.0, 0.22))
	var ao := occlusion[j * SIZE + i]
	if ao > 0.0:
		c = c.darkened(ao * 0.3)
	return c


func tile_normal(i: int, j: int) -> Vector3:
	var a := vertex_height(i, j)
	var b := vertex_height(i + 1, j)
	var c := vertex_height(i + 1, j + 1)
	var d := vertex_height(i, j + 1)
	return Vector3(((a + d) - (b + c)) * 0.5, 1.0, ((a + b) - (c + d)) * 0.5).normalized()


## Tile colours with softened transitions: where neighbouring tiles differ in type, a tile blends
## partway towards its neighbours, so borders soften while each tile keeps one flat colour.
func soft_colors() -> PackedColorArray:
	var base := PackedColorArray()
	base.resize(SIZE * SIZE)
	for j in SIZE:
		for i in SIZE:
			base[j * SIZE + i] = tile_color(i, j) if _tile_in_mesh(i, j) else Color.BLACK
	var out := base.duplicate()
	for j in range(1, SIZE - 1):
		for i in range(1, SIZE - 1):
			var idx := j * SIZE + i
			var t := tiles[idx]
			var sum := Color(0, 0, 0, 0)
			var differs := false
			for o in [-1, 1, -SIZE, SIZE]:
				sum += base[idx + o]
				if tiles[idx + o] != t:
					differs = true
			if differs and t != Tile.SEA:
				out[idx] = base[idx].lerp(sum / 4.0, 0.3)
	return out


static func _hash01(i: int, j: int) -> float:
	var h := (i * 73856093) ^ (j * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xFFFF) / 65535.0


# --- meshes and collision ------------------------------------------------------------------------

func _tile_in_mesh(i: int, j: int) -> bool:
	var x := float(i - HALF) + 0.5
	var z := float(j - HALF) + 0.5
	return x * x + z * z <= MESH_RADIUS * MESH_RADIUS


func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var count := 0
	for j in SIZE:
		for i in SIZE:
			if _tile_in_mesh(i, j):
				count += 1
	verts.resize(count * 6)
	colors.resize(count * 6)
	normals.resize(count * 6)
	var soft := soft_colors()
	var k := 0
	for j in SIZE:
		for i in SIZE:
			if not _tile_in_mesh(i, j):
				continue
			var x0 := float(i - HALF)
			var z0 := float(j - HALF)
			var a := Vector3(x0, vertex_height(i, j), z0)
			var b := Vector3(x0 + 1, vertex_height(i + 1, j), z0)
			var c := Vector3(x0 + 1, vertex_height(i + 1, j + 1), z0 + 1)
			var d := Vector3(x0, vertex_height(i, j + 1), z0 + 1)
			var col := soft[j * SIZE + i]
			var n1 := (c - a).cross(b - a).normalized()
			var n2 := (d - a).cross(c - a).normalized()
			verts[k] = a; verts[k + 1] = b; verts[k + 2] = c
			verts[k + 3] = a; verts[k + 4] = c; verts[k + 5] = d
			for q in 3:
				normals[k + q] = n1
				normals[k + 3 + q] = n2
			for q in 6:
				colors[k + q] = col
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Collision only for land and shallows: no sea or pond floor, so clicks over open water find no
## ground and the navmesh never covers the seabed.
func build_collision_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	for j in SIZE:
		for i in SIZE:
			var x0 := float(i - HALF)
			var z0 := float(j - HALF)
			var a := Vector3(x0, vertex_height(i, j), z0)
			var b := Vector3(x0 + 1, vertex_height(i + 1, j), z0)
			var c := Vector3(x0 + 1, vertex_height(i + 1, j + 1), z0 + 1)
			var d := Vector3(x0, vertex_height(i, j + 1), z0 + 1)
			var top := maxf(maxf(a.y, b.y), maxf(c.y, d.y))
			var centre := Vector2(x0 + 0.5, z0 + 0.5)
			var floor_level := -0.25
			if centre.distance_to(IslandLayout.POND) < 7.5:
				floor_level = IslandLayout.POND_LEVEL - 0.1
			if top < floor_level:
				continue
			faces.append_array([a, b, c, a, c, d])
	return faces
