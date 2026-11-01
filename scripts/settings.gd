extends RefCounted
## Every tunable value of the ghosts, in one place.
##
## Defaults live here. `res://ghost_settings.json` (exported from the tweak
## page) overrides any of them. Press R in the running app to reload the file.

const PATH := "res://ghost_settings.json"

const DEFAULTS := {
	# Population & lifecycle (seconds)
	"ghost_count": 5,
	"start_stagger": 4.0,
	"life_min": 9.0, "life_max": 26.0,
	"fade_in_min": 5.5, "fade_in_max": 16.0,
	"fade_out_min": 3.0, "fade_out_max": 8.0,
	"respawn_min": 3.0, "respawn_max": 12.0,
	# Size & head movement
	"size_min": 0.33, "size_max": 0.19,          # ghost length, fraction of screen height
	"speed_min": 99, "speed_max": 131.0,        # px/s at 1080p (small ghosts are slower)
	"speed_low": 2.0, "speed_high": 1.95,         # surges: slowest / fastest multiplier
	"surge_rate": 30.0,                           # how quickly the speed changes
	"turn_amount": 3.9,                          # how much the path wanders
	"turn_rate": 19.0,                           # how quickly the wandering changes
	"head_lead": 0.85,                            # head looks into turns
	"glance": 0.7,                               # head looks around on its own
	"head_turn_speed": 2.0,
	"bob": 8.0,                                  # sideways floating wobble, px
	"personal_space": 0.4,                       # how far ghosts keep apart
	# Cloth simulation (the body): a mass-spring grid pinned to the head
	"body_length": 0.97,                         # head centre to hem, in ghost lengths
	"neck_stiffness": 0.07,                      # holds the rows below the head in shape
	"neck_length": 0.73,                          # how far down that fades out (fraction of the body)
	"cloth_stiffness": 0.2,                      # stretch & shear springs, 0..1
	"cloth_bend": 0.18,                           # bend springs, 0 = crumples, 1 = stiff sheet
	"stretch": 0.35,                             # how far the cloth may stretch
	"squash": 0.83,                              # how far it may bunch up (like folding)
	"water_drag": 5.45,                           # velocity lost per second; higher = thicker water
	"shape_memory": 6.85,                         # pull back to hanging straight behind the head
	"gravity": -0.35,                              # downward pull, ghost lengths/s²
	"flutter": 1.15,                              # slow currents pushing the cloth around
	"wave_amount": 0.55,                          # travelling wave along the body
	"wave_speed": 0.6,
	"cloth_iterations": 9,                       # spring solver passes per step
	# Shape (randomized per ghost between min and max)
	"body_width_min": 0.8, "body_width_max": 1.15,
	"flare_min": 0.5, "flare_max": 0.9,
	"scallops_min": 2, "scallops_max": 4,
	# Shader cloth detail
	"cloth_amount": 0.75,
	"cloth_speed_min": 0.22, "cloth_speed_max": 0.53,
	# Look
	"opacity_far": 0.77, "opacity_near": 0.95,
	"tail_fade": 0.45,
	"glow": 1.45,
	"ghost_flicker": 0.38,
	# Face
	"blink_min": 1, "blink_max": 4,          # seconds between blinks
	"blink_duration": 0.25,
	"double_blink": 0.5,                         # chance of a quick second blink
	"look_amount": 1.3,                          # eyes glance left/right
	"eye_size": 2.5,
	"blush": 1.0,
	"outline": 0.0,                              # pink chalk outline strength (0 = none)
	# Rainbow ghost
	"rainbow_ghosts": 1,                         # how many of the ghosts are rainbow-coloured
	"rainbow_speed": 0.12,                       # colour cycles per second
	"rainbow_bands": 1.0,                        # rainbows from head to hem
	"rainbow_saturation": 0.6,                   # 0 = cream, 1 = full colour
	# Colours
	"body_color": "#f5edd9",
	"rim_color": "#d1618c",
	"blush_color": "#ed8ca8",
	"eye_color": "#0a080a",
	"glow_color": "#ccc7f2",
	"sparkle_color": "#d9a840",
	# Sparkles
	"sparkle_count": 0,
	"sparkle_size": 1.0,
	"sparkle_speed": 3.65,
	# Screen filter
	"filter_on": true,
	"bloom": 1.75,
	"bloom_radius": 33.0,
	"grain": 0.18,
	"aberration": 6.2,
	"screen_flicker": 0.21,
	"vignette": 0.0,
	"black_floor": 0.0,
}

static var data := DEFAULTS.duplicate()


static func load_file() -> void:
	data = DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		for k in parsed:
			if DEFAULTS.has(k):
				data[k] = parsed[k]
	else:
		push_warning("ghost_settings.json could not be read; using defaults")


static func f(key: String) -> float:
	return float(data[key])


static func i(key: String) -> int:
	return int(round(float(data[key])))


static func b(key: String) -> bool:
	return bool(data[key])


static func c(key: String) -> Color:
	return Color.html(str(data[key]))


static func rand(rng: RandomNumberGenerator, key: String) -> float:
	return rng.randf_range(f(key + "_min"), maxf(f(key + "_min"), f(key + "_max")))
