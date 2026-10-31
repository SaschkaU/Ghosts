#!/usr/bin/env python3
"""Build tools/ghost_tweaker.html from the Godot shaders and settings defaults.

The browser preview uses the exact same shader code as the Godot project,
translated mechanically from Godot's shading language to WebGL2 GLSL, and the
defaults from ghost_settings.json. Run after changing a shader or a setting:

    python3 tools/build_tweaker.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def to_glsl(src: str) -> str:
    src = re.sub(r"^shader_type.*$", "", src, flags=re.M)
    src = re.sub(r"^render_mode.*$", "", src, flags=re.M)
    # uniforms: drop hints and default values
    def uni(m):
        return f"uniform {m.group(1)} {m.group(2)};"
    src = re.sub(r"uniform\s+(\w+)\s+(\w+(?:\[\d+\])?)\s*(?::[^=;]*)?(?:=[^;]*)?;", uni, src)
    src = src.replace("void fragment()", "void main()")
    src = re.sub(r"\bSCREEN_UV\b", "v_uv", src)
    src = re.sub(r"\bSCREEN_PIXEL_SIZE\b", "u_px", src)
    src = re.sub(r"\bUV\b", "v_uv", src)
    src = re.sub(r"\bTIME\b", "u_time", src)
    src = re.sub(r"\bCOLOR\.a\b", "1.0", src)
    src = re.sub(r"\bCOLOR\s*=", "fragColor =", src)
    return src


def main():
    tpl = (ROOT / "tools/tweaker_template.html").read_text()
    defaults = json.loads((ROOT / "ghost_settings.json").read_text())
    ghost = to_glsl((ROOT / "shaders/ghost.gdshader").read_text())
    screen = to_glsl((ROOT / "shaders/spooky_screen.gdshader").read_text())
    out = (tpl.replace("/*DEFAULTS*/", json.dumps(defaults))
              .replace("/*GHOST_FRAG*/", json.dumps(ghost))
              .replace("/*SCREEN_FRAG*/", json.dumps(screen)))
    (ROOT / "tools/ghost_tweaker.html").write_text(out)
    print("wrote tools/ghost_tweaker.html")


if __name__ == "__main__":
    main()
