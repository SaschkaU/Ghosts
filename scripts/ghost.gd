extends Sprite2D
## One wandering ghost. Movement is slow, noise-driven drifting; the head leads
## and the cloth trails. Everything visual lives in shaders/ghost.gdshader.

const GHOST_SHADER := preload("res://shaders/ghost.gdshader")

static var _white_tex: Texture2D

var heading := 0.0          # direction of travel, radians
var turn_rate := 0.0
var speed := 60.0
var avoid := Vector2.ZERO   # set by main.gd to keep ghosts apart
var length_px := 300.0
var area := Rect2()
var dying := false

var _noise := FastNoiseLite.new()
var _t := 0.0
var _phase := 0.0
var _blink_in := 3.0
var _blink := 0.0
var _life := 0.0
var _bob_phase := 0.0
var _mat: ShaderMaterial


func setup(rng: RandomNumberGenerator, screen: Vector2, image: Texture2D = null) -> void:
	area = Rect2(Vector2.ZERO, screen)
	_noise.seed = rng.randi()
	_noise.frequency = 0.02
	_phase = rng.randf() * 100.0
	_bob_phase = rng.randf() * TAU

	# Size: some small & far, some big & close.
	var depth := rng.randf()
	length_px = screen.y * lerpf(0.20, 0.42, depth)
	speed = lerpf(28.0, 70.0, depth) * screen.y / 1080.0
	z_index = int(depth * 100.0)

	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	texture = _white_tex
	var aspect := 0.8
	scale = Vector2(length_px * aspect, length_px) / 4.0

	_mat = ShaderMaterial.new()
	_mat.shader = GHOST_SHADER
	_mat.set_shader_parameter("aspect", aspect)
	_mat.set_shader_parameter("phase", _phase)
	_mat.set_shader_parameter("body_width", rng.randf_range(0.75, 1.15))
	_mat.set_shader_parameter("flare", rng.randf_range(0.15, 0.5))
	_mat.set_shader_parameter("scallops", float(rng.randi_range(2, 4)))
	_mat.set_shader_parameter("cloth_speed", rng.randf_range(0.4, 0.7))
	# Far ghosts are dimmer.
	_mat.set_shader_parameter("opacity", lerpf(0.6, 0.95, depth))
	if image:
		_mat.set_shader_parameter("use_texture", true)
		_mat.set_shader_parameter("ghost_texture", image)
	material = _mat

	position = Vector2(rng.randf_range(0.1, 0.9) * screen.x, rng.randf_range(0.1, 0.9) * screen.y)
	heading = rng.randf() * TAU
	rotation = heading + PI / 2.0
	modulate.a = 0.0
	_blink_in = rng.randf_range(1.0, 6.0)


func vanish() -> void:
	dying = true


func _process(delta: float) -> void:
	_t += delta
	_life += delta

	# Wandering: slowly varying turn rate.
	var target_turn := _noise.get_noise_2d(_t * 10.0, 0.0) * 1.1
	# Steer back towards the middle when drifting too far out.
	var margin := length_px * 0.25
	var inner := area.grow(-margin)
	if not inner.has_point(position):
		var to_centre := (area.get_center() - position).angle()
		target_turn += clampf(angle_difference(heading, to_centre), -1.0, 1.0) * 1.2
	if avoid != Vector2.ZERO:
		target_turn += clampf(angle_difference(heading, avoid.angle()), -1.0, 1.0) * minf(avoid.length(), 1.0)
	turn_rate = lerpf(turn_rate, target_turn, delta * 1.2)
	heading += turn_rate * delta

	var spd := speed * (0.75 + 0.35 * (_noise.get_noise_2d(0.0, _t * 6.0) + 1.0) * 0.5)
	var dir := Vector2.from_angle(heading)
	var bob := dir.orthogonal() * sin(_t * 1.3 + _bob_phase) * 6.0
	position += dir * spd * delta + bob * delta

	# Head leads, body lags a little.
	rotation = lerp_angle(rotation, heading + PI / 2.0, delta * 1.5)

	# Tail trails opposite to the turn.
	_mat.set_shader_parameter("bend", clampf(-turn_rate * 0.8, -0.7, 0.7))
	_mat.set_shader_parameter("look", sin(_t * 0.23 + _phase) * 0.8)

	# Blinking.
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink = 1.0
		_blink_in = randf_range(2.5, 7.0)
	_blink = maxf(_blink - delta * 6.0, 0.0)
	_mat.set_shader_parameter("blink", sin(_blink * PI))

	# Fade in on spawn, fade out when removed.
	if dying:
		modulate.a = maxf(modulate.a - delta * 0.5, 0.0)
		if modulate.a <= 0.0:
			queue_free()
	else:
		modulate.a = minf(modulate.a + delta * 0.4, 1.0)
