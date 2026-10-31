# Ghosts

A Godot 4 app for a projector: pitch black with chalky, softly glowing
ghosts that materialize, drift around and dissolve again. The head leads and the
body follows like slow-motion cloth. Everything is drawn by shaders, so there are
no sprite images to manage.

![screenshot](docs/screenshot.jpg)

## Run it on a Mac

1. Install Godot 4.5 (or newer 4.x) from <https://godotengine.org/download/macos/>.
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **Run** (or F5). It opens in a normal window. Drag the window onto the
   projector (or press `S`), then press `F` or double-click to go fullscreen: that
   hides the title bar, window buttons, menu bar, Dock and mouse cursor.

### Keys

| Key | Action |
| --- | --- |
| `F` / double-click | Toggle fullscreen |
| `S` | Move to the next screen |
| `Up` / `Down` | Add / remove a ghost (they fade in and out) |
| `P` | Spooky screen filter on / off |
| `R` | Reload `ghost_settings.json` |
| `H` | Show / hide the help line |
| `Esc` / `Q` | Quit |

Command-line options (after `--`): `--screen=1`, `--ghosts=12`.

### Make a standalone app

**Project → Export → Add… → macOS**, then export. Godot asks you to download the
export templates the first time.

## How it works

| File | What it does |
| --- | --- |
| `shaders/ghost.gdshader` | Draws one ghost: the outline of the simulated cloth as a chalk body, pink rim, eyes, blush, scalloped hem. |
| `shaders/spooky_screen.gdshader` | Full-screen filter: bloom, film grain, chromatic fringe, projector flicker, vignette. Darks are clamped to true black so the projector shows nothing between ghosts. |
| `scripts/ghost.gd` | Only the head is driven: it wanders with surges and pauses and turns and glances on its own. The body is a real cloth simulation: a 10×5 mass-spring grid (verlet particles with stretch, shear and bend springs) pinned to the head, pushed around by water drag, slow currents and a travelling wave. Each ghost materializes, lives a while, then dissolves. |
| `scripts/main.gd` | Keeps up to 5 ghosts around, staggered: they appear one by one at the start, and a new one appears 3–12 s after one dissolves, keeps them apart, handles keys and screens. |
| `scripts/sparkles.gd` | Twinkling gold chalk crosses. |

### Tuning the look

Every value (population, fades, movement, cloth, face and blinking, colours,
sparkles, screen filter) lives in `ghost_settings.json`. The easiest way to tune
it is the **Ghost Tweaker** page, a live browser copy of the app with a slider
for everything: open `tools/ghost_tweaker.html` in a browser, press
**Copy settings JSON**, paste it into `ghost_settings.json`, and press `R` in
the running app.

The defaults (and what each key means) are in `scripts/settings.gd`. The
tweaker uses the same shaders as the app; after changing a shader or a default,
rebuild it with `python3 tools/build_tweaker.py`.
