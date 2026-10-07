class_name EmberMark
extends Control
## The ember emblem above the title, drawn in code: a flame over a small island, with drifting sparks.

var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.72)
	var s := size.y / 74.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-34, 4) * s, c + Vector2(-18, -4) * s, c + Vector2(0, -6) * s,
			c + Vector2(18, -4) * s, c + Vector2(34, 4) * s, c + Vector2(0, 10) * s]), Color("3f6e3a"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-40, 6) * s, c + Vector2(40, 6) * s, c + Vector2(0, 14) * s]), Color("2f6e9e"))
	var flick := 1.0 + 0.06 * sin(_t * 9.0) + 0.04 * sin(_t * 13.7)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 24:
		var t := k * TAU / 24.0
		var rr := (1.0 + 0.35 * cos(t) * cos(t)) * (1.0 + 0.05 * sin(_t * 7.0 + k))
		var x := 14.0 * sin(t) * rr
		var y := -(22.0 * cos(t) + 10.0) * (1.0 if cos(t) < 0.0 else 1.9) * flick
		outer.append(c + Vector2(x, y - 4) * s)
		inner.append(c + Vector2(x * 0.5, y * 0.55 - 6) * s)
	draw_colored_polygon(outer, Color("e0753a"))
	draw_colored_polygon(inner, Color("ffd36a"))
	_rng.seed = 7
	for k in 6:
		var phase := fmod(_t * 0.35 + k * 0.17, 1.0)
		var x := (_rng.randf() - 0.5) * 50.0 + sin((_t + k) * 2.0) * 4.0
		var y := -30.0 - phase * 40.0
		draw_circle(c + Vector2(x, y) * s, (2.2 - phase * 1.6) * s, Color(1.0, 0.8, 0.4, 1.0 - phase))
