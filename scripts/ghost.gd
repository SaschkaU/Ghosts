extends Sprite2D
## One wandering ghost.
##
## Only the head is driven: it moves along a slow, noise-driven path with
## surges and pauses, and turns and looks around on its own. The body is a
## loose chain of points simulated like cloth (verlet with inertia, a little
## stretch, light bending stiffness and air flutter) that just hangs off the
## head and gets dragged along behind it. shaders/ghost.gdshader
## draws the body around that chain.
##
## Each ghost has a lifetime: it materializes, drifts for a while, then
## dissolves. main.gd spawns a new one somewhere else afterwards.

signal gone

const GHOST_SHADER := preload("res://shaders/ghost.gdshader")
const N := 10                 # must match N in the shader
const QUAD := 2.4             # quad side in ghost lengths
const BODY := 0.72            # head centre to hem, in ghost lengths

static var _white_tex: Texture2D

## Cloth feel.
@export var stiffness := 0.1        # 0 = limp rope, 1 = stiff stick
@export var stretch := 0.3          # how much the cloth may stretch when yanked (0.3 = 30 %)
@export var keep_velocity := 0.6    # per second; higher = more drag, swing and follow-through
@export var flutter := 0.4          # slow turbulence on the cloth, in ghost lengths / s²
@export var wave_amount := 0.9      # big slow undulation travelling down the body
@export var wave_speed := 0.6       # radians / s; low = slow-motion, underwater feel

var heading := 0.0          # direction of travel, radians
var head_angle := 0.0       # direction the head faces (leads into turns)
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
var _bob_phase := 0.0
var _presence := 0.0
var _appear_time := 4.0
var _vanish_time := 4.0
var _life_left := 30.0
var _mat: ShaderMaterial
var _pts := PackedVector2Array()
var _prev := PackedVector2Array()
var _seg := 10.0


func setup(rng: RandomNumberGenerator, screen: Vector2, lifetime := Vector2(15.0, 55.0)) -> void:
	area = Rect2(Vector2.ZERO, screen)
	_noise.seed = rng.randi()
	_noise.frequency = 0.02
	_phase = rng.randf() * 100.0
	_bob_phase = rng.randf() * TAU

	# Size: some small & far, some big & close.
	var depth := rng.randf()
	length_px = screen.y * lerpf(0.24, 0.45, depth)
	speed = lerpf(30.0, 70.0, depth) * screen.y / 1080.0
	z_index = int(depth * 100.0)
	_seg = length_px * BODY / float(N - 1)

	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	texture = _white_tex
	scale = Vector2.ONE * QUAD * length_px / 4.0

	_mat = ShaderMaterial.new()
	_mat.shader = GHOST_SHADER
	_mat.set_shader_parameter("quad_size", QUAD)
	_mat.set_shader_parameter("phase", _phase)
	_mat.set_shader_parameter("body_width", rng.randf_range(0.8, 1.15))
	_mat.set_shader_parameter("flare", rng.randf_range(0.15, 0.5))
	_mat.set_shader_parameter("scallops", float(rng.randi_range(2, 4)))
	_mat.set_shader_parameter("cloth_speed", rng.randf_range(0.22, 0.35))
	_mat.set_shader_parameter("opacity", lerpf(0.65, 0.95, depth))  # far ghosts are dimmer
	_mat.set_shader_parameter("presence", 0.0)
	material = _mat

	position = Vector2(rng.randf_range(0.15, 0.85) * screen.x, rng.randf_range(0.15, 0.85) * screen.y)
	heading = rng.randf() * TAU
	head_angle = heading
	_appear_time = rng.randf_range(3.0, 8.0)
	_vanish_time = rng.randf_range(3.0, 8.0)
	_life_left = rng.randf_range(lifetime.x, lifetime.y)
	_blink_in = rng.randf_range(1.0, 6.0)

	# Start with the body hanging straight behind the head.
	_pts.resize(N)
	_prev.resize(N)
	var back := -Vector2.from_angle(heading)
	for i in N:
		_pts[i] = position + back * _seg * i
		_prev[i] = _pts[i]
	_push_spine()


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
	var target_turn := _noise.get_noise_2d(_t * 10.0, 0.0) * 1.2
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
	var surge := clampf(_noise.get_noise_2d(0.0, _t * 6.0) * 1.6 + 0.5, 0.0, 1.0)
	var spd := speed * lerpf(0.2, 1.4, surge * surge)
	var dir := Vector2.from_angle(heading)
	var bob := dir.orthogonal() * sin(_t * 1.3 + _bob_phase) * 8.0
	position += dir * spd * delta + bob * delta

	# The head turns on its own: into the curve and glancing around.
	var glance := _noise.get_noise_2d(500.0, _t * 4.0) * 0.7
	head_angle = lerp_angle(head_angle, heading + clampf(turn_rate * 0.6, -0.6, 0.6) + glance, delta * 2.0)


func _simulate_cloth(delta: float) -> void:
	_pts[0] = position
	var damp := pow(keep_velocity, delta)
	var fl := flutter * length_px * delta * delta
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
	for _iter in 3:
		for i in range(1, N):
			# Light bending stiffness: pull towards the straight continuation.
			if i >= 2:
				var straight := _pts[i - 1] + (_pts[i - 1] - _pts[i - 2]).normalized() * _seg
				_pts[i] = _pts[i].lerp(straight, stiffness)
			# Segment length: springy, may stretch a bit when the head pulls.
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
	_mat.set_shader_parameter("look", sin(_t * 0.23 + _phase) * 0.8)
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink = 1.0
		_blink_in = randf_range(2.5, 7.0)
	_blink = maxf(_blink - delta * 6.0, 0.0)
	_mat.set_shader_parameter("blink", sin(_blink * PI))


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
