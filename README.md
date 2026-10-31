# Ghosts

A Godot 4 app for a projector: pitch-black fullscreen with chalky, softly glowing
ghosts drifting around. Everything is drawn by shaders, so there are no sprite
images to manage, and the lower half of each ghost moves like slow-motion cloth.

![screenshot](docs/screenshot.jpg)

## Run it on a Mac

1. Install Godot 4.5 (or newer 4.x) from <https://godotengine.org/download/macos/>.
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **Run** (or F5). It opens fullscreen. If a projector is connected, it goes to
   the last screen, which is usually the projector.

### Keys

| Key | Action |
| --- | --- |
| `F` | Toggle fullscreen |
| `S` | Move to the next screen |
| `Up` / `Down` | Add / remove a ghost (they fade in and out) |
| `P` | Spooky screen filter on / off |
| `H` | Show / hide the help line |
| `Esc` / `Q` | Quit |

Command-line options (after `--`): `--screen=1`, `--ghosts=12`.

### Make a standalone app

**Project → Export → Add… → macOS**, then export. Godot asks you to download the
export templates the first time.

## How it works

| File | What it does |
| --- | --- |
| `shaders/ghost.gdshader` | Draws one ghost: chalk body, pink rim, eyes, blush, scalloped hem. The cloth motion lives here. |
| `shaders/spooky_screen.gdshader` | Full-screen filter: bloom, film grain, chromatic fringe, projector flicker, vignette. Darks are clamped to true black so the projector shows nothing between ghosts. |
| `scripts/ghost.gd` | Slow noise-driven wandering. The head leads, the tail bends against turns, and the ghost blinks and glances around. |
| `scripts/main.gd` | Spawns ghosts, keeps them apart, handles keys and screens. |
| `scripts/sparkles.gd` | Twinkling gold chalk crosses. |
| `ghost_preview.tscn` | One big ghost, for tuning the shader live in the editor. |

### Tuning the look

Open `ghost_preview.tscn`, select **Ghost**, and play with the shader parameters
in the Inspector. The useful ones are `cloth_amount`, `cloth_speed`, `flare`,
`scallops`, `tail_fade`, `glow`, and the colours. To change every ghost, edit the
default values at the top of `shaders/ghost.gdshader` or the random ranges in
`scripts/ghost.gd`.

### Using painted ghost images instead

Put PNGs (one upright ghost per image, head at the top, transparent background)
in a `ghost_images/` folder. About half the ghosts will use them, with the same
cloth motion and spooky filter applied.
