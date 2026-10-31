extends Node2D
## Little gold chalk crosses and dashes that twinkle and drift in the dark.

const S := preload("res://scripts/settings.gd")

var _items: Array[Dictionary] = []
var _t := 0.0


func setup(rng: RandomNumberGenerator, screen: Vector2) -> void:
	_items.clear()
	var unit := screen.y / 1080.0 * S.f("sparkle_size")
	for i in S.i("sparkle_count"):
		_items.append({
			"pos": Vector2(rng.randf() * screen.x, rng.randf() * screen.y),
			"size": rng.randf_range(8.0, 22.0) * unit,
			"rot": rng.randf_range(-0.5, 0.5),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.3, 1.1),
			"kind": rng.randi_range(0, 2),
			"drift": Vector2(rng.randf_range(-4, 4), rng.randf_range(-6, 2)) * screen.y / 1080.0,
			"screen": screen,
		})


func _process(delta: float) -> void:
	_t += delta * S.f("sparkle_speed")
	for it in _items:
		var p: Vector2 = it.pos + it.drift * delta
		var s: Vector2 = it.screen
		it.pos = Vector2(fposmod(p.x, s.x), fposmod(p.y, s.y))
	queue_redraw()


func _draw() -> void:
	var color := S.c("sparkle_color")
	for it in _items:
		var tw := 0.5 + 0.5 * sin(_t * it.speed + it.phase)
		var a := pow(tw, 3.0)
		if a < 0.02:
			continue
		var c := color
		c.a = a
		var sz: float = it.size * (0.7 + 0.3 * tw)
		var w := maxf(sz * 0.14, 1.5)
		draw_set_transform(it.pos, it.rot, Vector2.ONE)
		match it.kind:
			0:  # plus sparkle
				draw_line(Vector2(-sz, 0), Vector2(sz, 0), c, w, true)
				draw_line(Vector2(0, -sz * 1.2), Vector2(0, sz * 1.2), c, w, true)
			1:  # x sparkle
				draw_line(Vector2(-sz, -sz) * 0.7, Vector2(sz, sz) * 0.7, c, w, true)
				draw_line(Vector2(-sz, sz) * 0.7, Vector2(sz, -sz) * 0.7, c, w, true)
			2:  # motion dashes
				draw_line(Vector2(-sz * 0.3, -sz), Vector2(sz * 0.1, sz), c, w * 0.8, true)
				draw_line(Vector2(sz * 0.3, -sz * 0.8), Vector2(sz * 0.6, sz * 0.6), c, w * 0.8, true)
	draw_set_transform(Vector2.ZERO)
