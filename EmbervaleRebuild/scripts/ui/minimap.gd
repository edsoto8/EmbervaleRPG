class_name Minimap
extends Control
## North-up map of the whole island: terrain colours, buildings, the player arrow (facing), NPC dots
## and the current objective star.

var island: TutorialIsland
var player: PlayerController
var director: TutorialDirector
var _texture: ImageTexture
var _time := 0.0


func setup(i: TutorialIsland, p: PlayerController, d: TutorialDirector) -> void:
	island = i
	player = p
	director = d
	var n := IslandTerrain.SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for k in n:
			var t: int = island.terrain.tiles[j * n + k]
			var c := island.terrain.tile_color(k, j)
			if t == IslandTerrain.Tile.SEA or t == IslandTerrain.Tile.POND_BED:
				c = Color("2f6e9e") if t == IslandTerrain.Tile.SEA else Color("3d86b8")
			img.set_pixel(k, j, c)
	for cpos in IslandLayout.COTTAGES:
		_stamp(img, cpos, 2, Color("8a4b33"))
	_stamp(img, IslandLayout.GATE, 2, Color("8d8a82"))
	_texture = ImageTexture.create_from_image(img)


func _stamp(img: Image, p: Vector2, r: int, c: Color) -> void:
	var cx := int(p.x) + IslandTerrain.HALF
	var cy := int(p.y) + IslandTerrain.HALF
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < IslandTerrain.SIZE and y < IslandTerrain.SIZE:
				img.set_pixel(x, y, c)


func to_map(p: Vector3) -> Vector2:
	return Vector2((p.x + IslandTerrain.HALF) / IslandTerrain.SIZE * size.x,
			(p.z + IslandTerrain.HALF) / IslandTerrain.SIZE * size.y)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("1c140e"))
	if _texture == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	if director:
		for npc in director.npcs.values():
			draw_circle(to_map(npc.global_position), 3.0, Color("ffe066"))
			draw_arc(to_map(npc.global_position), 3.0, 0, TAU, 10, Color("3a2410"), 1.0)
		var target := director.objective_target()
		if target != Vector3.INF:
			_star(to_map(target), 7.0 + sin(_time * 4.0), Color("ffd36a"))
	for spot in get_tree().get_nodes_in_group("fishing_spot"):
		var c := to_map(spot.global_position)
		draw_arc(c, 2.5 + 1.0 * sin(_time * 3.0), 0, TAU, 12, Color(0.85, 0.95, 1.0, 0.9), 1.2)
	for fire in get_tree().get_nodes_in_group("fire"):
		if fire.is_burning():
			var c := to_map(fire.global_position)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.5), c + Vector2(3, 2.5), c + Vector2(-3, 2.5)]), Color("ff8a3a"))
	if player:
		var c := to_map(player.global_position)
		var yaw := player.facing_yaw()
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(-fwd.y, fwd.x)
		var tri := PackedVector2Array([c + fwd * 7.0, c - fwd * 4.0 + right * 4.5, c - fwd * 4.0 - right * 4.5])
		draw_colored_polygon(tri, Color.WHITE)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color("1c140e"), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.BORDER, false, 2.0)
	draw_string(get_theme_default_font(), Vector2(size.x - 14, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color("3a2410"), 1.2)
