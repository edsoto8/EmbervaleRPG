class_name HitpointsBar
extends Control
## Ten small hearts drawn in code; filled ones pulse gently when health is low.

var current := 10
var maximum := 10
var _t := 0.0


func set_values(c: int, m: int) -> void:
	current = c
	maximum = maxi(m, 1)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if current <= 3:
		queue_redraw()


func _draw() -> void:
	var w := size.x / maximum
	var r := minf(w * 0.42, size.y * 0.45)
	for i in maximum:
		var c := Vector2(w * (i + 0.5), size.y * 0.5)
		var filled := i < current
		var col := Color("ff5a5a") if filled else Color(0.25, 0.15, 0.12, 0.9)
		if filled and current <= 3:
			col = col.lerp(Color("ffb0a0"), 0.5 + 0.5 * sin(_t * 6.0))
		_heart(c, r, col)
		_heart_outline(c, r, Color("2a1510"))


func _heart_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 20:
		var t := k * TAU / 20.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y) * (r / 16.0))
	return pts


func _heart(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(_heart_points(c, r), col)


func _heart_outline(c: Vector2, r: float, col: Color) -> void:
	var pts := _heart_points(c, r)
	pts.append(pts[0])
	draw_polyline(pts, col, 1.0)
