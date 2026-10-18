"""Bakes the fire's drawing book from a small 2D fire simulation, so each drawing grows out of the
last and the tips stretch and tear off by themselves. The game reads the book as a FireBook
resource (res://assets/fire/fire_book.res); tools/fire_sim/pack_fire_book.gd packs this script's
.bin into it, and tools/fire_sim/README.md has the whole procedure.

The model, per sequence (a closed loop of DRAWINGS drawings, 12 a second):
  - a stable-fluids grid at SCALE x the tile (semi-Lagrangian advection, Jacobi pressure, open
    sides and top, buoyancy from a temperature that cools, vorticity confinement for the curls);
  - one broad base per sequence whose outline wobbles, sways and breathes on the loop's period
    (strongly enough that the whole body deforms from drawing to drawing, base included) and whose
    lower part lies below the tile's bottom, with a few jets inside it that burst in turn (evenly
    spaced phases on one beat, so the body never pulses as a whole); the base never weakens below
    a floor, so no sequence goes out;
  - the base's strength varies across it in moving streaks, so thin streaks rise between thick
    ones and burn through first: many separate tongues, and holes where the density is low;
  - the flame scalar F burns down faster as it ages, so a mass stands about 1:1.5; its age rides
    along as F x age (mass-weighted, so an edge is as old as the material inside it);
  - each parcel carries a heat tag from the inlet (the jets hot, the base's weak spots cooler), so
    cooler licks curl over hot ones; a second carried noise rags the edge, a third opens holes;
  - pieces: torn flakes (straight-sided polygons stretched on a slant, at most about a quarter of
    the body's width) tear off a tongue's tip (the tip's material is cut where the piece leaves, so
    a notch opens), ride the flow up 2-3 body heights, turn, shrink and cool to red;
  - sparks are particles moved by the velocity, drawn as short chunky ovals (2-3 texels) along it,
    so they survive the default zoom.
The colour is baked as one heat value (seconds-like): the age, the tag, a carried patch noise and,
for old material, the depth inside its piece (an orange centre, a red edge). So orange and red
come as patches, tips and pieces, never as an even rim. The loop closes by blending the last BLEND
drawings' fields into the first ones before anything is thresholded, so the seam is a short morph.

Each layer stores what the draw thresholds, not colours: R the flame field (0.5 at the edge),
G the heat (0..HEAT_MAX), B the sparks, A a soft halo (about a quarter of the flame's width round
it). After the sequences the book holds one tear layer: a tiling pattern of straight creases and
upward spikes in R and G that the draw fetches at a few times the book's resolution and adds to the
field before its threshold (R) and to the heat (G), so the edge and the bands tear at every zoom
where a threshold of the smooth upscaled field would draw smooth curves. Its B holds a coarse,
isotropic lump pattern the draw fades to at the default zoom (where R's tall ridges read as
strands).

The book file, <out>/fire_sim_book.bin, little-endian: the magic "TTFSIM02"; int32 tile width,
tile height, sequences and drawings; per sequence an int32 width class and four float32 bounds
(left, top, right, bottom in the tile's UV, over every drawing); then the RGBA8 layers, rows top
first, each sequence's drawings in turn, and the tear layer last.

The contact sheets (<sheets>/sheet_frames.png, sim_seam.png, sheet_tear.png: drawings upscaled 3x
through the draw's tear) are written when --sheets is given. Run with Blender's bundled Python
(numpy):
  python.exe -I tools/fire_sim/bake_fire_book.py --out DIR [--sheets DIR] [--only 0,5]
"""

import argparse
import math
import os
import struct
import sys
import time
import zlib

import numpy as np

TILE_W, TILE_H = 96, 128
SCALE = 2
NX, NY = TILE_W * SCALE, TILE_H * SCALE
DRAWINGS = 48
BLEND = 10
WARMUP = 36
RATE = 12.0
SUB = 6
DT = 1.0 / (RATE * SUB)
LOOP_S = DRAWINGS / RATE
HEAT_MAX = 1.0
# The flame scalar's edge, and the field's encoding gain round it.
EDGE = 0.25
FIELD_GAIN = 1.0
MAGIC = b"TTFSIM02"
BOOK_NAME = "fire_sim_book.bin"

# The sequences: base width (share of the tile), jets, seed, width class (0 a small lively flame,
# 1 a medium mass, 2 a wide mass), and a burn and buoyancy scale (the small flames burn faster and
# rise slower, so they stay lumpy rather than a wick). Sorted by class; the draw picks within a
# class by the fire's seed.
SEQUENCES = [
    # The narrow ones are wide and burn fast (about 1:1.5-1:2; narrower and slower they read as
    # candles at 1:2-1:3), and the medium ones a little wider.
    dict(width=0.3, jets=2, seed=11, klass=0, burn=2.15, buoy=0.68),
    dict(width=0.32, jets=2, seed=23, klass=0, burn=2.05, buoy=0.68),
    dict(width=0.34, jets=3, seed=37, klass=0, burn=2.0, buoy=0.7),
    dict(width=0.36, jets=3, seed=41, klass=1, burn=1.85, buoy=0.7),
    dict(width=0.39, jets=3, seed=53, klass=1, burn=1.85, buoy=0.7),
    dict(width=0.4, jets=4, seed=67, klass=2, burn=1.15, buoy=1.0),
    dict(width=0.44, jets=5, seed=71, klass=2, burn=1.15, buoy=1.0),
    dict(width=0.48, jets=5, seed=89, klass=2, burn=1.1, buoy=1.0),
]

# The physics, in grid cells and seconds.
P = dict(
    emit_v=24.0,
    jet_v=30.0,
    buoy=260.0,
    cool=1.1,
    drag=0.9,
    burn=1.2,
    burn_age=2.2,
    vort=16.0,
    jacobi=30,
    noise_amp=0.36,
    noise_cells=10.0,
    hole_amp=1.3,
    hole_cells=10.0,
    wobble=30.0,
    spark_rate=(1.0, 4.0),
    # Pieces: a second's rate (lo + hi x width), radius (share of the base's width, plus 1 cell),
    # life (s), extra rise (cells a second) over the flow's share, the heat they cool to. At most
    # about a quarter of the body: bigger ones (0.14-0.2) read as coins as big as a small fire.
    piece_rate=(1.2, 2.6),
    piece_r=(0.05, 0.08),
    piece_span=(0.9, 1.5),
    piece_rise=90.0,
    piece_flow=0.6,
    piece_cool=0.42,
    # Old material's erosion of the field (field units) from age old_from on.
    old_erode=0.45,
    old_from=0.22,
)

# The heat (the colour's input, seconds-like): the age, plus a cooler tag's offset and stretch, a
# carried patch noise once the material has left the base, and an old piece's centre made hotter
# by its depth inside the piece.
HEAT = dict(tag_add=0.1, tag_mul=1.5, patch=0.14, patch_from=0.08, piece_core=0.14)


def smooth_noise(rng, ny, nx, cells, stretch=1.0):
    """Periodic smooth noise (unit spread) with features about `cells` across (`stretch` times
    taller than wide)."""
    white = rng.standard_normal((ny, nx))
    ky = np.fft.fftfreq(ny)[:, None] / stretch
    kx = np.fft.fftfreq(nx)[None, :]
    k = np.sqrt(kx * kx + ky * ky) * cells
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * np.exp(-(k * k) * 4.0)))
    out /= out.std() + 1e-9
    return np.tanh(out * 0.8).astype(np.float32)


class Sampler:
    """Bilinear weights for one backtrace, applied to any number of fields."""

    def __init__(self, x, y):
        x = np.clip(x, 0.0, NX - 1.001)
        y = np.clip(y, 0.0, NY - 1.001)
        self.x0 = x.astype(np.int32)
        self.y0 = y.astype(np.int32)
        self.fx = (x - self.x0).astype(np.float32)
        self.fy = (y - self.y0).astype(np.float32)

    def __call__(self, f):
        x0, y0, fx, fy = self.x0, self.y0, self.fx, self.fy
        a = f[y0, x0] * (1 - fx) + f[y0, x0 + 1] * fx
        b = f[y0 + 1, x0] * (1 - fx) + f[y0 + 1, x0 + 1] * fx
        return a * (1 - fy) + b * fy


def sample_at(f, px, py):
    return Sampler(np.asarray(px), np.asarray(py))(f)


def loop_waves(rng, count, rx, amp, freq):
    """`count` sines across the base (amplitude, cells^-1 frequency, whole turns a loop, phase)."""
    out = []
    for _ in range(count):
        turns = int(rng.integers(1, 4)) * (1 if rng.uniform() < 0.5 else -1)
        out.append((rng.uniform(*amp), rng.uniform(*freq) / rx, turns, rng.uniform(0.0, 2.0 * math.pi)))
    return out


def wave(x, w, terms):
    out = np.zeros_like(x)
    for amp, k, turns, phase in terms:
        out += amp * np.sin(k * x + turns * w + phase)
    return out


def turn(rng, lo, hi):
    """A whole number of turns a loop, either way."""
    return int(rng.integers(lo, hi + 1)) * (1 if rng.uniform() < 0.5 else -1)


class Emitter:
    """The foot: one broad base (outline wobbling, swaying and breathing, strength and heat varying
    across it, all on the loop's period) with jets inside it that burst in turn."""

    def __init__(self, spec, rng):
        width = spec["width"] * NX
        self.cx = NX * 0.5 + rng.uniform(-0.05, 0.05) * width
        self.rx = width * 0.5
        self.ry = self.rx * rng.uniform(0.5, 0.75)
        # The base's centre near the tile's bottom: a little of it lies below the tile, so its
        # foot is one broad round bottom the draw's soft foot fades out.
        self.cy = self.ry * rng.uniform(0.6, 0.85)
        self.skew = rng.uniform(-0.35, 0.35)
        # The outline wobbles on four harmonics turning 1-3 times a loop, the base sways sideways
        # and breathes, so the body's whole outline deforms, not only its tips.
        self.rim = [(rng.uniform(0.1, 0.18), n, turn(rng, 1, 3), rng.uniform(0, 6.3)) for n in (2, 3, 4, 6)]
        self.sway = (rng.uniform(0.07, 0.12) * width, turn(rng, 1, 2), rng.uniform(0, 6.3))
        self.lean = (rng.uniform(0.15, 0.3), turn(rng, 1, 2), rng.uniform(0, 6.3))
        self.breathe = (rng.uniform(0.06, 0.1), turn(rng, 2, 3), rng.uniform(0, 6.3))
        # Three streak waves of uneven strength, so the wide masses send up several small tongues
        # (four even ones sent up a comb of equal tongues and a strand texture at the default zoom).
        self.thick = loop_waves(rng, 3, self.rx, (0.1, 0.26), (2.5, 8.0))
        self.tag = loop_waves(rng, 3, self.rx, (0.12, 0.22), (2.0, 7.0))
        k = spec["jets"]
        spread = np.linspace(-0.5, 0.5, k) if k > 1 else np.zeros(1)
        self.k = k
        self.jx = self.cx + spread * width * 0.5 + rng.uniform(-0.06, 0.06, k) * width
        self.jr = width / (k * 1.25 + 1.0) * rng.uniform(0.8, 1.2, k)
        self.jdrift = rng.uniform(0.06, 0.14, k) * width
        self.jphase = rng.uniform(0.0, 2.0 * math.pi, k)
        # One beat for all the jets, their bursts evenly spaced round it (shuffled across the base),
        # so one jet is always strong and the body's height holds.
        self.beat = int(rng.integers(5, 8))
        self.jburst = (rng.permutation(k) / k) * 2.0 * math.pi

    def fields(self, gx, gy, t):
        """The inlet's (profile, strength, tag, jet) at time t (seconds, periodic on LOOP_S)."""
        w = 2.0 * math.pi * t / LOOP_S
        sa, sc, sp = self.sway
        la, lc, lp = self.lean
        ba, bc, bp = self.breathe
        cx = self.cx + sa * math.sin(sc * w + sp)
        ry = self.ry * (1.0 + ba * math.sin(bc * w + bp))
        skew = self.skew + la * math.sin(lc * w + lp)
        dx = gx - cx - skew * (gy - self.cy)
        dy = gy - self.cy
        ang = np.arctan2(dy / ry, dx / self.rx)
        wob = 1.0 + sum(a * np.sin(n * ang + c * w + p) for a, n, c, p in self.rim)
        d = np.sqrt((dx / self.rx) ** 2 + (dy / ry) ** 2) / wob
        base = np.clip((1.0 - d) * 2.5, 0.0, 1.0)
        # Thick and thin streaks across the base; the floor keeps the base alight.
        # Thinner toward the sides, so a mass tapers to a lumpy round top rather than a comb.
        taper = 1.0 - 0.4 * np.clip(np.abs(dx) / self.rx, 0.0, 1.0) ** 2
        thick = np.clip(0.72 + wave(dx, w, self.thick), 0.45, 1.0) * taper
        strength = base * thick
        # The base burns cooler than the jets, unevenly across it: cooler licks beside hot cores.
        tag = base * np.clip(0.35 + wave(dx, w, self.tag), 0.05, 0.8)
        jet = np.zeros_like(base)
        for i in range(self.k):
            x = self.jx[i] + (cx - self.cx) + self.jdrift[i] * math.sin(w + self.jphase[i])
            # A burst: sharp, so the column above pinches off between bursts.
            burst = (0.5 + 0.5 * math.sin(w * self.beat + self.jburst[i])) ** 2
            r = self.jr[i] * (0.7 + 0.3 * burst)
            # Short and broad (2.4 tall jets stood as rods), its foot inside the base.
            y = self.cy + ry * 0.15
            lump = np.clip((1.0 - ((gx - x) / r) ** 2 - ((gy - y) / (r * 2.0)) ** 2) * 2.0, 0.0, 1.0)
            # Gentle bursts: full ones sent up slugs that aged as one red column and pulsed the
            # height.
            jet = np.maximum(jet, lump * (0.5 + 0.5 * burst))
            strength = np.maximum(strength, lump * (0.8 + 0.2 * burst))
            tag = np.maximum(tag, lump * (0.7 + 0.3 * burst))
        profile = np.maximum(base, jet)
        return profile, strength, tag, jet


class Sim:
    def __init__(self, spec):
        self.spec = spec
        self.rng = np.random.default_rng(spec["seed"])
        self.emitter = Emitter(spec, self.rng)
        shape = (NY, NX)
        self.u = np.zeros(shape, np.float32)
        self.v = np.zeros(shape, np.float32)
        self.f = np.zeros(shape, np.float32)
        self.g = np.zeros(shape, np.float32)
        self.h = np.zeros(shape, np.float32)
        self.temp = np.zeros(shape, np.float32)
        self.noise = np.zeros(shape, np.float32)
        self.holes = np.zeros(shape, np.float32)
        self.p = np.zeros((NY + 2, NX + 2), np.float32)
        self.noise_src = smooth_noise(self.rng, NY, NX, P["noise_cells"])
        self.hole_src = np.clip((smooth_noise(self.rng, NY, NX, P["hole_cells"]) - 0.35) / 0.2, 0.0, 1.0)
        self.wobble_src = smooth_noise(self.rng, NY, NX, 24.0)
        self.gy, self.gx = np.mgrid[0:NY, 0:NX].astype(np.float32)
        self.t = 0.0
        self.sparks = []
        self.pieces = []

    def emit(self):
        profile, strength, tag, jet = self.emitter.fields(self.gx, self.gy, self.t)
        src = np.roll(self.noise_src, int(self.t * 40.0) % NY, axis=0)
        holes = np.roll(self.hole_src, int(self.t * 55.0) % NY, axis=0)
        wob = np.roll(self.wobble_src, int(self.t * 25.0) % NX, axis=1)
        self.f = np.maximum(self.f, strength)
        self.temp = np.maximum(self.temp, profile * (0.55 + 0.45 * strength))
        self.g *= 1.0 - profile
        # The tag broken by the carried noise, so no inlet shape shows in the colour.
        self.h = self.h * (1.0 - profile) + tag * (0.92 + 0.2 * src)
        self.noise = self.noise * (1.0 - profile) + src * profile
        self.holes = self.holes * (1.0 - profile) + holes * profile
        self.v = np.maximum(self.v, P["emit_v"] * strength + P["jet_v"] * jet)
        self.u = self.u * (1.0 - profile) + profile * wob * P["wobble"]

    def forces(self):
        self.v += P["buoy"] * self.spec["buoy"] * self.temp * DT
        w = np.gradient(self.v, axis=1) - np.gradient(self.u, axis=0)
        aw = np.abs(w)
        gx = np.gradient(aw, axis=1)
        gy = np.gradient(aw, axis=0)
        mag = np.sqrt(gx * gx + gy * gy) + 1e-5
        self.u += P["vort"] * (gy / mag) * w * DT
        self.v += -P["vort"] * (gx / mag) * w * DT
        damp = 1.0 - P["drag"] * DT
        self.u *= damp
        self.v *= damp

    def project(self):
        div = np.gradient(self.u, axis=1) + np.gradient(self.v, axis=0)
        p = self.p
        for _ in range(P["jacobi"]):
            p[1:-1, 1:-1] = (p[1:-1, :-2] + p[1:-1, 2:] + p[:-2, 1:-1] + p[2:, 1:-1] - div) * 0.25
        inner = p[1:-1, 1:-1]
        self.u -= np.gradient(inner, axis=1)
        self.v -= np.gradient(inner, axis=0)

    def advect(self):
        back = Sampler(self.gx - self.u * DT, self.gy - self.v * DT)
        self.u, self.v = back(self.u), back(self.v)
        self.f, self.g, self.h = back(self.f), back(self.g), back(self.h)
        self.temp, self.noise, self.holes = back(self.temp), back(self.noise), back(self.holes)

    def burn(self):
        old = np.maximum(self.f, 1e-6)
        age = self.g / old
        rate = P["burn"] * self.spec["burn"] * (1.0 + P["burn_age"] * age)
        self.f = np.maximum(self.f - rate * DT, 0.0)
        self.g *= self.f / old
        self.g += self.f * DT
        self.temp *= math.exp(-P["cool"] * DT)

    def step(self):
        self.emit()
        self.forces()
        self.project()
        self.advect()
        self.burn()
        self.move_sparks()
        self.move_pieces()
        self.t += DT

    def spawn_sparks(self):
        lo, hi = P["spark_rate"]
        rate = lo + hi * self.spec["width"]
        for _ in range(self.rng.poisson(rate / RATE)):
            age = self.g / np.maximum(self.f, 1e-4)
            ys, xs = np.nonzero((self.f > EDGE) & (age > 0.12))
            if xs.size == 0:
                return
            i = self.rng.integers(xs.size)
            self.sparks.append(
                dict(
                    x=float(xs[i]),
                    y=float(ys[i]),
                    vx=float(self.rng.normal(0.0, 25.0)),
                    vy=float(self.rng.uniform(20.0, 60.0)),
                    life=0.0,
                    span=float(self.rng.uniform(1.0, 2.0)),
                    size=float(self.rng.uniform(1.5, 2.4)),
                )
            )

    def spawn_pieces(self):
        """Tears pieces off the tips: a chunk about a quarter of the base's width leaves a solid
        part near the body's top, and the material it took is cut from the body (a notch)."""
        lo, hi = P["piece_rate"]
        count = self.rng.poisson((lo + hi * self.spec["width"]) / RATE)
        if count == 0:
            return
        age = self.g / np.maximum(self.f, 1e-4)
        ys, xs = np.nonzero((self.f > 0.4) & (age > 0.05))
        if xs.size == 0:
            return
        near_top = ys >= ys.max() - 0.3 * (ys.max() - ys.min() + 1)
        ys, xs = ys[near_top], xs[near_top]
        width = self.spec["width"] * NX
        for _ in range(count):
            i = self.rng.integers(xs.size)
            x, y = float(xs[i]), float(ys[i])
            r = self.rng.uniform(*P["piece_r"]) * width + 1.0
            d = np.hypot(self.gx - x, self.gy - y) / (r * 1.4)
            cut = 0.9 * np.sqrt(np.clip(1.0 - d, 0.0, 1.0))
            self.f *= 1.0 - cut
            self.g *= 1.0 - cut
            # A torn flake, not a coin: a convex polygon of 3-5 straight sides (each side's
            # direction jittered round the turn, its distance uneven), stretched along a slanted
            # axis, turning as it rises; the noise rags its sides.
            n = int(self.rng.integers(3, 6))
            base = self.rng.uniform(0.0, 2.0 * math.pi)
            sides = [
                (
                    base + 2.0 * math.pi * k / n + self.rng.uniform(-0.3, 0.3) * 2.0 * math.pi / n,
                    float(self.rng.uniform(0.7, 1.15)),
                )
                for k in range(n)
            ]
            self.pieces.append(
                dict(
                    x=x,
                    y=y,
                    vx=float(sample_at(self.u, [x], [y])[0]),
                    vy=float(sample_at(self.v, [x], [y])[0]),
                    r=r,
                    life=0.0,
                    span=float(self.rng.uniform(*P["piece_span"])),
                    h0=float(self.rng.uniform(0.15, 0.2)),
                    stretch=float(self.rng.uniform(1.3, 2.0)),
                    axis=float(self.rng.uniform(0.3, 1.3) * (1 if self.rng.uniform() < 0.5 else -1)),
                    spin=float(self.rng.uniform(-1.5, 1.5)),
                    sides=sides,
                )
            )

    def move_pieces(self):
        keep = []
        ease = 1.0 - math.exp(-DT * 4.0)
        for p in self.pieces:
            fu = float(sample_at(self.u, [p["x"]], [p["y"]])[0])
            fv = float(sample_at(self.v, [p["x"]], [p["y"]])[0])
            p["vx"] += (fu * 0.7 - p["vx"]) * ease
            p["vy"] += (max(fv, 0.0) * P["piece_flow"] + P["piece_rise"] - p["vy"]) * ease
            p["x"] += p["vx"] * DT
            p["y"] += p["vy"] * DT
            p["life"] += DT
            if p["life"] < p["span"] and p["y"] < NY * 0.95:
                keep.append(p)
        self.pieces = keep

    def draw_pieces(self):
        """The pieces' field (EDGE at their outline) and heat, -1 / 0 where there is none."""
        field = np.full((NY, NX), -1.0, np.float32)
        heat = np.zeros((NY, NX), np.float32)
        for p in self.pieces:
            k = p["life"] / p["span"]
            rr = p["r"] * (1.0 - k) ** 0.6
            if rr < 1.2:
                continue
            reach = int(rr * 2.4 * p["stretch"]) + 2
            x0, x1 = max(int(p["x"]) - reach, 0), min(int(p["x"]) + reach + 1, NX)
            y0, y1 = max(int(p["y"]) - reach, 0), min(int(p["y"]) + reach + 1, NY)
            if x1 <= x0 or y1 <= y0:
                continue
            qx = self.gx[y0:y1, x0:x1] - p["x"]
            qy = self.gy[y0:y1, x0:x1] - p["y"]
            turn_a = p["axis"] + p["spin"] * p["life"]
            ca, sa = math.cos(turn_a), math.sin(turn_a)
            along = (qx * ca + qy * sa) / p["stretch"]
            side = -qx * sa + qy * ca
            # The polygon's own distance (1 on its sides): the farthest side's reach.
            d = np.max(np.stack([(along * math.cos(t) + side * math.sin(t)) / s for t, s in p["sides"]]), axis=0) / rr
            # Steep, so the straight sides and corners survive the draw's tear; the noise rags them
            # a little. It cools from orange to red over its life.
            val = EDGE + 0.6 * (1.0 - d) + 0.1 * self.noise_src[y0:y1, x0:x1]
            hot = p["h0"] + (P["piece_cool"] - p["h0"]) * k**0.8 + 0.04 * np.clip(d, 0.0, 1.0)
            win = field[y0:y1, x0:x1]
            over = val > win
            field[y0:y1, x0:x1] = np.where(over, val, win)
            heat[y0:y1, x0:x1] = np.where(over, hot, heat[y0:y1, x0:x1])
        return field, heat

    def move_sparks(self):
        keep = []
        ease = 1.0 - math.exp(-DT * 2.5)
        for s in self.sparks:
            fu = float(sample_at(self.u, [s["x"]], [s["y"]])[0])
            fv = float(sample_at(self.v, [s["x"]], [s["y"]])[0])
            s["vx"] += (fu - s["vx"]) * ease + self.rng.normal(0.0, 4.0)
            s["vy"] += (fv + 30.0 - s["vy"]) * ease
            s["x"] += s["vx"] * DT
            s["y"] += s["vy"] * DT
            s["life"] += DT
            # Kept off the tile's sides and top, so a spark's drift never widens the sequence's
            # bounds (the quad) to the whole tile.
            if s["life"] < s["span"] and abs(s["x"] / NX - 0.5) < 0.38 and s["y"] < NY * 0.92:
                keep.append(s)
        self.sparks = keep

    def draw_sparks(self):
        img = np.zeros((NY, NX), np.float32)
        for s in self.sparks:
            speed = math.hypot(s["vx"], s["vy"]) + 1e-3
            dx, dy = s["vx"] / speed, s["vy"] / speed
            half_l = (2.5 + min(speed, 220.0) * 0.012) * s["size"]
            half_w = 1.3 * s["size"]
            glow = (1.0 - s["life"] / s["span"]) ** 0.4
            x0, x1 = int(s["x"] - 12), int(s["x"] + 13)
            y0, y1 = int(s["y"] - 12), int(s["y"] + 13)
            x0, y0 = max(x0, 0), max(y0, 0)
            x1, y1 = min(x1, NX), min(y1, NY)
            if x1 <= x0 or y1 <= y0:
                continue
            qx = self.gx[y0:y1, x0:x1] - s["x"]
            qy = self.gy[y0:y1, x0:x1] - s["y"]
            a = (qx * dx + qy * dy) / half_l
            b = (-qx * dy + qy * dx) / half_w
            val = np.sqrt(np.clip(1.0 - (a * a + b * b), 0.0, 1.0)) * glow
            img[y0:y1, x0:x1] = np.maximum(img[y0:y1, x0:x1], val)
        return img

    def snapshot(self):
        """The fields a drawing is made from, at grid resolution (the heat mass-weighted)."""
        age = self.g / np.maximum(self.f, 1e-4)
        rag = 0.4 + 0.6 * np.clip(age / 0.3, 0.0, 1.0)
        field = self.f + P["noise_amp"] * self.noise * rag
        # Holes where the material is thin, once it has left the base.
        thin = np.clip(1.3 - self.f, 0.0, 1.0) * np.clip((age - 0.03) / 0.08, 0.0, 1.0)
        field = field - P["hole_amp"] * self.holes * thin
        # Old material thins away (else it streams up as thin dark-red spikes twice the body's
        # height); the pieces, drawn after, carry the red.
        field = field - P["old_erode"] * np.clip((age - P["old_from"]) / 0.2, 0.0, 1.0)
        # Thin rods (a jet streaming up 2-3 texels wide, twice the body's height) opened away:
        # features narrower than the disk go, broad bodies and tongues keep their outline.
        opened = open_disk(field)
        field = opened + OPEN_KEEP * (field - opened)
        cool = 1.0 - np.clip(self.h, 0.0, 1.0)
        patch = HEAT["patch"] * self.noise * np.clip(age / HEAT["patch_from"], 0.0, 1.0)
        heat = age * (1.0 + HEAT["tag_mul"] * cool) + HEAT["tag_add"] * cool + patch
        f = self.f.copy()
        # The pieces over the body: where a piece's field tops the body's, it is the piece.
        pf, ph = self.draw_pieces()
        over = pf > field
        field = np.where(over, pf, field)
        f = np.where(over, np.maximum(f, 0.45), f)
        fh = np.where(over, f * ph, f * np.maximum(heat, 0.0))
        # Nothing reaches the tile's top or sides: a piece there shrinks away before the edge.
        top = np.clip((self.gy / NY - 0.84) / 0.14, 0.0, 1.0)
        side = np.clip((np.abs(self.gx / NX - 0.5) - 0.42) / 0.07, 0.0, 1.0)
        field = field - 0.8 * np.maximum(top, side)
        return dict(field=field, f=f, fh=fh, sparks=self.draw_sparks())


def down(a):
    return a.reshape(TILE_H, SCALE, TILE_W, SCALE).mean(axis=(1, 3))


# The body's opening: the disk's radius (grid cells) and how much of what it removes is kept.
OPEN_R = 3
OPEN_KEEP = 0.2
OPEN_DISK = [(dy, dx) for dy in range(-OPEN_R, OPEN_R + 1) for dx in range(-OPEN_R, OPEN_R + 1) if dx * dx + dy * dy <= OPEN_R * OPEN_R + 1]


def shift_reduce(a, offsets, pick):
    """`pick` (np.minimum or np.maximum) of `a` over the given (dy, dx) offsets, edges padded."""
    r = max(max(abs(dy), abs(dx)) for dy, dx in offsets)
    pad = np.pad(a, r, mode="edge")
    out = a.copy()
    h, w = a.shape
    for dy, dx in offsets:
        out = pick(out, pad[r + dy : r + dy + h, r + dx : r + dx + w])
    return out


def open_disk(a):
    """Morphological opening of `a` by the disk OPEN_DISK (erode, then dilate)."""
    return shift_reduce(shift_reduce(a, OPEN_DISK, np.minimum), OPEN_DISK, np.maximum)


def blur(a, r, passes=3):
    out = a
    for _ in range(passes):
        pad = np.pad(out, r, mode="constant")
        c = np.cumsum(pad, axis=1)
        c = np.concatenate([np.zeros((c.shape[0], 1), c.dtype), c], axis=1)
        out = (c[:, 2 * r + 1 :] - c[:, : -2 * r - 1]) / (2 * r + 1)
        c = np.cumsum(out, axis=0)
        c = np.concatenate([np.zeros((1, c.shape[1]), c.dtype), c], axis=0)
        out = (c[2 * r + 1 :, :] - c[: -2 * r - 1, :]) / (2 * r + 1)
    return out


def mix_snap(a, b, k):
    """Snapshot a blended toward b by k: fields linear, the heat mass-weighted."""
    return dict(
        field=a["field"] * (1 - k) + b["field"] * k,
        f=a["f"] * (1 - k) + b["f"] * k,
        fh=a["fh"] * (1 - k) + b["fh"] * k,
        sparks=np.maximum(a["sparks"] * (1 - k), b["sparks"] * k),
    )


# The halo's blur radius (texels, three box passes) and gain.
HALO_R = 8
HALO_GAIN = 1.5


def encode(snap):
    """A drawing's RGBA8 layer (tile rows top first) from a grid snapshot."""
    field = down(snap["field"])
    f = down(snap["f"])
    heat = down(snap["fh"]) / np.maximum(f, 1e-4)
    valid = f > 0.03
    heat = np.where(valid, heat, 0.0)
    weight = valid.astype(np.float32)
    for _ in range(8):
        sa = blur(heat * weight, 1, 1)
        sw = blur(weight, 1, 1)
        fill = sa / np.maximum(sw, 1e-4)
        heat = np.where(weight > 0, heat, np.where(sw > 0, fill, heat))
        weight = np.maximum(weight, (sw > 0).astype(np.float32))
    # Beyond that the heat's wide blur, not HEAT_MAX, so no mip pulls a red into a body's edge
    # (an even hairline rim at the default zoom otherwise).
    sa = blur(heat * weight, 12, 2)
    sw = blur(weight, 12, 2)
    heat = np.where(weight > 0, heat, np.where(sw > 1e-3, sa / np.maximum(sw, 1e-4), HEAT_MAX))
    # An old piece or tip is hotter in its middle: an orange centre, a red edge.
    depth = np.clip((blur((field > EDGE).astype(np.float32), 2, 2) - 0.35) / 0.5, 0.0, 1.0)
    old = np.clip((heat - 0.12) / 0.12, 0.0, 1.0)
    heat = heat - HEAT["piece_core"] * depth * old
    r = np.clip(0.5 + (field - EDGE) * FIELD_GAIN, 0.0, 1.0)
    gch = np.clip(heat / HEAT_MAX, 0.0, 1.0)
    bch = np.clip(down(snap["sparks"]) * 1.6, 0.0, 1.0)
    cover = np.clip((r - 0.5) * 12.0, 0.0, 1.0) * (1.0 - 0.6 * gch)
    ach = np.clip(blur(cover, HALO_R) * HALO_GAIN, 0.0, 1.0)
    layer = np.stack([r, gch, bch, ach], axis=-1)[::-1]
    return np.round(layer * 255.0).astype(np.uint8)


def tear_layer(seed=5):
    """The tear tile (tiling, TILE_W x TILE_H): R straight creases between jittered cells (torn
    paper's angular notches) mixed with sharp upward ridges, G the same pattern shifted (the
    bands' tear), both mean about 0.5; B the default zoom's coarse lumps."""
    rng = np.random.default_rng(seed)
    gy, gx = np.mgrid[0:TILE_H, 0:TILE_W].astype(np.float32) + 0.5

    def creases(cells_x, cells_y, squash=0.6):
        cw, ch = TILE_W / cells_x, TILE_H / cells_y
        px = (np.arange(cells_x)[None, :] + rng.uniform(0.15, 0.85, (cells_y, cells_x))) * cw
        py = (np.arange(cells_y)[:, None] + rng.uniform(0.15, 0.85, (cells_y, cells_x))) * ch
        px, py = px.ravel(), py.ravel()
        dx = np.abs(gx[..., None] - px)
        dy = np.abs(gy[..., None] - py)
        dx = np.minimum(dx, TILE_W - dx)
        dy = np.minimum(dy, TILE_H - dy)
        # Cells taller than wide: the creases run mostly upward, as a flame's tears do.
        d = np.sort(np.sqrt(dx * dx + (dy * squash) ** 2), axis=-1)
        return np.clip((d[..., 1] - d[..., 0]) / (0.45 * cw), 0.0, 1.0)

    def ridges(cells):
        n = smooth_noise(rng, TILE_H, TILE_W, cells, stretch=2.2)
        return 1.0 - np.abs(n)

    def pattern():
        t = 0.55 * creases(5, 5) + 0.25 * ridges(5.0) + 0.2 * ridges(2.5)
        return (t - t.mean()) / (2.5 * t.std() + 1e-6) + 0.5

    def lumps():
        # The default zoom's tear, coarse and as wide as tall (big cells' notches and round lumps),
        # which the mips keep where the tall ridges read as strands.
        t = 0.6 * creases(3, 4, 1.0) + 0.4 * smooth_noise(rng, TILE_H, TILE_W, 14.0)
        return (t - t.mean()) / (2.5 * t.std() + 1e-6) + 0.5

    r = pattern()
    g = pattern()
    b = lumps()
    layer = np.stack([r, g, b, np.zeros_like(r)], axis=-1)
    return np.round(np.clip(layer, 0.0, 1.0) * 255.0).astype(np.uint8)


def run_sequence(spec):
    sim = Sim(spec)
    snaps = []
    total = WARMUP + DRAWINGS + BLEND
    for d in range(total):
        for _ in range(SUB):
            sim.step()
        sim.spawn_sparks()
        sim.spawn_pieces()
        if d >= WARMUP:
            snaps.append(sim.snapshot())
    layers = []
    for k in range(DRAWINGS):
        snap = snaps[k]
        if k < BLEND:
            snap = mix_snap(snaps[DRAWINGS + k], snaps[k], (k + 0.5) / BLEND)
        layers.append(encode(snap))
    return layers


# The preview's ramp (mirrors the flame shader's defaults): the heat banded white, cream, yellow,
# orange, red; the soft foot as the draw's (FOOT_SOFT over ROOM flame heights).
STOPS = (0.035, 0.07, 0.14, 0.26)
ROOM = 2.1
FOOT_SOFT = 0.2
# The draw's foot: the field lifted near the bottom (rounding the foot's corners) and the
# feather's line ragged by the tear.
FOOT_LIFT = 0.18
FOOT_LIFT_H = 0.3
FOOT_RAG = 0.14
# The draw's tear defaults: the tear tile's repeats across the drawing, its weight on the field
# (more on old material), and on the heat.
TEAR_SCALE = 2.5
TEAR_AMP = (0.1, 0.22)
TEAR_HEAT = 0.03
# The draw's linear colours, put through the sRGB curve for the preview.
COLS = (
    np.array(
        [
            [1.0, 0.9, 0.55],
            [1.0, 0.68, 0.2],
            [1.0, 0.48, 0.06],
            [1.0, 0.22, 0.02],
            [0.6, 0.03, 0.015],
        ],
        np.float32,
    )
    ** (1.0 / 2.2)
)
SPARK = np.array([1.0, 0.9, 0.55], np.float32)
BG = np.array([0.09, 0.085, 0.11], np.float32)
HALO = np.array([1.0, 0.3, 0.045], np.float32) ** (1.0 / 2.2)


def upscale(a, k):
    """Bilinear upscale of an (h, w, c) array by k (texel centres kept, edges clamped)."""
    h, w = a.shape[:2]
    ys = np.clip((np.arange(h * k) + 0.5) / k - 0.5, 0.0, h - 1.001)
    xs = np.clip((np.arange(w * k) + 0.5) / k - 0.5, 0.0, w - 1.001)
    y0, x0 = ys.astype(np.int32), xs.astype(np.int32)
    fy, fx = (ys - y0)[:, None, None], (xs - x0)[None, :, None]
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x0 + 1] * fx
    bot = a[y0 + 1][:, x0] * (1 - fx) + a[y0 + 1][:, x0 + 1] * fx
    return top * (1 - fy) + bot * fy


def preview(layer, tear=None, k=1):
    """A drawing as the draw shows it: at k x with the tear tile added (tear given), else 1x."""
    a = layer.astype(np.float32) / 255.0
    if k > 1:
        a = upscale(a, k)
    h, w = a.shape[:2]
    inside = a[..., 0] - 0.5
    heat = a[..., 1]
    v = (np.arange(h, dtype=np.float32)[::-1, None] + 0.5) / h * ROOM
    u = (np.arange(w, dtype=np.float32)[None, :] + 0.5) / w
    rag = np.zeros_like(inside)
    if tear is not None:
        t = tear.astype(np.float32) / 255.0
        ty = (np.arange(h) * TEAR_SCALE / k).astype(np.int32) % TILE_H
        tx = (np.arange(w) * TEAR_SCALE / k).astype(np.int32) % TILE_W
        tt = t[ty][:, tx]
        amp = TEAR_AMP[0] + (TEAR_AMP[1] - TEAR_AMP[0]) * np.clip((heat - STOPS[0]) / (STOPS[2] - STOPS[0]), 0.0, 1.0)
        rag = tt[..., 0] - 0.5
        inside = inside + rag * amp
        heat = heat + (tt[..., 1] - 0.5) * TEAR_HEAT
    lift = 1.0 - np.clip(v / FOOT_LIFT_H, 0.0, 1.0)
    inside = inside - FOOT_LIFT * lift * lift
    shape = np.clip(inside / 0.04 + 0.5, 0.0, 1.0) if k == 1 else (inside > 0).astype(np.float32)
    soft = FOOT_SOFT * (1.0 + 2.5 * (2.0 * u - 1.0) ** 2)
    shape = shape * np.clip((v + rag * FOOT_RAG) / soft, 0.0, 1.0)
    band = np.zeros(heat.shape, np.int32)
    for s in STOPS:
        band += heat > s
    colour = COLS[band]
    halo_a = np.clip((a[..., 3] - 0.08) / 0.92, 0.0, 1.0) ** 1.5
    halo = halo_a[..., None] * HALO * 0.5 * (1 - shape[..., None])
    spark = a[..., 2, None]
    out = BG * (1 - shape[..., None]) + colour * shape[..., None] + halo
    out = out * (1 - spark) + SPARK * spark
    return np.clip(out * 255.0, 0, 255).astype(np.uint8)


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def grid(tiles, columns, gap=2):
    rows = (len(tiles) + columns - 1) // columns
    h, w, _ = tiles[0].shape
    out = np.full((rows * (h + gap), columns * (w + gap), 3), 40, np.uint8)
    for i, t in enumerate(tiles):
        r, c = divmod(i, columns)
        out[r * (h + gap) : r * (h + gap) + h, c * (w + gap) : c * (w + gap) + w] = t
    return out


# The halo's cut (A below it draws nothing, so the quad's edge never shows a step).
HALO_CUT = 20


def bounds(layers):
    a = np.stack(layers).astype(np.int32)
    used = (a[..., 0] > 120) | (a[..., 2] > 5) | (a[..., 3] > HALO_CUT)
    any_used = used.any(axis=0)
    ys, xs = np.nonzero(any_used)
    if xs.size == 0:
        return (0.0, 0.0, 1.0, 1.0)
    left, right = max(xs.min() - 1, 0), min(xs.max() + 2, TILE_W)
    top, bottom = max(ys.min() - 1, 0), min(ys.max() + 2, TILE_H)
    return (left / TILE_W, top / TILE_H, right / TILE_W, bottom / TILE_H)


def body_stats(layers):
    """The body's height (texels, the R > 0.5 rows: mean, least and most over the loop), its mean
    width, the share of its texels in each band and its fewest texels, for the log."""
    a = np.stack(layers).astype(np.float32) / 255.0
    body = a[..., 0] > 0.5
    rows = body.any(axis=2)
    cols = body.any(axis=1)
    heights = [TILE_H - np.nonzero(r)[0].min() if r.any() else 0 for r in rows]
    widths = [np.ptp(np.nonzero(c)[0]) + 1 if c.any() else 0 for c in cols]
    # The mass: the unbroken run of rows up from the bottom holding at least a quarter of the
    # widest row's texels (tips and detached pieces left out), so its height says how the body
    # itself breathes.
    mass = []
    for k in range(len(layers)):
        counts = body[k].sum(axis=1)[::-1]
        weak = np.nonzero(counts < 0.25 * max(counts.max(), 1))[0]
        start = int(np.argmax(counts > 0))
        weak = weak[weak > start]
        mass.append(int(weak[0]) if weak.size else TILE_H)
    heat = a[..., 1][body]
    bands = np.zeros(heat.shape, np.int32)
    for s in STOPS:
        bands += heat > s
    share = np.bincount(bands, minlength=5) / max(heat.size, 1)
    least = int(body.reshape(len(layers), -1).sum(axis=1).min())
    return np.mean(heights), np.mean(widths), share, least, (min(mass), np.mean(mass), max(mass))


def old_bounds(path):
    """The sequences' bounds areas (tile shares) in the book at `path` before it is rewritten."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(8 + 16)
            if head[:6] != b"TTFSIM":
                return []
            count = struct.unpack("<4i", head[8:24])[2]
            out = []
            for _ in range(count):
                _, x0, y0, x1, y1 = struct.unpack("<i4f", fh.read(20))
                out.append((x1 - x0) * (y1 - y0))
            return out
    except OSError:
        return []


def write_sheets(folder, books, picks, sheet_seqs, tear):
    """The contact sheets: two sequences' every drawing, each picked sequence's loop seam, and
    the two sequences' drawings at 3x through the draw's tear."""
    os.makedirs(folder, exist_ok=True)
    tiles = []
    for i in sheet_seqs:
        tiles += [preview(layer) for layer in books[i]]
    write_png(folder + "/sheet_frames.png", grid(tiles, 12))
    seam = []
    for i in picks:
        seam += [preview(books[i][k % DRAWINGS]) for k in range(DRAWINGS - 6, DRAWINGS + 6)]
    write_png(folder + "/sim_seam.png", grid(seam, 12))
    close = []
    for i in sheet_seqs:
        close += [preview(books[i][k], tear, 3) for k in range(0, 24, 4)]
    write_png(folder + "/sheet_tear.png", grid(close, 6))


def main():
    parser = argparse.ArgumentParser(description="Bakes the fire's drawing book (TTFSIM02).")
    parser.add_argument("--out", required=True, help="folder for fire_sim_book.bin")
    parser.add_argument("--sheets", default="", help="folder for the contact sheets (none when empty)")
    parser.add_argument("--only", default="", help="comma-separated sequence indices (sheets only, no book)")
    parser.add_argument("--sheet-seqs", default="1,6", help="the narrow and the wide sequence for sheet_frames")
    args = parser.parse_args()
    if args.only and not args.sheets:
        parser.error("--only writes only the contact sheets, so it needs --sheets")
    os.makedirs(args.out, exist_ok=True)
    picks = [int(s) for s in args.only.split(",")] if args.only else list(range(len(SEQUENCES)))
    books = {}
    start = time.perf_counter()
    for i in picks:
        t0 = time.perf_counter()
        books[i] = run_sequence(SEQUENCES[i])
        tall, wide, share, least, mass = body_stats(books[i])
        b = bounds(books[i])
        print(
            "sequence %d (width %.2f): %.1f s; body %.0f x %.0f texels (h/w %.2f), mass height %d / %.0f / %d"
            " (spread %.2f), least %d texels; bands %s; bounds area %.3f"
            % (
                i,
                SEQUENCES[i]["width"],
                time.perf_counter() - t0,
                wide,
                tall,
                tall / max(wide, 1),
                mass[0],
                mass[1],
                mass[2],
                (mass[2] - mass[0]) / max(mass[2], 1),
                least,
                np.round(share, 2),
                (b[2] - b[0]) * (b[3] - b[1]),
            )
        )
    bake_s = time.perf_counter() - start
    tear = tear_layer()
    if args.sheets:
        sheet_seqs = [int(s) for s in args.sheet_seqs.split(",") if int(s) in books] or picks[:2]
        write_sheets(args.sheets, books, picks, sheet_seqs, tear)
    if args.only:
        print("preview only: %.1f s for %d sequences" % (bake_s, len(picks)))
        return
    path = args.out + "/" + BOOK_NAME
    before = old_bounds(path)
    header = MAGIC + struct.pack("<4i", TILE_W, TILE_H, len(SEQUENCES), DRAWINGS)
    body = []
    areas = []
    for i, spec in enumerate(SEQUENCES):
        b = bounds(books[i])
        areas.append((b[2] - b[0]) * (b[3] - b[1]))
        header += struct.pack("<i4f", spec["klass"], *b)
    for i in range(len(SEQUENCES)):
        body += [layer.tobytes() for layer in books[i]]
    body.append(tear.tobytes())
    data = header + b"".join(body)
    with open(path, "wb") as fh:
        fh.write(data)
    packed = len(zlib.compress(data, 9))
    if len(before) == len(areas):
        ratio = [a / max(o, 1e-6) for a, o in zip(areas, before)]
        print("bounds area against the book it replaced: %s, mean %.3f" % (np.round(ratio, 2), np.mean(ratio)))
    print(
        "book %s: %d layers, %.2f MB raw, %.2f MB deflated, %.2f MB on the GPU with mips; bake %.1f s"
        % (path, len(SEQUENCES) * DRAWINGS + 1, len(data) / 1048576.0, packed / 1048576.0, len(data) * 4 / 3 / 1048576.0, bake_s)
    )


if __name__ == "__main__":
    sys.exit(main())
