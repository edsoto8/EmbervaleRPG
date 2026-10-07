class_name ItemIcon
extends Control
## Draws an item icon in code from ItemDB's icon recipe (no image assets).

var item_id := ""


func set_item(id: String) -> void:
	item_id = id
	queue_redraw()


func _draw() -> void:
	if item_id == "":
		return
	var info := ItemDB.info(item_id)
	var c: Color = info.get("color", Color.WHITE)
	var s := size
	var m := minf(s.x, s.y)
	var o := (s - Vector2(m, m)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * m
	var dark := c.darkened(0.45)
	match info.get("icon", ""):
		"log":
			for k in 2:
				var y := 0.42 + k * 0.2
				draw_rect(Rect2(p.call(0.18, y - 0.08), Vector2(0.56, 0.17) * m), c)
				draw_rect(Rect2(p.call(0.18, y - 0.08), Vector2(0.56, 0.17) * m), dark, false, 1.5)
				draw_circle(p.call(0.76, y + 0.005), 0.085 * m, c.lightened(0.35))
				draw_circle(p.call(0.76, y + 0.005), 0.04 * m, dark)
		"shrimp":
			var pts := PackedVector2Array()
			for k in 9:
				var a := PI * 0.15 + k * 0.17
				pts.append(p.call(0.5 + cos(a) * 0.26, 0.5 + sin(a) * 0.26))
			draw_polyline(pts, c, 0.16 * m, true)
			draw_circle(pts[pts.size() - 1], 0.07 * m, c.lightened(0.2))
			draw_line(pts[0], p.call(0.82, 0.35), dark, 2.0)
		"fish":
			draw_colored_polygon(PackedVector2Array([p.call(0.14, 0.5), p.call(0.4, 0.33), p.call(0.66, 0.4),
					p.call(0.72, 0.5), p.call(0.66, 0.6), p.call(0.4, 0.67)]), c)
			draw_colored_polygon(PackedVector2Array([p.call(0.7, 0.5), p.call(0.88, 0.34), p.call(0.88, 0.66)]), dark)
			draw_circle(p.call(0.26, 0.47), 0.03 * m, Color("1c140e"))
		"bread":
			draw_colored_polygon(PackedVector2Array([p.call(0.16, 0.66), p.call(0.2, 0.42), p.call(0.38, 0.3),
					p.call(0.62, 0.3), p.call(0.8, 0.42), p.call(0.84, 0.66)]), c)
			for k in 3:
				draw_line(p.call(0.35 + k * 0.14, 0.36), p.call(0.3 + k * 0.14, 0.5), dark, 2.0)
		"coins":
			for k in 3:
				var cc: Vector2 = p.call(0.36 + k * 0.12, 0.62 - k * 0.1)
				draw_circle(cc, 0.17 * m, dark)
				draw_circle(cc, 0.14 * m, c)
				draw_circle(cc, 0.06 * m, c.lightened(0.3))
		"sword":
			draw_line(p.call(0.25, 0.75), p.call(0.78, 0.22), c, 0.09 * m)
			draw_line(p.call(0.2, 0.6), p.call(0.4, 0.8), Color("c9a34a"), 0.07 * m)
			draw_line(p.call(0.14, 0.86), p.call(0.28, 0.72), Color("4a3424"), 0.07 * m)
		"rod":
			draw_line(p.call(0.2, 0.84), p.call(0.82, 0.16), c, 0.06 * m)
			draw_line(p.call(0.82, 0.16), p.call(0.82, 0.6), Color("e8e0c8"), 1.2)
			draw_circle(p.call(0.32, 0.7), 0.07 * m, Color("6e6a62"))
		"tinderbox":
			draw_rect(Rect2(p.call(0.22, 0.36), Vector2(0.56, 0.36) * m), c)
			draw_rect(Rect2(p.call(0.22, 0.36), Vector2(0.56, 0.12) * m), c.lightened(0.2))
			draw_circle(p.call(0.66, 0.26), 0.06 * m, Color("ffb347"))
		"axe":
			draw_line(p.call(0.26, 0.84), p.call(0.66, 0.2), Color("7d5634"), 0.07 * m)
			draw_colored_polygon(PackedVector2Array([p.call(0.56, 0.18), p.call(0.82, 0.12), p.call(0.86, 0.42),
					p.call(0.62, 0.36)]), c)
