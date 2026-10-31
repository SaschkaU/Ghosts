extends Node2D
## Projector ghosts. Pitch black background, wandering ghosts, spooky filter.
##
## Keys:  F fullscreen · S next screen · Up/Down more/fewer ghosts
##        P filter on/off · R reload ghost_settings.json · H help · Esc quit
## Command line (after `--`):  --screen=1  --ghosts=12

const S := preload("res://scripts/settings.gd")
const Ghost := preload("res://scripts/ghost.gd")
const Sparkles := preload("res://scripts/sparkles.gd")
const SCREEN_SHADER := preload("res://shaders/spooky_screen.gdshader")

var ghost_count := 5

var _rng := RandomNumberGenerator.new()
var _ghost_layer: Node2D
var _sparkles: Node2D
var _filter: ColorRect
var _help: Label
var _count_override := -1


func _ready() -> void:
	_rng.randomize()
	S.load_file()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_parse_args()
	ghost_count = _count_override if _count_override >= 0 else S.i("ghost_count")

	_sparkles = Sparkles.new()
	add_child(_sparkles)
	_ghost_layer = Node2D.new()
	add_child(_ghost_layer)

	var fx := CanvasLayer.new()
	fx.layer = 10
	add_child(fx)
	_filter = ColorRect.new()
	_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SCREEN_SHADER
	_filter.material = mat
	fx.add_child(_filter)
	_apply_filter()

	var ui := CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	_help = Label.new()
	_help.text = "F fullscreen   S next screen   Up/Down ghosts   P filter   R reload settings   H help   Esc quit"
	_help.position = Vector2(24, 20)
	_help.modulate = Color(1, 1, 1, 0.5)
	ui.add_child(_help)
	get_tree().create_timer(5.0).timeout.connect(func(): _help.visible = false)

	get_viewport().size_changed.connect(_reset)
	# Defer so the window has its final size (fullscreen / screen switch).
	_reset.call_deferred()


func _parse_args() -> void:
	var screen := -1
	if DisplayServer.get_screen_count() > 1:
		screen = DisplayServer.get_screen_count() - 1   # projector is usually the last screen
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--screen="):
			screen = int(arg.get_slice("=", 1))
		elif arg.begins_with("--ghosts="):
			_count_override = maxi(int(arg.get_slice("=", 1)), 0)
	if screen >= 0:
		_move_to_screen(screen)


func _move_to_screen(idx: int) -> void:
	var win := get_window()
	idx = posmod(idx, DisplayServer.get_screen_count())
	var mode := win.mode
	win.mode = Window.MODE_WINDOWED
	win.current_screen = idx
	win.mode = mode


func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _apply_filter() -> void:
	_filter.visible = S.b("filter_on")
	var mat := _filter.material as ShaderMaterial
	mat.set_shader_parameter("bloom", S.f("bloom"))
	mat.set_shader_parameter("bloom_radius", S.f("bloom_radius"))
	mat.set_shader_parameter("grain", S.f("grain"))
	mat.set_shader_parameter("aberration", S.f("aberration"))
	mat.set_shader_parameter("flicker", S.f("screen_flicker"))
	mat.set_shader_parameter("vignette", S.f("vignette"))
	mat.set_shader_parameter("black_floor", S.f("black_floor"))


func _reload_settings() -> void:
	S.load_file()
	if _count_override < 0:
		ghost_count = S.i("ghost_count")
	_apply_filter()
	_sparkles.setup(_rng, _screen_size())
	for g in _alive():
		g.apply_settings()
	var gs := _alive()
	while gs.size() > ghost_count:
		gs.pop_back().vanish()
	for i in ghost_count - gs.size():
		_spawn_later(_rng.randf_range(0.5, 1.0 + i * S.f("start_stagger")))


func _reset() -> void:
	var size := _screen_size()
	_sparkles.setup(_rng, size)
	for g in _ghost_layer.get_children():
		g.gone.disconnect(_on_ghost_gone)
		g.queue_free()
	# Stagger the first appearances instead of popping in all at once.
	for i in ghost_count:
		_spawn_later(0.5 if i == 0 else _rng.randf_range(1.0, 1.0 + i * S.f("start_stagger")))


func _spawn_later(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if _alive().size() < ghost_count:
		_spawn()


func _spawn() -> void:
	var g := Ghost.new()
	g.setup(_rng, _screen_size())
	g.gone.connect(_on_ghost_gone)
	_ghost_layer.add_child(g)


func _on_ghost_gone() -> void:
	# Keep the population steady: something new appears a little later, elsewhere.
	_spawn_later(S.rand(_rng, "respawn"))


func _alive() -> Array:
	return _ghost_layer.get_children().filter(func(g): return not g.dying)


func _process(_delta: float) -> void:
	# Keep ghosts from sitting on top of each other.
	var gs := _alive()
	for g in gs:
		g.avoid = Vector2.ZERO
	var space := S.f("personal_space")
	for i in gs.size():
		for j in range(i + 1, gs.size()):
			var a: Node2D = gs[i]
			var b: Node2D = gs[j]
			var d := b.position - a.position
			var r: float = (a.length_px + b.length_px) * space
			if d.length() < r and d.length() > 0.01:
				var push := d.normalized() * (1.0 - d.length() / r)
				a.avoid -= push
				b.avoid += push


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE, KEY_Q:
			get_tree().quit()
		KEY_F:
			var win := get_window()
			win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_S:
			_move_to_screen(get_window().current_screen + 1)
		KEY_UP:
			ghost_count += 1
			_spawn()
		KEY_DOWN:
			var gs := _alive()
			if not gs.is_empty():
				ghost_count -= 1
				gs.pick_random().vanish()
		KEY_P:
			_filter.visible = not _filter.visible
		KEY_R:
			_reload_settings()
		KEY_H:
			_help.visible = not _help.visible
