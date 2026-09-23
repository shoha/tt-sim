#!/usr/bin/env python3
"""The declared sound palette: one entry per sound, tuned by ear.

Every sound is drawn from C major pentatonic so overlapping sounds never clash,
and opposing actions mirror each other (open rises, close falls). This is the
file to edit when a sound does not feel right; the engine itself should not
need to change.
"""

from dataclasses import dataclass

# C major pentatonic. No other note letters are permitted in the palette.
PENTATONIC = frozenset({"C", "D", "E", "G", "A"})

# The floor that separates "soft" from "sharp". Sampled UI clicks sit near 1 ms.
MIN_ATTACK_MS = 12.0

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
    gap_ms: float = 0.0
    decay_tau_ms: float = 60.0
    release_ms: float = 8.0
    harmonics: tuple = WARM_HARMONICS
    noise_mix: float = 0.0
    noise_cutoff_hz: float = 2000.0
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
    # --- UI bus -----------------------------------------------------------
    "click": SoundSpec(
        bus="ui", notes=("E4",), attack_ms=20.0, note_ms=150.0, decay_tau_ms=45.0
    ),
    "hover": SoundSpec(
        bus="ui",
        notes=("E5",),
        attack_ms=15.0,
        note_ms=90.0,
        decay_tau_ms=25.0,
        lp_cutoff_hz=5000.0,
    ),
    "tick": SoundSpec(
        bus="ui",
        notes=("A4",),
        attack_ms=12.0,
        note_ms=80.0,
        decay_tau_ms=20.0,
        harmonics=(1.0, 0.15),
    ),
    "open": SoundSpec(
        bus="ui", notes=("C4", "G4"), attack_ms=25.0, note_ms=130.0, decay_tau_ms=55.0
    ),
    "close": SoundSpec(
        bus="ui", notes=("G4", "C4"), attack_ms=25.0, note_ms=130.0, decay_tau_ms=55.0
    ),
    "confirm": SoundSpec(
        bus="ui",
        notes=("C4", "E4", "G4"),
        attack_ms=25.0,
        note_ms=126.667,
        decay_tau_ms=60.0,
    ),
    "cancel": SoundSpec(
        bus="ui", notes=("G4", "D4"), attack_ms=30.0, note_ms=150.0, decay_tau_ms=65.0
    ),
    "success": SoundSpec(
        bus="ui",
        notes=("C4", "E4", "G4", "C5"),
        attack_ms=25.0,
        note_ms=175.0,
        decay_tau_ms=140.0,
    ),
    "error": SoundSpec(
        bus="ui",
        notes=("D3", "E3"),
        chord=True,
        attack_ms=40.0,
        note_ms=550.0,
        decay_tau_ms=160.0,
        harmonics=ROUND_HARMONICS,
        lp_cutoff_hz=2200.0,
    ),
    "transition": SoundSpec(
        bus="ui",
        notes=("G4",),
        attack_ms=60.0,
        note_ms=400.0,
        decay_tau_ms=120.0,
        noise_mix=0.85,
        noise_cutoff_hz=3000.0,
        sweep_semitones=-7.0,
        lp_cutoff_hz=5000.0,
        max_high_band_db=-14.0,
    ),
    "leave_game": SoundSpec(
        bus="ui",
        notes=("C5", "G4", "E4", "C4"),
        attack_ms=30.0,
        note_ms=200.0,
        decay_tau_ms=150.0,
    ),
    # --- SFX bus ----------------------------------------------------------
    "token_pickup": SoundSpec(
        bus="sfx",
        notes=("E3",),
        attack_ms=15.0,
        note_ms=250.0,
        decay_tau_ms=70.0,
        harmonics=ROUND_HARMONICS,
        noise_mix=0.18,
        noise_cutoff_hz=1800.0,
        sweep_semitones=2.0,
        lp_cutoff_hz=3000.0,
    ),
    "token_drop": SoundSpec(
        bus="sfx",
        notes=("A2",),
        attack_ms=12.0,
        note_ms=320.0,
        decay_tau_ms=80.0,
        harmonics=ROUND_HARMONICS,
        noise_mix=0.28,
        noise_cutoff_hz=1500.0,
        sweep_semitones=-2.0,
        lp_cutoff_hz=2400.0,
    ),
    "token_slide": SoundSpec(
        bus="sfx",
        notes=("A2",),
        attack_ms=40.0,
        note_ms=470.0,
        decay_tau_ms=220.0,
        harmonics=ROUND_HARMONICS,
        noise_mix=0.45,
        noise_cutoff_hz=2200.0,
        lp_cutoff_hz=2800.0,
        max_high_band_db=-16.0,
    ),
    "token_hover": SoundSpec(
        bus="sfx",
        notes=("E5",),
        attack_ms=12.0,
        note_ms=60.0,
        decay_tau_ms=18.0,
        harmonics=(1.0, 0.12),
        lp_cutoff_hz=5000.0,
    ),
    "token_whoosh": SoundSpec(
        bus="sfx",
        notes=("E4",),
        attack_ms=50.0,
        note_ms=500.0,
        decay_tau_ms=150.0,
        noise_mix=0.9,
        noise_cutoff_hz=3200.0,
        sweep_semitones=-5.0,
        lp_cutoff_hz=5200.0,
        max_high_band_db=-14.0,
    ),
    "splash_enter": SoundSpec(
        bus="sfx",
        notes=("C4", "G4"),
        attack_ms=30.0,
        note_ms=200.0,
        decay_tau_ms=110.0,
        noise_mix=0.22,
        noise_cutoff_hz=2600.0,
        lp_cutoff_hz=4200.0,
    ),
    "splash_exit": SoundSpec(
        bus="sfx",
        notes=("G4", "C4"),
        attack_ms=30.0,
        note_ms=200.0,
        decay_tau_ms=110.0,
        noise_mix=0.22,
        noise_cutoff_hz=2600.0,
        lp_cutoff_hz=4200.0,
    ),
}
