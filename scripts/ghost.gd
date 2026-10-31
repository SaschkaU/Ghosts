extends Sprite2D
## One wandering ghost.
##
## Only the head is driven: it moves along a slow, noise-driven path with
## surges and pauses, and turns and looks around on its own. The body is a
## loose chain of points simulated like cloth (verlet with inertia, a little
## stretch, light bending stiffness, a slow travelling wave and turbulence)
## that hangs off the head and gets dragged along behind it.
## shaders/ghost.gdshader draws the body around that chain.
##
## Each ghost has a lifetime: it materializes, drifts for a while, then
## dissolves. main.gd spawns a new one somewhere else afterwards.
##
## All tunable values come from scripts/settings.gd (and ghost_settings.json).

signal gone

const S := preload("res://scripts/settings.gd")
const GHOST_SHADER := preload("res://shaders/ghost.gdshader")
const N := 10                 # must match N in the shader
const QUAD := 2.4             # quad side in ghost lengths

static var _white_tex: Texture2D

var heading := 0.0          # direction of travel, radians
var head_angle := 0.0       # direction the head faces
var turn_rate := 0.0
var avoid := Vector2.ZERO   # set by main.gd to keep ghosts apart
var length_px := 300.0
var area := Rect2()
var dying := false

var _depth := 0.5           # 0 = small & far, 1 = big & close
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _phase := 0.0
var _bob_phase := 0.0
var _presence := 0.0
var _appear_time := 4.0
var _vanish_time := 4.0
var _life_left := 30.0
var _blink_in := 3.0
var _blink_t := -1.0        # < 0 = eyes open
var _mat: ShaderMaterial
var _pts := PackedVector2Array()
var _prev := PackedVector2Array()
var _seg := 10.0
var _rand := {}             # per-ghost 0..1 picks, so live setting changes keep each ghost's character


func setup(rng: RandomNumberGenerator, screen: Vector2) -> void:
	area = Rect2(Vector2.ZERO, screen)
	_rng.seed = rng.randi()
	_noise.seed = rng.randi()
	_noise.frequency = 0.02
	_phase = rng.randf() * 100.0
	_bob_phase = rng.randf() * TAU
	_depth = rng.randf()
	for k in ["body_width", "flare", "scallops", "cloth_speed"]:
		_rand[k] = rng.randf()
	z_index = int(_depth * 100.0)

	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	texture = _white_tex
	_mat = ShaderMaterial.new()
	_mat.shader = GHOST_SHADER
	_mat.set_shader_parameter("quad_size", QUAD)
	_mat.set_shader_parameter("phase", _phase)
	material = _mat
	apply_settings()

	position = Vector2(rng.randf_range(0.15, 0.85) * screen.x, rng.randf_range(0.15, 0.85) * screen.y)
	heading = rng.randf() * TAU
	head_angle = heading
	_appear_time = S.rand(rng, "fade_in")
	_vanish_time = S.rand(rng, "fade_out")
	_life_left = S.rand(rng, "life")
	_blink_in = rng.randf_range(1.0, S.f("blink_max"))

	# Start with the body hanging straight behind the head.
	_pts.resize(N)
	_prev.resize(N)
	var back := -Vector2.from_angle(heading)
	for i in N:
		_pts[i] = position + back * _seg * i
		_prev[i] = _pts[i]
	_push_spine()


## Re-read settings (called on spawn and when the settings file is reloaded).
func apply_settings() -> void:
	length_px = area.size.y * lerpf(S.f("size_min"), S.f("size_max"), _depth)
	_seg = length_px * S.f("body_length") / float(N - 1)
	scale = Vector2.ONE * QUAD * length_px / 4.0
	var pick := func(key: String) -> float:
		return lerpf(S.f(key + "_min"), S.f(key + "_max"), _rand[key])
	_mat.set_shader_parameter("body_width", pick.call("body_width"))
	_mat.set_shader_parameter("flare", pick.call("flare"))
	_mat.set_shader_parameter("scallops", float(round(pick.call("scallops"))))
	_mat.set_shader_parameter("cloth_speed", pick.call("cloth_speed"))
	_mat.set_shader_parameter("cloth_amount", S.f("cloth_amount"))
	_mat.set_shader_parameter("opacity", lerpf(S.f("opacity_far"), S.f("opacity_near"), _depth))
	_mat.set_shader_parameter("tail_fade", S.f("tail_fade"))
	_mat.set_shader_parameter("glow", S.f("glow"))
	_mat.set_shader_parameter("flicker", S.f("ghost_flicker"))
	_mat.set_shader_parameter("eye_size", S.f("eye_size"))
	_mat.set_shader_parameter("blush_amount", S.f("blush"))
	for k in ["body_color", "rim_color", "blush_color", "eye_color", "glow_color"]:
		_mat.set_shader_parameter(k, S.c(k))


func vanish() -> void:
	dying = true


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	_move(delta)
	_simulate_cloth(delta)
	_push_spine()
	_animate_face(delta)
	_lifecycle(delta)


func _move(delta: float) -> void:
	var target_turn := _noise.get_noise_2d(_t * S.f("turn_rate"), 0.0) * S.f("turn_amount")
	# Steer back towards the middle when drifting too far out.
	var inner := area.grow(-length_px * 0.3)
	if not inner.has_point(position):
		var to_centre := (area.get_center() - position).angle()
		target_turn += clampf(angle_difference(heading, to_centre), -1.0, 1.0) * 1.2
	if avoid != Vector2.ZERO:
		target_turn += clampf(angle_difference(heading, avoid.angle()), -1.0, 1.0) * minf(avoid.length(), 1.0)
	turn_rate = lerpf(turn_rate, target_turn, delta * 1.2)
	heading += turn_rate * delta

	# Surges and near-pauses, so the body visibly drags and catches up.
	var surge := clampf(_noise.get_noise_2d(0.0, _t * S.f("surge_rate")) * 1.6 + 0.5, 0.0, 1.0)
	var base := lerpf(S.f("speed_min"), S.f("speed_max"), _depth) * area.size.y / 1080.0
	var spd := base * lerpf(S.f("speed_low"), S.f("speed_high"), surge * surge)
	var dir := Vector2.from_angle(heading)
	var bob := dir.orthogonal() * sin(_t * 1.3 + _bob_phase) * S.f("bob")
	position += dir * spd * delta + bob * delta

	# The head turns on its own: into the curve and glancing around.
	var lead := clampf(turn_rate * S.f("head_lead"), -0.8, 0.8)
	var glance := _noise.get_noise_2d(500.0, _t * 4.0) * S.f("glance")
	head_angle = lerp_angle(head_angle, heading + lead + glance, delta * S.f("head_turn_speed"))


func _simulate_cloth(delta: float) -> void:
	_pts[0] = position
	var damp := pow(clampf(S.f("keep_velocity"), 0.0, 0.99), delta)
	var fl := S.f("flutter") * length_px * delta * delta
	var wave_amount := S.f("wave_amount")
	var wave_speed := S.f("wave_speed")
	for i in range(1, N):
		var k := float(i) / float(N - 1)
		var v := (_pts[i] - _prev[i]) * damp
		_prev[i] = _pts[i]
		var air := Vector2(_noise.get_noise_2d(i * 13.0, _t * 6.0), _noise.get_noise_2d(i * 13.0 + 300.0, _t * 6.0))
		# Slow sideways wave travelling from the head to the hem, like cloth under water.
		var side := (_pts[i - 1] - _pts[i]).normalized().orthogonal()
		var wave := sin(_t * wave_speed - k * 2.5 + _phase) * wave_amount * length_px * k
		_pts[i] += v + air * fl * k * 60.0 + side * wave * delta * delta

	# The body hangs off the head at a single point, so the head can turn
	# freely; everything below just follows.
	var stiffness := S.f("stiffness")
	var stretch := S.f("stretch")
	for _iter in 3:
		for i in range(1, N):
			if i >= 2:
				var straight := _pts[i - 1] + (_pts[i - 1] - _pts[i - 2]).normalized() * _seg
				_pts[i] = _pts[i].lerp(straight, stiffness)
			var d := _pts[i] - _pts[i - 1]
			var l := d.length()
			if l > 0.0001:
				var target := clampf(lerpf(l, _seg, 0.35), _seg * 0.92, _seg * (1.0 + stretch))
				_pts[i] = _pts[i - 1] + d / l * target


func _push_spine() -> void:
	var local := PackedVector2Array()
	local.resize(N)
	for i in N:
		local[i] = (_pts[i] - _pts[0]) / length_px
	_mat.set_shader_parameter("spine", local)
	_mat.set_shader_parameter("head_angle", head_angle)


func _animate_face(delta: float) -> void:
	_mat.set_shader_parameter("look", sin(_t * 0.23 + _phase) * S.f("look_amount"))
	# Occasional blinks, sometimes a quick double blink.
	var dur := maxf(S.f("blink_duration"), 0.05)
	if _blink_t < 0.0:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_t = 0.0
	else:
		_blink_t += delta
		if _blink_t >= dur:
			_blink_t = -1.0
			if _rng.randf() < S.f("double_blink"):
				_blink_in = dur * 0.6
			else:
				_blink_in = S.rand(_rng, "blink")
	var closed := 0.0 if _blink_t < 0.0 else sin(PI * _blink_t / dur)
	_mat.set_shader_parameter("blink", closed)


func _lifecycle(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		dying = true
	if dying:
		_presence = maxf(_presence - delta / _vanish_time, 0.0)
		if _presence <= 0.0:
			gone.emit()
			queue_free()
	else:
		_presence = minf(_presence + delta / _appear_time, 1.0)
	_mat.set_shader_parameter("presence", smoothstep(0.0, 1.0, _presence))
