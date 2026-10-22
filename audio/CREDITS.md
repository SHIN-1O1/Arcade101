# Audio credits

Every file under `audio/` was generated from scratch by `tools/gen_audio.py` (sine, triangle and
square oscillators plus filtered noise, encoded to Ogg Vorbis with ffmpeg). No third-party samples,
recordings or packs are used.

| Files | Source | Licence |
|---|---|---|
| `audio/sfx/*.ogg` (14 effects) | `tools/gen_audio.py`, original | CC0 1.0 (public domain) |
| `audio/music/menu.ogg`, `audio/music/game.ogg` | `tools/gen_audio.py`, original | CC0 1.0 (public domain) |

Regenerate with `python tools/gen_audio.py` (needs numpy and ffmpeg with libvorbis).
