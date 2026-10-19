#!/usr/bin/env python3
"""The declared sound palette: one entry per sound, tuned by ear.

Every sound is a single struck note (or one chord in error's case). Motion comes
from a pitch glide within that single note, not from a note sequence, because
note sequences read as little tunes rather than interface feedback. Opposing
actions mirror each other through glide direction (open rises, close falls).
This is the file to edit when a sound does not feel right; the engine itself
should not need to change.

Attacks are bimodal, matched to the reference pack: quick interaction sounds
(hover, click, tick, error, and the token taps) onset in a few milliseconds,
while deliberate sounds (confirm, cancel, success, open/close, leave_game)
swell over 60-115 ms. There is no global attack floor - a single minimum was
the original mistake, since it made every quick sound feel sluggish.

The palette is uniformly dark with minimal noise, taking its character from the
error sound. Brightness is no longer varied per sound; pitch and duration carry
the distinction between sounds. `max_high_band_db` is set per-sound and checked
against both a ceiling and a floor at render time.

`tone_ms`, `noise_delay_ms`, `noise_attack_ms` and `noise_decay_ms` let a
sound's noise bed sit on its own timeline rather than always starting with
the tone and outlasting it. This is what lets a splash be two events in
sequence - a tonal impact, then a gap, then a spattering noise bed that
diminishes as it falls - instead of one envelope covering both. Leaving all
four at zero reproduces the original single-envelope behaviour exactly: a
full-length tone with the noise bed starting at sample zero and decaying at
`decay_tau_ms * 2.0`.

The last four fields are playback, not synthesis: how loud the game plays the
file, how far its pitch may wander, how soon it may repeat, and which sound
wins when one gesture asks for several. They never change a rendered file.
`generate_sfx.py --install` (or `--manifest` alone) writes them into
assets/audio/sfx_manifest.json, which AudioManager loads, so this file is the
one place that says how anything sounds in game.

Two kinds of sound are not synthesized. A RecordedShot (SHOTS, the authoring
tools' sounds) cuts a few takes from CC0 recordings (ORIGINALS), installed one
file each and played at random (sfx_recording.process_shot). A RecordedLoop (RECORDINGS) names an
original recording and the processing that turns it into a seamless loop
(sfx_recording.process_loop), for an ambience no struck note can be, such as
the persistent fire's roar. `--install` processes the original when it is
present (it is kept out of git; the URL says where it came from) and otherwise
keeps the committed file. The manifest marks a loop, its file imports looping,
and the node that owns its source plays it (FireSound), never
AudioManager.play(); its `volume_db` is still the one place its level is set.
"""

from dataclasses import dataclass

# C major pentatonic. No other note letters are permitted in the palette.
PENTATONIC = frozenset({"C", "D", "E", "G", "A"})

# Coalescing tiers. When one gesture asks for several sounds on a bus in the
# same frame (a click that confirms a dialog and closes it), only the highest
# tier plays, so the gesture is heard once. An outcome outranks the panel that
# closes with it, which outranks the click that caused both.
PRIORITY_FAINT = 10  # ticks and hovers
PRIORITY_TAP = 20  # clicks and token taps
PRIORITY_EVENT = 30  # something changed state: a panel, a transition, a splash
PRIORITY_OUTCOME = 40  # confirm, cancel, success, leave_game
PRIORITY_ALERT = 50  # error
PRIORITIES = frozenset(
    {PRIORITY_FAINT, PRIORITY_TAP, PRIORITY_EVENT, PRIORITY_OUTCOME, PRIORITY_ALERT}
)

# Default harmonic stack: fundamental plus two steeply attenuated partials.
WARM_HARMONICS = (1.0, 0.3, 0.08)

# Rounder still, for the low token sounds.
ROUND_HARMONICS = (1.0, 0.18, 0.04)


@dataclass(frozen=True)
class SoundSpec:
    """Parameters for one sound. Rendered by sfx_render.render_spec."""

    bus: str
    notes: tuple = ()
    chord: bool = False
    attack_ms: float = 20.0
    note_ms: float = 150.0
    tone_ms: float = 0.0  # tone length; 0 means the full note_ms
    gap_ms: float = 0.0
    decay_tau_ms: float = 60.0
    release_ms: float = 8.0
    harmonics: tuple = WARM_HARMONICS
    noise_mix: float = 0.0
    noise_cutoff_hz: float = 2000.0
    noise_delay_ms: float = 0.0  # when the noise bed starts
    noise_attack_ms: float = 0.0  # noise bed's own attack; 0 means reuse the tone's
    noise_decay_ms: float = 0.0  # noise bed's own decay; 0 means decay_tau_ms * 2
    sweep_semitones: float = 0.0
    lp_cutoff_hz: float = 4000.0
    max_high_band_db: float = -20.0
    # Playback (manifest only; see the module docstring).
    volume_db: float = 0.0  # player gain on top of the rendered peak
    pitch_jitter: float = 0.5  # random pitch offset per play, +/- semitones
    cooldown_s: float = 0.0  # minimum seconds between two plays of this sound
    priority: int = PRIORITY_TAP  # coalescing tier, see PRIORITIES

    @property
    def total_ms(self) -> float:
        """Rendered length in milliseconds."""
        if self.chord or not self.notes:
            return self.note_ms
        return len(self.notes) * (self.note_ms + self.gap_ms)


@dataclass(frozen=True)
class RecordedLoop:
    """A seamless loop processed from an original recording (see the module docstring)."""

    bus: str
    # The original, relative to the repository root, and where it came from.
    source: str
    title: str
    author: str
    url: str
    licence: str
    # The loop's range in the original; the last crossfade_ms fade into the head.
    start_s: float
    end_s: float
    crossfade_ms: float
    # Filters: the rumble under highpass_hz, a mains hum (0: none), and the
    # low-pass before the rate is halved down to sample_rate.
    highpass_hz: float
    hum_hz: float
    lowpass_hz: float
    sample_rate: int
    max_high_band_db: float
    # Playback (manifest only), as for SoundSpec.
    volume_db: float = 0.0
    pitch_jitter: float = 0.5
    cooldown_s: float = 0.0
    priority: int = PRIORITY_FAINT

    @property
    def total_ms(self) -> float:
        """The loop's length in milliseconds (the file adds one guard sample)."""
        return (self.end_s - self.start_s) * 1000.0 - self.crossfade_ms


RECORDINGS = {
    "fire_roar": RecordedLoop(
        bus="sfx",
        source="docs/plans/2026-10-11-fire-features/cc0_fire_large/"
        "483318__craigsmith__r27-25-large-fire-burning.wav",
        title="R27-25-Large Fire Burning.wav",
        author="craigsmith",
        url="https://freesound.org/people/craigsmith/sounds/483318/",
        licence="CC0 1.0",
        # 1.75 s of quieter lead-in and a fade-out after 59.4 s are cut.
        start_s=2.0, end_s=59.3, crossfade_ms=400.0,
        highpass_hz=70.0, hum_hz=49.8, lowpass_hz=10000.0, sample_rate=24000,
        max_high_band_db=-20.0,
        # An ambience under the token sounds: the level by ear is set here only.
        # At -9 dB (card F7c, the user: "lower the fire sound volume a tad"; F7b
        # had -6) one player's RMS is -31.6 dBFS (the loop's -22.6 under it),
        # about 23 dB under token_drop's loudest 50 ms (-8.9 dBFS), 20 dB with
        # both players at full. Each of FireSound's two players starts at its
        # own pitch within the jitter, so the pair never phases.
        volume_db=-9.0, pitch_jitter=0.5, priority=PRIORITY_FAINT,
    ),
}


@dataclass(frozen=True)
class Original:
    """A CC0 recording that recorded one-shots cut their takes from.

    `source` is relative to the repository root and kept out of git, as the
    roar's is: Freesound's HQ preview (an original needs a login), decoded to
    44.1 kHz 16-bit mono WAV beside the downloaded MP3.
    """

    source: str
    title: str
    author: str
    url: str
    licence: str = "CC0 1.0"


@dataclass(frozen=True)
class Take:
    """One variant of a RecordedShot: a range of an Original (ORIGINALS key).

    Every take is peak-normalized, so a take whose peak stands far above its
    body plays quieter than its siblings; `gain_db` lifts it to the loudest
    take's loudest 50 ms (measured, then set by hand like volume_db), so the
    variants differ by their jitter, not by which take came up.
    """

    original: str
    start_s: float
    end_s: float
    gain_db: float = 0.0


@dataclass(frozen=True)
class RecordedShot:
    """A one-shot with a few takes cut from recordings (sfx_recording.process_shot).

    Each take is band-limited and halved to `sample_rate`, high-passed, trimmed,
    faded in over `fade_in_ms` and out over its last `fade_out_ms`, and
    peak-normalized, then installed as `<name>.wav`, `<name>.v1.wav`, ... The
    manifest lists them as the entry's `takes`, and AudioManager plays a random
    one each time (never the same twice running), with the pitch jitter and a
    gain jitter of `gain_jitter_db` either way. `pitch_scale` is a base pitch
    under the jitter, for a family's lower or higher sibling (undo and redo).
    """

    bus: str
    takes: tuple
    highpass_hz: float
    lowpass_hz: float
    fade_in_ms: float
    fade_out_ms: float
    max_high_band_db: float
    sample_rate: int = 22050
    # Playback (manifest only), as for SoundSpec.
    volume_db: float = 0.0
    pitch_jitter: float = 0.5
    gain_jitter_db: float = 1.5
    pitch_scale: float = 1.0
    cooldown_s: float = 0.0
    priority: int = PRIORITY_FAINT

    @property
    def total_ms(self) -> float:
        """The mean take's length in milliseconds."""
        lengths = [take.end_s - take.start_s for take in self.takes]
        return 1000.0 * sum(lengths) / len(lengths)


def _freesound(sound_id: int, author: str, title: str) -> Original:
    return Original(
        source="docs/plans/2026-10-19-brushland/sound/originals/%d/%d.wav" % (sound_id, sound_id),
        title=title,
        author=author,
        url="https://freesound.org/people/%s/sounds/%d/" % (author, sound_id),
    )


# Every recording the authoring sounds cut from; each page confirmed CC0 on
# 2026-10-19 (its licence link the CC0 1.0 deed, no other licence named).
ORIGINALS = {
    "foliage_1": _freesound(190641, "GUS_MAN", "Rustling foilage 1.wav"),
    "foliage_3": _freesound(190639, "GUS_MAN", "Rustling foilage 3.wav"),
    "balsa_1": _freesound(186401, "LloydEvans09", "Balsa hit 1.wav"),
    "balsa_2": _freesound(186400, "LloydEvans09", "Balsa hit 2.wav"),
    "balsa_4": _freesound(186398, "LloydEvans09", "Balsa hit 4"),
    "balsa_5": _freesound(186405, "LloydEvans09", "Balsa hit 5.wav"),
    "splash_small": _freesound(737233, "qubodup", "Small Water Splash"),
    "splash": _freesound(737234, "qubodup", "Water Splash"),
    "grapes": _freesound(
        538143, "asherkaye2", "Quick Splash (dropping grapes into a glass of water)"
    ),
    "splash_shots": _freesound(50623, "vibe_crc", "water_splash_10shots.wav"),
    "paint_strokes": _freesound(86113, "acrober", "normal paint strokes_1-2.aif"),
    "paint_slow": _freesound(86114, "acrober", "slowpaintstrokes_1-2.aif"),
    "wet_sand": _freesound(651294, "f3bbbo", "Digging in wet course sand (raw file)"),
    "wet_sand_2": _freesound(651293, "f3bbbo", "Digging in wet course sand (2)"),
    "trowel": _freesound(
        696531, "dhallcomposer", "Digging Into Soft Soil with Small Trowell.wav"
    ),
}


def _takes(*ranges) -> tuple:
    return tuple(Take(*fields) for fields in ranges)


# How far under token_drop's loudest 50 ms (-8.8 dBFS) each moment's takes play,
# in dB: gentle enough for a long session (the roar's one player sits about 23 dB
# under it in RMS). tools/tests/test_sfx_spec.py measures the installed takes.
UNDER_TOKEN_DROP_DB = {"start": 14.0, "settle": 16.0, "tick": 20.0, "undo": 15.0, "redo": 15.0}

# The authoring tools' sounds (StrokeSound): per family a stroke's start, a quiet
# tick per stretch of drag, and the release's settle, plus undo and redo. Each
# volume_db puts the loudest take's loudest 50 ms at its UNDER_TOKEN_DROP_DB, and
# each take's gain_db lifts it to that take (measured 2026-10-19; a take that
# needed more than 6 dB was dropped as unlike its siblings).
SHOTS = {
    "plant_start": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("foliage_3", 0.06, 0.55, 1.6), ("foliage_1", 0.89, 1.4),
            ("foliage_1", 1.45, 1.95, 1.5),
        ),
        highpass_hz=120.0, lowpass_hz=9000.0, fade_in_ms=4.0, fade_out_ms=150.0,
        max_high_band_db=-14.0, volume_db=-9.5, priority=PRIORITY_TAP,
    ),
    "plant_tick": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("foliage_1", 0.02, 0.22), ("foliage_1", 0.38, 0.58, 1.5),
            ("foliage_1", 1.69, 1.89, 0.7), ("foliage_3", 0.72, 0.92, 1.4),
        ),
        highpass_hz=150.0, lowpass_hz=9000.0, fade_in_ms=3.0, fade_out_ms=80.0,
        max_high_band_db=-14.0, volume_db=-14.6, pitch_jitter=0.8, gain_jitter_db=2.0,
        cooldown_s=0.12,
    ),
    "plant_settle": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("foliage_1", 1.45, 2.4, 0.6), ("foliage_3", 0.06, 1.1),
            ("foliage_1", 0.38, 1.2, 0.1),
        ),
        highpass_hz=120.0, lowpass_hz=7000.0, fade_in_ms=20.0, fade_out_ms=450.0,
        max_high_band_db=-14.0, volume_db=-9.6, priority=PRIORITY_TAP,
    ),
    "prop_start": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("balsa_1", 0.0, 0.42, 2.1), ("balsa_2", 0.0, 0.29), ("balsa_5", 0.0, 0.46, 4.6),
        ),
        highpass_hz=90.0, lowpass_hz=6000.0, fade_in_ms=1.0, fade_out_ms=80.0,
        max_high_band_db=-13.0, volume_db=-7.7, pitch_scale=0.84, priority=PRIORITY_TAP,
    ),
    "prop_tick": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("balsa_4", 0.0, 0.15, 5.3), ("balsa_2", 0.0, 0.15), ("balsa_1", 0.0, 0.15, 2.1),
        ),
        highpass_hz=120.0, lowpass_hz=6000.0, fade_in_ms=1.0, fade_out_ms=60.0,
        max_high_band_db=-13.0, volume_db=-13.7, pitch_jitter=0.8, gain_jitter_db=2.0,
        cooldown_s=0.12,
    ),
    "prop_settle": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("balsa_4", 0.0, 0.26, 2.9), ("balsa_5", 0.0, 0.46, 2.6), ("balsa_1", 0.0, 0.42),
        ),
        highpass_hz=80.0, lowpass_hz=4500.0, fade_in_ms=1.0, fade_out_ms=120.0,
        max_high_band_db=-15.0, volume_db=-7.4, pitch_scale=0.71, priority=PRIORITY_TAP,
    ),
    "water_start": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("splash_small", 0.02, 0.55, 0.9), ("splash", 0.0, 0.5),
            ("splash_shots", 5.45, 5.95, 0.4),
        ),
        highpass_hz=120.0, lowpass_hz=8000.0, fade_in_ms=3.0, fade_out_ms=150.0,
        max_high_band_db=-10.0, volume_db=-7.9, priority=PRIORITY_TAP,
    ),
    "water_tick": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("grapes", 1.47, 1.68), ("grapes", 1.69, 1.88, 1.9),
            ("splash_shots", 7.26, 7.47, 1.3),
        ),
        highpass_hz=150.0, lowpass_hz=8000.0, fade_in_ms=2.0, fade_out_ms=70.0,
        max_high_band_db=-24.0, volume_db=-13.5, pitch_jitter=0.8, gain_jitter_db=2.0,
        cooldown_s=0.12,
    ),
    "water_settle": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("splash_shots", 8.73, 9.4, 1.7), ("splash_shots", 14.02, 14.7, 0.4),
            ("splash_shots", 10.04, 10.7),
        ),
        highpass_hz=120.0, lowpass_hz=7000.0, fade_in_ms=10.0, fade_out_ms=350.0,
        max_high_band_db=-25.0, volume_db=-9.5, pitch_scale=0.89, priority=PRIORITY_TAP,
    ),
    "paint_start": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("paint_strokes", 0.47, 0.95), ("paint_strokes", 0.91, 1.4, 4.2),
            ("paint_strokes", 0.0, 0.47, 3.2),
        ),
        highpass_hz=150.0, lowpass_hz=8000.0, fade_in_ms=10.0, fade_out_ms=150.0,
        max_high_band_db=-12.0, volume_db=-9.3, priority=PRIORITY_TAP,
    ),
    "paint_tick": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("paint_slow", 1.56, 1.8, 2.4), ("paint_slow", 3.4, 3.62, 0.2),
            ("paint_slow", 2.7, 2.92, 0.8), ("paint_slow", 0.33, 0.55),
        ),
        highpass_hz=150.0, lowpass_hz=8000.0, fade_in_ms=8.0, fade_out_ms=90.0,
        max_high_band_db=-12.0, volume_db=-17.0, pitch_jitter=0.8, gain_jitter_db=2.0,
        cooldown_s=0.12,
    ),
    "paint_settle": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("paint_slow", 2.24, 2.95, 5.4), ("paint_slow", 0.32, 1.1, 1.1),
            ("paint_slow", 2.69, 3.35),
        ),
        highpass_hz=150.0, lowpass_hz=7000.0, fade_in_ms=20.0, fade_out_ms=350.0,
        max_high_band_db=-17.0, volume_db=-12.2, priority=PRIORITY_TAP,
    ),
    "sculpt_start": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("wet_sand", 0.9, 1.35, 1.1), ("wet_sand", 1.67, 2.15, 1.2),
            ("wet_sand", 7.76, 8.25),
        ),
        highpass_hz=50.0, lowpass_hz=3500.0, fade_in_ms=6.0, fade_out_ms=150.0,
        max_high_band_db=-17.0, volume_db=-9.9, pitch_scale=0.79, priority=PRIORITY_TAP,
    ),
    "sculpt_tick": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("trowel", 0.19, 0.45, 0.2), ("trowel", 1.25, 1.52, 1.4),
            ("trowel", 2.29, 2.56, 3.9), ("trowel", 3.23, 3.48),
        ),
        highpass_hz=50.0, lowpass_hz=3500.0, fade_in_ms=4.0, fade_out_ms=90.0,
        max_high_band_db=-26.0, volume_db=-15.9, pitch_scale=0.84, pitch_jitter=0.8,
        gain_jitter_db=2.0, cooldown_s=0.12,
    ),
    "sculpt_settle": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("wet_sand", 5.3, 6.0, 1.4), ("wet_sand", 6.59, 7.2),
            ("wet_sand", 9.53, 10.15, 1.3), ("wet_sand_2", 0.0, 0.72, 1.2),
        ),
        highpass_hz=40.0, lowpass_hz=3000.0, fade_in_ms=15.0, fade_out_ms=350.0,
        max_high_band_db=-19.0, volume_db=-12.1, pitch_scale=0.71, priority=PRIORITY_TAP,
    ),
    # Undo steps down and redo up (base pitch two semitones either side), the
    # balsa knock shortened to a tick.
    "undo": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("balsa_4", 0.0, 0.16, 4.8), ("balsa_5", 0.0, 0.16, 4.9), ("balsa_2", 0.0, 0.16),
        ),
        highpass_hz=120.0, lowpass_hz=5000.0, fade_in_ms=1.0, fade_out_ms=70.0,
        max_high_band_db=-13.0, volume_db=-8.4, pitch_scale=0.89, pitch_jitter=0.3,
        gain_jitter_db=1.0, cooldown_s=0.05, priority=PRIORITY_TAP,
    ),
    "redo": RecordedShot(
        bus="sfx",
        takes=_takes(
            ("balsa_4", 0.0, 0.16, 4.8), ("balsa_5", 0.0, 0.16, 4.9), ("balsa_2", 0.0, 0.16),
        ),
        highpass_hz=120.0, lowpass_hz=5000.0, fade_in_ms=1.0, fade_out_ms=70.0,
        max_high_band_db=-13.0, volume_db=-8.4, pitch_scale=1.12, pitch_jitter=0.3,
        gain_jitter_db=1.0, cooldown_s=0.05, priority=PRIORITY_TAP,
    ),
}


SPECS = {
    "cancel": SoundSpec(
        bus="ui", notes=("D4",),
        attack_ms=58.0, note_ms=168.0, decay_tau_ms=53.8, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-4.0, lp_cutoff_hz=2000.0, max_high_band_db=-48.1,
        priority=PRIORITY_OUTCOME,
    ),
    "click": SoundSpec(
        bus="ui", notes=("E4",),
        attack_ms=2.0, note_ms=58.0, decay_tau_ms=18.6, release_ms=3.5,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-45.0,
        priority=PRIORITY_TAP,
    ),
    "close": SoundSpec(
        bus="ui", notes=("G4",),
        attack_ms=60.0, note_ms=175.0, decay_tau_ms=56.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-5.0, lp_cutoff_hz=2000.0, max_high_band_db=-44.2,
        priority=PRIORITY_EVENT,
    ),
    "confirm": SoundSpec(
        bus="ui", notes=("E4",),
        attack_ms=90.0, note_ms=190.0, decay_tau_ms=60.8, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=4.0, lp_cutoff_hz=2000.0, max_high_band_db=-43.5,
        priority=PRIORITY_OUTCOME,
    ),
    "error": SoundSpec(
        bus="ui", notes=("C4", "D4", "E4"),
        chord=True,
        attack_ms=27.0, note_ms=300.0, decay_tau_ms=108.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2400.0, max_high_band_db=-44.4,
        priority=PRIORITY_ALERT,
    ),
    "hover": SoundSpec(
        bus="ui", notes=("E5",),
        attack_ms=2.0, note_ms=38.0, decay_tau_ms=12.2, release_ms=2.3,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-34.1,
        volume_db=-6.0, priority=PRIORITY_FAINT,
    ),
    "leave_game": SoundSpec(
        bus="ui", notes=("C4",),
        attack_ms=100.0, note_ms=460.0, decay_tau_ms=147.2, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-7.0, lp_cutoff_hz=2000.0, max_high_band_db=-49.8,
        pitch_jitter=0.0, priority=PRIORITY_OUTCOME,
    ),
    "open": SoundSpec(
        bus="ui", notes=("C4",),
        attack_ms=60.0, note_ms=175.0, decay_tau_ms=56.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=5.0, lp_cutoff_hz=2000.0, max_high_band_db=-46.9,
        priority=PRIORITY_EVENT,
    ),
    "splash_enter": SoundSpec(
        bus="sfx", notes=("C3",),
        attack_ms=6.0, note_ms=610.0, tone_ms=95.0,
        decay_tau_ms=22.0, release_ms=6.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.660, noise_cutoff_hz=5200.0,
        noise_delay_ms=350.0, noise_attack_ms=35.0, noise_decay_ms=130.0,
        sweep_semitones=22.0, lp_cutoff_hz=2800.0, max_high_band_db=-20.5,
        priority=PRIORITY_EVENT,
    ),
    "splash_exit": SoundSpec(
        bus="sfx", notes=("G4",),
        attack_ms=5.0, note_ms=610.0, tone_ms=95.0,
        decay_tau_ms=22.0, release_ms=6.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.660, noise_cutoff_hz=5200.0,
        noise_delay_ms=350.0, noise_attack_ms=35.0, noise_decay_ms=130.0,
        sweep_semitones=-22.0, lp_cutoff_hz=2800.0, max_high_band_db=-20.3,
        volume_db=-3.0, priority=PRIORITY_EVENT,
    ),
    "success": SoundSpec(
        bus="ui", notes=("C4", "E4", "A4"),
        chord=True,
        attack_ms=14.0, note_ms=300.0, decay_tau_ms=110.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2400.0, max_high_band_db=-42.6,
        priority=PRIORITY_OUTCOME,
    ),
    "tick": SoundSpec(
        bus="ui", notes=("A4",),
        attack_ms=3.0, note_ms=45.0, decay_tau_ms=14.4, release_ms=2.7,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-40.5,
        # Half a semitone each way at most, so a tick stays near A4 and does not
        # clash with the pentatonic notes around it. The cooldown was the
        # settings sliders' own throttle; it now holds for every tick.
        volume_db=-8.0, pitch_jitter=0.5, cooldown_s=0.08, priority=PRIORITY_FAINT,
    ),
    "token_drop": SoundSpec(
        bus="sfx", notes=("A2",),
        attack_ms=8.0, note_ms=190.0, decay_tau_ms=60.8, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-2.0, lp_cutoff_hz=1800.0, max_high_band_db=-54.3,
        # The caller adds a height-driven gain and base pitch per drop.
        pitch_jitter=0.7, priority=PRIORITY_TAP,
    ),
    "token_hover": SoundSpec(
        bus="sfx", notes=("E5",),
        attack_ms=2.0, note_ms=38.0, decay_tau_ms=12.2, release_ms=2.3,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-34.1,
        # Sweeping the mouse across a row of tokens chirps once, not once per token
        # (six in a sweep stacked +7 LU before the cooldown).
        volume_db=-6.0, cooldown_s=0.15, priority=PRIORITY_FAINT,
    ),
    "token_pickup": SoundSpec(
        bus="sfx", notes=("E3",),
        attack_ms=5.0, note_ms=150.0, decay_tau_ms=48.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=2.0, lp_cutoff_hz=2000.0, max_high_band_db=-52.2,
        priority=PRIORITY_TAP,
    ),
    "token_slide": SoundSpec(
        bus="sfx", notes=("A2",),
        attack_ms=30.0, note_ms=320.0, decay_tau_ms=102.4, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=1800.0, max_high_band_db=-54.5,
        volume_db=-3.0, priority=PRIORITY_FAINT,
    ),
    "token_whoosh": SoundSpec(
        bus="sfx", notes=("E4",),
        attack_ms=45.0, note_ms=340.0, decay_tau_ms=110.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.450, noise_cutoff_hz=2800.0,
        sweep_semitones=-9.0, lp_cutoff_hz=2000.0, max_high_band_db=-28.2,
        # The caller sets a speed-driven base pitch; off by default
        # (AudioManager.TOKEN_WHOOSH_SOUND_ENABLED).
        volume_db=-3.0, pitch_jitter=1.3, priority=PRIORITY_FAINT,
    ),
    "transition": SoundSpec(
        bus="ui", notes=("G4",),
        attack_ms=55.0, note_ms=260.0, decay_tau_ms=80.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.420, noise_cutoff_hz=2800.0,
        sweep_semitones=-12.0, lp_cutoff_hz=2000.0, max_high_band_db=-29.4,
        volume_db=-3.0, pitch_jitter=0.0, priority=PRIORITY_EVENT,
    ),
}
