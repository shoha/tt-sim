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
"""

from dataclasses import dataclass

# C major pentatonic. No other note letters are permitted in the palette.
PENTATONIC = frozenset({"C", "D", "E", "G", "A"})

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

    @property
    def total_ms(self) -> float:
        """Rendered length in milliseconds."""
        if self.chord or not self.notes:
            return self.note_ms
        return len(self.notes) * (self.note_ms + self.gap_ms)


SPECS = {
    "cancel": SoundSpec(
        bus="ui", notes=("D4",),
        attack_ms=58.0, note_ms=168.0, decay_tau_ms=53.8, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-4.0, lp_cutoff_hz=2000.0, max_high_band_db=-48.1,
    ),
    "click": SoundSpec(
        bus="ui", notes=("E4",),
        attack_ms=2.0, note_ms=58.0, decay_tau_ms=18.6, release_ms=3.5,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-45.0,
    ),
    "close": SoundSpec(
        bus="ui", notes=("G4",),
        attack_ms=60.0, note_ms=175.0, decay_tau_ms=56.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-5.0, lp_cutoff_hz=2000.0, max_high_band_db=-44.2,
    ),
    "confirm": SoundSpec(
        bus="ui", notes=("E4",),
        attack_ms=90.0, note_ms=190.0, decay_tau_ms=60.8, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=4.0, lp_cutoff_hz=2000.0, max_high_band_db=-43.5,
    ),
    "error": SoundSpec(
        bus="ui", notes=("C4", "D4", "E4"),
        chord=True,
        attack_ms=27.0, note_ms=300.0, decay_tau_ms=108.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2400.0, max_high_band_db=-44.4,
    ),
    "hover": SoundSpec(
        bus="ui", notes=("E5",),
        attack_ms=2.0, note_ms=38.0, decay_tau_ms=12.2, release_ms=2.3,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-34.1,
    ),
    "leave_game": SoundSpec(
        bus="ui", notes=("C4",),
        attack_ms=100.0, note_ms=460.0, decay_tau_ms=147.2, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-7.0, lp_cutoff_hz=2000.0, max_high_band_db=-49.8,
    ),
    "open": SoundSpec(
        bus="ui", notes=("C4",),
        attack_ms=60.0, note_ms=175.0, decay_tau_ms=56.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=5.0, lp_cutoff_hz=2000.0, max_high_band_db=-46.9,
    ),
    "splash_enter": SoundSpec(
        bus="sfx", notes=("C3",),
        attack_ms=6.0, note_ms=610.0, tone_ms=95.0,
        decay_tau_ms=22.0, release_ms=6.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.660, noise_cutoff_hz=5200.0,
        noise_delay_ms=350.0, noise_attack_ms=35.0, noise_decay_ms=130.0,
        sweep_semitones=22.0, lp_cutoff_hz=2800.0, max_high_band_db=-20.5,
    ),
    "splash_exit": SoundSpec(
        bus="sfx", notes=("G4",),
        attack_ms=5.0, note_ms=610.0, tone_ms=95.0,
        decay_tau_ms=22.0, release_ms=6.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.660, noise_cutoff_hz=5200.0,
        noise_delay_ms=350.0, noise_attack_ms=35.0, noise_decay_ms=130.0,
        sweep_semitones=-22.0, lp_cutoff_hz=2800.0, max_high_band_db=-20.3,
    ),
    "success": SoundSpec(
        bus="ui", notes=("C4", "E4", "A4"),
        chord=True,
        attack_ms=14.0, note_ms=300.0, decay_tau_ms=110.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2400.0, max_high_band_db=-42.6,
    ),
    "tick": SoundSpec(
        bus="ui", notes=("A4",),
        attack_ms=3.0, note_ms=45.0, decay_tau_ms=14.4, release_ms=2.7,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-40.5,
    ),
    "token_drop": SoundSpec(
        bus="sfx", notes=("A2",),
        attack_ms=8.0, note_ms=190.0, decay_tau_ms=60.8, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=-2.0, lp_cutoff_hz=1800.0, max_high_band_db=-54.3,
    ),
    "token_hover": SoundSpec(
        bus="sfx", notes=("E5",),
        attack_ms=2.0, note_ms=38.0, decay_tau_ms=12.2, release_ms=2.3,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=2000.0, max_high_band_db=-34.1,
    ),
    "token_pickup": SoundSpec(
        bus="sfx", notes=("E3",),
        attack_ms=5.0, note_ms=150.0, decay_tau_ms=48.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=2.0, lp_cutoff_hz=2000.0, max_high_band_db=-52.2,
    ),
    "token_slide": SoundSpec(
        bus="sfx", notes=("A2",),
        attack_ms=30.0, note_ms=320.0, decay_tau_ms=102.4, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.020, noise_cutoff_hz=12000.0,
        sweep_semitones=0.0, lp_cutoff_hz=1800.0, max_high_band_db=-54.5,
    ),
    "token_whoosh": SoundSpec(
        bus="sfx", notes=("E4",),
        attack_ms=45.0, note_ms=340.0, decay_tau_ms=110.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.450, noise_cutoff_hz=2800.0,
        sweep_semitones=-9.0, lp_cutoff_hz=2000.0, max_high_band_db=-28.2,
    ),
    "transition": SoundSpec(
        bus="ui", notes=("G4",),
        attack_ms=55.0, note_ms=260.0, decay_tau_ms=80.0, release_ms=8.0,
        harmonics=ROUND_HARMONICS, noise_mix=0.420, noise_cutoff_hz=2800.0,
        sweep_semitones=-12.0, lp_cutoff_hz=2000.0, max_high_band_db=-29.4,
    ),
}
