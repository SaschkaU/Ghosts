extends Sprite2D
## One wandering ghost.
##
## Only the head is driven: it moves along a slow, noise-driven path with
## surges and pauses, and turns and looks around on its own. The body is a
## real piece of cloth: a ROWS x COLS mass-spring grid (verlet particles with
## stretch, shear and bend springs) whose top rows are pinned to the head.
## Water drag, a weak memory of its hanging shape, slow currents and a
## travelling wave push it around, so it trails, folds and billows behind the
## head like fabric underwater. shaders/ghost.gdshader draws its outline.
##
## Each ghost has a lifetime: it materializes, drifts for a while, then
## dissolves. main.gd spawns a new one somewhere else afterwards.
##
## All tunable values come from scripts/settings.gd (and ghost_settings.json).

signal gone

const S := preload("res://scripts/settings.gd")
const GHOST_SHADER := preload("res://shaders/ghost.gdshader")
const ROWS := 10              # must match ROWS / COLS in the shader
const COLS := 5
const PINNED_ROWS := 2        # rows fixed to the head
const SIM_DT := 1.0 / 60.0

static var _white_tex: Texture2D

var heading := 0.0          # direction of travel, radians
var head_angle := 0.0       # direction the head faces
var turn_rate := 0.0
var avoid := Vector2.ZERO   # set by main.gd to keep ghosts apart
var length_px := 300.0
var area := Rect2()
var dying := false
var rainbow := false        # set by main.gd before setup(); see set_rainbow()
var valkyrie := false       # violet Valkyries ghost with a V; see set_valkyrie()
var sequin := false         # covered in rainbow sequins; see set_sequin()

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
var _pts := PackedVector2Array()     # cloth particles, row-major, screen px
var _prev := PackedVector2Array()
var _rest := PackedVector2Array()    # hanging shape in the head's frame (x = right, y = back), px
var _links := PackedInt32Array()     # constraint pairs
var _link_lo := PackedFloat64Array()   # allowed length range (bend springs: exactly the rest length)
var _link_hi := PackedFloat64Array()
var _link_k := PackedFloat64Array()    # strength / number of free ends
var _link_wa := PackedFloat64Array()   # 0 = pinned end, 1 = free end
var _link_wb := PackedFloat64Array()
var _quad := 3.0            # largest quad side the ghost may need, ghost lengths
var _halo_reach := 0.3      # beyond this distance from the body nothing is drawn, ghost lengths
var _sim_acc := 0.0
var _sim_t := 0.0
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

	# Start with the cloth hanging straight behind the head.
	_pts.resize(ROWS * COLS)
	_prev.resize(ROWS * COLS)
	for i in ROWS * COLS:
		_pts[i] = _rest_world(i)
		_prev[i] = _pts[i]
	_push_spine()


## Re-read settings (called on spawn and when the settings file is reloaded).
func apply_settings() -> void:
	length_px = area.size.y * lerpf(S.f("size_min"), S.f("size_max"), _depth)
	# Quad big enough for the longest the body can stretch, plus the halo.
	_quad = 2.0 * (S.f("body_length") * (1.0 + S.f("stretch")) + 0.35)
	# How far outside the cloth outline the shader can still put visible
	# light: the halo (until it drops below 1/1024), the ripples that shift
	# the outline, the scalloped hem bulge and the chalky edge. The quad is
	# fitted to the cloth plus this margin every frame (see _push_spine), so
	# the shader runs only where something can be seen.
	var halo := log(maxf(S.f("glow") * 0.35 * 1.5 * 1024.0, 1.0)) / 38.0
	var ca := absf(S.f("cloth_amount"))
	_halo_reach = halo + 0.092 * ca + 0.03 + 0.015 * ca + 0.04
	var pick := func(key: String) -> float:
		return lerpf(S.f(key + "_min"), S.f(key + "_max"), _rand[key])
	_mat.set_shader_parameter("body_width", pick.call("body_width"))
	_build_cloth(pick.call("body_width"), pick.call("flare"))
	_mat.set_shader_parameter("scallops", float(round(pick.call("scallops"))))
	_mat.set_shader_parameter("cloth_speed", pick.call("cloth_speed"))
	_mat.set_shader_parameter("cloth_amount", S.f("cloth_amount"))
	_mat.set_shader_parameter("opacity", lerpf(S.f("opacity_far"), S.f("opacity_near"), _depth))
	_mat.set_shader_parameter("tail_fade", S.f("tail_fade"))
	_mat.set_shader_parameter("glow", S.f("glow"))
	_mat.set_shader_parameter("flicker", S.f("ghost_flicker"))
	_mat.set_shader_parameter("eye_size", S.f("eye_size"))
	_mat.set_shader_parameter("blush_amount", S.f("blush"))
	_mat.set_shader_parameter("outline", S.f("outline"))
	for k in ["body_color", "rim_color", "blush_color", "eye_color", "glow_color"]:
		_mat.set_shader_parameter(k, S.c(k))
	for k in ["rainbow_speed", "rainbow_bands", "rainbow_saturation"]:
		_mat.set_shader_parameter(k, S.f(k))
	_mat.set_shader_parameter("rainbow", 1.0 if rainbow else 0.0)
	for k in ["valkyrie_v_size", "valkyrie_v_y", "valkyrie_v_width", "valkyrie_v_thickness"]:
		_mat.set_shader_parameter(k, S.f(k))
	for k in ["valkyrie_color", "valkyrie_v_color", "valkyrie_v_edge"]:
		_mat.set_shader_parameter(k, S.c(k))
	_mat.set_shader_parameter("valkyrie", 1.0 if valkyrie else 0.0)
	for k in ["sequin_size", "sequin_bands", "sequin_shuffle", "sequin_speed", "sequin_saturation",
			"sequin_sparkle", "sequin_glint", "sequin_flip", "sequin_shimmer"]:
		_mat.set_shader_parameter(k, S.f(k))
	_mat.set_shader_parameter("sequin_gap", S.c("sequin_gap"))
	_mat.set_shader_parameter("sequin", 1.0 if sequin else 0.0)


func set_rainbow(on: bool) -> void:
	rainbow = on
	if _mat:
		_mat.set_shader_parameter("rainbow", 1.0 if on else 0.0)


func set_valkyrie(on: bool) -> void:
	valkyrie = on
	if _mat:
		_mat.set_shader_parameter("valkyrie", 1.0 if on else 0.0)


func set_sequin(on: bool) -> void:
	sequin = on
	if _mat:
		_mat.set_shader_parameter("sequin", 1.0 if on else 0.0)


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
	# Fixed 60 Hz steps so the feel doesn't depend on the frame rate.
	_sim_acc += delta
	while _sim_acc >= SIM_DT:
		_sim_acc -= SIM_DT
		_sim_t += SIM_DT
		_cloth_step(SIM_DT)


## Rest shape of the cloth and its springs. The cloth hangs from the widest
## line across the head and widens towards the hem (flare).
func _build_cloth(width: float, flare: float) -> void:
	_rest.resize(ROWS * COLS)
	var row_gap := length_px * S.f("body_length") / float(ROWS - 1)
	var head_r := 0.13 * width * length_px
	for r in ROWS:
		var k := float(r) / float(ROWS - 1)
		var half := head_r * (1.0 + flare * k)
		for c in COLS:
			_rest[r * COLS + c] = Vector2((float(c) / float(COLS - 1) * 2.0 - 1.0) * half, r * row_gap)
	_links.clear()
	_link_lo.clear()
	_link_hi.clear()
	_link_k.clear()
	_link_wa.clear()
	_link_wb.clear()
	# Springs (position-based): stretch / shear springs may stretch a little
	# and squash freely like folding fabric; bend springs keep it from crumpling.
	# Springs between two pinned particles never move anything and are left out.
	var stiff := clampf(S.f("cloth_stiffness"), 0.0, 1.0)
	var bend_k := clampf(S.f("cloth_bend"), 0.0, 1.0)
	var stretch := 1.0 + S.f("stretch")
	var squash := 1.0 - S.f("squash")
	var pinned := PINNED_ROWS * COLS
	var add := func(a: int, b: int, bend: int) -> void:
		var wa := 0.0 if a < pinned else 1.0
		var wb := 0.0 if b < pinned else 1.0
		if wa + wb == 0.0:
			return
		# Rest length is kept in 32-bit like the particle positions.
		var rest: float = PackedFloat32Array([_rest[a].distance_to(_rest[b])])[0]
		_links.append(a)
		_links.append(b)
		_link_lo.append(rest if bend == 1 else rest * squash)
		_link_hi.append(rest if bend == 1 else rest * stretch)
		_link_k.append((bend_k if bend == 1 else stiff) / (wa + wb))
		_link_wa.append(wa)
		_link_wb.append(wb)
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			if c + 1 < COLS: add.call(i, i + 1, 0)
			if r + 1 < ROWS: add.call(i, i + COLS, 0)
			if r + 1 < ROWS and c + 1 < COLS:
				add.call(i, i + COLS + 1, 0)
				add.call(i + 1, i + COLS, 0)
			if c + 2 < COLS: add.call(i, i + 2, 1)
			if r + 2 < ROWS: add.call(i, i + 2 * COLS, 1)


func _rest_world(i: int) -> Vector2:
	var fwd := Vector2.from_angle(head_angle)
	var rp := _rest[i]
	return position + fwd.orthogonal() * -rp.x - fwd * rp.y


## The hot loop of the app (runs 60 times a second for every ghost), so it
## works on local copies of the arrays and on values worked out once per step
## or once per cloth build: GDScript is much faster with locals than with
## member lookups, dictionary reads and repeated trig.
func _cloth_step(h: float) -> void:
	var count := ROWS * COLS
	var pinned := PINNED_ROWS * COLS
	var keep := exp(-S.f("water_drag") * h)
	var memory := S.f("shape_memory")
	var grav := Vector2(0.0, S.f("gravity") * length_px)
	var turb := S.f("flutter") * length_px
	var wave_amount := S.f("wave_amount") * length_px
	var wave_speed := S.f("wave_speed")
	var inv_len := 30.0 / length_px
	var sim_t := _sim_t
	var noise := _noise
	var pos := position
	var fwd := Vector2.from_angle(head_angle)
	var side := fwd.orthogonal()
	var rest := _rest
	var pts := _pts
	var prev := _prev
	for i in range(pinned, count):
		var r := i / COLS
		var k := float(r) / float(ROWS - 1)
		var p := pts[i]
		var v := (p - prev[i]) * keep
		prev[i] = p
		var rp := rest[i]
		var acc := grav + (pos + side * -rp.x - fwd * rp.y - p) * memory
		# Slow currents: a noise field the cloth drifts through.
		acc += Vector2(noise.get_noise_2d(p.x * inv_len + sim_t * 6.0, p.y * inv_len),
				noise.get_noise_2d(p.x * inv_len + 300.0, p.y * inv_len - sim_t * 6.0)) * turb * k
		# Travelling wave, pushing sideways to the cloth.
		var up := (pts[i - COLS] - p).normalized()
		acc += up.orthogonal() * sin(sim_t * wave_speed - k * 3.0 + _phase) * sqrt(k) * wave_amount
		pts[i] = p + v + acc * h * h
	for i in pinned:
		var rp := rest[i]
		pts[i] = pos + side * -rp.x - fwd * rp.y
		prev[i] = pts[i]

	# Springs (position-based), set up in _build_cloth. Bend springs have
	# lo == hi == rest length, stretch / shear springs a range they may
	# stretch and squash within.
	var links := _links
	var lo := _link_lo
	var hi := _link_hi
	var kk := _link_k
	var wa := _link_wa
	var wb := _link_wb
	var n := lo.size()
	for _it in S.i("cloth_iterations"):
		for j in n:
			var a := links[2 * j]
			var b := links[2 * j + 1]
			var d := pts[b] - pts[a]
			var l := d.length()
			if l < 0.0001:
				continue
			var target := clampf(l, lo[j], hi[j])
			if target == l:
				continue
			var corr := d * ((l - target) / l * kk[j])
			pts[a] += corr * wa[j]
			pts[b] -= corr * wb[j]

	# Stiff neck: the rows just below the head are held towards their hanging
	# shape, fading out gradually down the body, so the head blends into the cloth.
	var neck := clampf(S.f("neck_stiffness"), 0.0, 1.0)
	var reach := maxf(S.f("neck_length") * float(ROWS - 1), 0.01)
	if neck > 0.0:
		for r in range(PINNED_ROWS, ROWS):
			var fall := 1.0 - float(r - PINNED_ROWS + 1) / (reach + 1.0)
			if fall <= 0.0:
				break
			var w := neck * fall * fall
			for c in COLS:
				var i := r * COLS + c
				var rp := rest[i]
				pts[i] = pts[i].lerp(pos + side * -rp.x - fwd * rp.y, w)
	_pts = pts
	_prev = prev


func _push_spine() -> void:
	var local := PackedVector2Array()
	local.resize(ROWS * COLS)
	var head_r := 0.13 * float(_mat.get_shader_parameter("body_width"))
	var lo := Vector2(-head_r, -head_r)
	var hi := Vector2(head_r, head_r)
	for i in ROWS * COLS:
		var q := (_pts[i] - position) / length_px
		local[i] = q
		lo = lo.min(q)
		hi = hi.max(q)
	_mat.set_shader_parameter("cloth", local)
	_mat.set_shader_parameter("head_angle", head_angle)
	# Draw only the box around the cloth plus its halo, never more than the
	# fixed quad the ghost used to fill (most of which was empty black).
	var half := _quad * 0.5
	lo = (lo - Vector2.ONE * _halo_reach).maxf(-half)
	hi = (hi + Vector2.ONE * _halo_reach).minf(half)
	var size := hi - lo
	_mat.set_shader_parameter("box", Vector4(lo.x, lo.y, size.x, size.y))
	# The texture is 4x4 px and centred: scale stretches it to the box,
	# offset (in texture pixels) moves its centre there.
	scale = size * length_px / 4.0
	offset = (lo + size * 0.5) * length_px / scale


## The screen rect this ghost draws into, in pixels.
func screen_rect() -> Rect2:
	var size := scale * 4.0
	return Rect2(position + offset * scale - size * 0.5, size)


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
