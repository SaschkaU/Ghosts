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
	"life_min": 15.0, "life_max": 55.0,
	"fade_in_min": 3.0, "fade_in_max": 8.0,
	"fade_out_min": 3.0, "fade_out_max": 8.0,
	"respawn_min": 3.0, "respawn_max": 12.0,
	# Size & head movement
	"size_min": 0.24, "size_max": 0.45,          # ghost length, fraction of screen height
	"speed_min": 30.0, "speed_max": 70.0,        # px/s at 1080p (small ghosts are slower)
	"speed_low": 0.2, "speed_high": 1.4,         # surges: slowest / fastest multiplier
	"surge_rate": 6.0,                           # how quickly the speed changes
	"turn_amount": 1.2,                          # how much the path wanders
	"turn_rate": 10.0,                           # how quickly the wandering changes
	"head_lead": 0.6,                            # head looks into turns
	"glance": 0.7,                               # head looks around on its own
	"head_turn_speed": 2.0,
	"bob": 8.0,                                  # sideways floating wobble, px
	"personal_space": 0.4,                       # how far ghosts keep apart
	# Cloth simulation (the body)
	"body_length": 0.72,                         # head centre to hem, in ghost lengths
	"stiffness": 0.1,
	"stretch": 0.3,
	"keep_velocity": 0.6,
	"flutter": 0.4,
	"wave_amount": 0.9,
	"wave_speed": 0.6,
	# Shape (randomized per ghost between min and max)
	"body_width_min": 0.8, "body_width_max": 1.15,
	"flare_min": 0.15, "flare_max": 0.5,
	"scallops_min": 2, "scallops_max": 4,
	# Shader cloth detail
	"cloth_amount": 1.0,
	"cloth_speed_min": 0.22, "cloth_speed_max": 0.35,
	# Look
	"opacity_far": 0.65, "opacity_near": 0.95,
	"tail_fade": 0.45,
	"glow": 0.55,
	"ghost_flicker": 0.08,
	# Face
	"blink_min": 3.0, "blink_max": 9.0,          # seconds between blinks
	"blink_duration": 0.3,
	"double_blink": 0.3,                         # chance of a quick second blink
	"look_amount": 0.8,                          # eyes glance left/right
	"eye_size": 1.0,
	"blush": 0.9,
	# Colours
	"body_color": "#f5edd9",
	"rim_color": "#d1618c",
	"blush_color": "#ed8ca8",
	"eye_color": "#0a080a",
	"glow_color": "#ccc7f2",
	"sparkle_color": "#d9a840",
	# Sparkles
	"sparkle_count": 26,
	"sparkle_size": 1.0,
	"sparkle_speed": 1.0,
	# Screen filter
	"filter_on": true,
	"bloom": 0.7,
	"bloom_radius": 14.0,
	"grain": 0.1,
	"aberration": 2.0,
	"screen_flicker": 0.05,
	"vignette": 0.55,
	"black_floor": 0.012,
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
