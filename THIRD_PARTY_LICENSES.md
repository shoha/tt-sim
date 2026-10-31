# Third-party licences

## Tabler Icons (assets/icons/ui/)

Icons in `assets/icons/ui/` are from Tabler Icons (https://tabler.io/icons),
normalised for engine tinting (colour literals only; no shape changes).

MIT License

Copyright (c) 2020-2026 Paweł Kuna

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Sky HDRIs (assets/skies/)

The panoramas in `assets/skies/` are ambientCG HDRIs released under the Creative
Commons CC0 1.0 Universal Public Domain Dedication
(https://creativecommons.org/publicdomain/zero/1.0/). They were downscaled to 1024x512
and exposure-normalised by `tools/curate_skies.gd`; no attribution is required, and the
sources are listed for provenance.

| File | Source | Site | URL |
|---|---|---|---|
| `assets/skies/clear_day.exr` | Day Sky HDRI 055 A | ambientCG | https://ambientcg.com/a/DaySkyHDRI055A |
| `assets/skies/cloudy.exr` | Day Sky HDRI 067 B | ambientCG | https://ambientcg.com/a/DaySkyHDRI067B |
| `assets/skies/overcast.exr` | Day Sky HDRI 021 A | ambientCG | https://ambientcg.com/a/DaySkyHDRI021A |
| `assets/skies/morning.exr` | Morning Sky HDRI 009 B | ambientCG | https://ambientcg.com/a/MorningSkyHDRI009B |
| `assets/skies/sunset.exr` | Evening Sky HDRI 032 A | ambientCG | https://ambientcg.com/a/EveningSkyHDRI032A |
| `assets/skies/dusk.exr` | Evening Sky HDRI 022 B | ambientCG | https://ambientcg.com/a/EveningSkyHDRI022B |
| `assets/skies/storm.exr` | Day Sky HDRI 061 A | ambientCG | https://ambientcg.com/a/DaySkyHDRI061A |

## Sound recordings (assets/audio/)

Every other sound in `assets/audio/` is synthesized by `tools/generate_sfx.py`. The recordings
below are released under the Creative Commons CC0 1.0 Universal Public Domain Dedication
(https://creativecommons.org/publicdomain/zero/1.0/); no attribution is required, and the
sources are listed for provenance. The processing is declared in `tools/sfx_spec.py`
(`RECORDINGS`, and `ORIGINALS` and `SHOTS` for the authoring sounds) and done by
`tools/sfx_recording.py`.

| File | Title | Author | URL | Licence | Processing |
|---|---|---|---|---|---|
| `assets/audio/sfx/fire_roar.wav` | R27-25-Large Fire Burning.wav (pack "Vintage Fire (Red Lib)") | craigsmith | https://freesound.org/people/craigsmith/sounds/483318/ | CC0 1.0 | 48 kHz 24-bit mono original: low-pass 10 kHz and halved to 24 kHz, high-pass 70 Hz, 49.8 Hz hum notched, trimmed to 2.0-59.3 s, the last 400 ms crossfaded into the head (equal power) as a seamless loop, peak-normalized to -3 dBFS, 16-bit |

The authoring tools' sounds (`plant_*`, `prop_*`, `water_*`, `paint_*`, `sculpt_*`, `undo`,
`redo`, each with takes `<name>.wav`, `<name>.v1.wav`, ...) are cut from the recordings below,
each from Freesound's HQ MP3 preview decoded to 44.1 kHz mono (licence confirmed on each page on
2026-10-19). Each take is low-passed and halved to 22.05 kHz, high-passed, trimmed to its range
in `SHOTS`, faded in and out (raised cosine) and peak-normalized to -3 dBFS, 16-bit.

| Used in | Title | Author | URL | Licence |
|---|---|---|---|---|
| `plant_*` | Rustling foilage 1.wav | GUS_MAN | https://freesound.org/people/GUS_MAN/sounds/190641/ | CC0 1.0 |
| `plant_*` | Rustling foilage 3.wav | GUS_MAN | https://freesound.org/people/GUS_MAN/sounds/190639/ | CC0 1.0 |
| `prop_*`, `undo`, `redo` | Balsa hit 1.wav, 2.wav, 4, 5.wav | LloydEvans09 | https://freesound.org/people/LloydEvans09/sounds/186401/, .../186400/, .../186398/, .../186405/ | CC0 1.0 |
| `water_start` | Small Water Splash; Water Splash | qubodup | https://freesound.org/people/qubodup/sounds/737233/, .../737234/ | CC0 1.0 |
| `water_tick` | Quick Splash (dropping grapes into a glass of water) | asherkaye2 | https://freesound.org/people/asherkaye2/sounds/538143/ | CC0 1.0 |
| `water_*` | water_splash_10shots.wav | vibe_crc | https://freesound.org/people/vibe_crc/sounds/50623/ | CC0 1.0 |
| `paint_*` | normal paint strokes_1-2.aif; slowpaintstrokes_1-2.aif | acrober | https://freesound.org/people/acrober/sounds/86113/, .../86114/ | CC0 1.0 |
| `sculpt_start`, `sculpt_settle` | Digging in wet course sand (raw file); (2) | f3bbbo | https://freesound.org/people/f3bbbo/sounds/651294/, .../651293/ | CC0 1.0 |
| `sculpt_tick` | Digging Into Soft Soil with Small Trowell.wav | dhallcomposer | https://freesound.org/people/dhallcomposer/sounds/696531/ | CC0 1.0 |

## Fonts (assets/fonts/)

| File | Font | Licence |
|---|---|---|
| `assets/fonts/fraunces/Fraunces-Variable.ttf`, `Fraunces-Italic-Variable.ttf` | Fraunces, Copyright 2018 The Fraunces Project Authors (https://github.com/undercasetype/Fraunces) | SIL Open Font License 1.1, `assets/fonts/fraunces/OFL.txt` |
| `assets/fonts/Inter-VariableFont_opsz,wght.ttf` | Inter, The Inter Project Authors (https://github.com/rsms/inter) | SIL Open Font License 1.1 (the licence text file is not in the repository yet, see the release checklist) |

## Vendored addons

Each addon under `addons/` carries its own licence file:

| Addon | Licence file |
|---|---|
| GUT | `addons/gut/LICENSE.md` |
| Icon Explorer | `addons/icon_explorer/LICENSE.md` |
| theme_gen | `addons/theme_gen/LICENSE.md` |
| theme_gen_save_sync | `addons/theme_gen_save_sync/LICENSE.md` |
| DragAndDrop3D | see `addons/DragAndDrop3D/` |
| brackeys_particle_controls | see `addons/brackeys_particle_controls/` |
| GodotSteam | see `addons/godotsteam/` |

## Native scatter library (native/)

The native scatter generator (`native/`, built into the game where its library is present)
carries these third-party sources:

| Source | Origin | Licence |
|---|---|---|
| `native/thirdparty/FastNoiseLite.h` | FastNoiseLite by Jordan Peck and contributors, as vendored in Godot 4.7.2-stable (`thirdparty/misc/FastNoiseLite.h`, https://github.com/godotengine/godot), unmodified | MIT, header of the file |
| `native/godot-cpp/` (submodule) | godot-cpp 10.0.0-stable, https://github.com/godotengine/godot-cpp | MIT, `native/godot-cpp/LICENSE.md` |
