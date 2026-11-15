"""Compares the SuperPos renders of native-superpos.sh, in the folder given as
the argument.

1. SuperPos against the same cloud made of Impulse, Phasor and GrainBuf, in
   native scsynth: sp.wav with sp_grainbuf.wav, sp_03.wav with
   sp_grainbuf_03.wav (grainDur 0.03), and sp_o3.wav with sp_grainbuf_o3.wav
   (overlap 3, grainDur 0.027). They must be the same, bit for bit, over the
   whole render.
2. supersonic.wav (SuperPos in headless SuperSonic, 24-bit) against sp.wav.
   The SuperSonic recording starts with silence, so both are aligned at their
   first non-zero frame. The limit is two steps of a 24-bit sample.
3. sp_v1.wav: a SynthDef from the first SuperPos class file (one output).
   SuperPos must refuse it: the render is complete and silent, and
   render.log has the message of SuperPos (a silent render alone would also
   come from a SynthDef that did not load).
4. sp_seeded with RandSeed: seed 1 twice gives the same render; seed 2 gives
   a different one.
5. maxGrains through the UGen: with a pool of 1 at overlap 8, one grain
   sounds at a time, so the peak is at most that of one grain
   (ONE_GRAIN_PEAK); with a pool of 64 it is much higher.

All files must have two channels at 48 kHz. Exit status 0 when all checks
pass.

Usage: compare-superpos.py <folder>
"""
import math
import os
import struct
import sys

import numpy as np

RATE = 48000
CHANNELS = 2
# Each render is 2 s. The synths stop at 1.99 s, which scsynth applies at the
# block boundary before it; SuperSonic plays on. The SuperSonic comparison
# stops at 1.9 s.
RENDER_FRAMES = 2 * RATE
PLAY_FRAMES = int(1.9 * RATE)
EXPECTED_MIN_PEAK = 0.2
SUPERSONIC_MAX_DIFF = 2.0 / 8388608.0
# amp 0.5, a buffer peak of 1, and the largest pan gain: pan up to +-0.5
# (stereoSpread 0.5) gives up to cos(pi / 8) in one channel.
ONE_GRAIN_PEAK = 0.5 * math.cos(math.pi / 8)


def read_wav(path):
    """The frames of a WAV file (PCM 16, 24, 32 bit or IEEE float 32 bit) as
    float64, shape (frames, channels), and the sample rate."""
    data = open(path, "rb").read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        sys.exit(f"FAIL: {path} is not a WAV file")
    pos, fmt, samples = 12, None, None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            tag, channels, rate = struct.unpack("<HHI", body[:8])
            bits = struct.unpack("<H", body[14:16])[0]
            if tag == 0xFFFE:  # WAVE_FORMAT_EXTENSIBLE: the real tag is in the subformat
                tag = struct.unpack("<H", body[24:26])[0]
            fmt = (tag, channels, rate, bits)
        elif cid == b"data":
            samples = body
        pos += 8 + size + (size & 1)
    if fmt is None or samples is None:
        sys.exit(f"FAIL: {path} has no fmt or data chunk")
    tag, channels, rate, bits = fmt
    if tag == 3 and bits == 32:
        a = np.frombuffer(samples, "<f4").astype(np.float64)
    elif tag == 1 and bits == 16:
        a = np.frombuffer(samples, "<i2") / 32768.0
    elif tag == 1 and bits == 24:
        b = np.frombuffer(samples, np.uint8).reshape(-1, 3).astype(np.int32)
        a = ((b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)) << 8 >> 8) / 8388608.0
    elif tag == 1 and bits == 32:
        a = np.frombuffer(samples, "<i4") / 2.0**31
    else:
        sys.exit(f"FAIL: {path}: WAV format {tag} with {bits} bits is not supported")
    return a.reshape(-1, channels), rate


def first_nonzero(a):
    nz = np.nonzero(np.abs(a).max(axis=1) > 1e-6)[0]
    return int(nz[0]) if len(nz) else None


failures = []
folder = sys.argv[1]


def load(name):
    a, rate = read_wav(os.path.join(folder, name + ".wav"))
    peak = float(np.abs(a).max()) if len(a) else 0.0
    print(f"{name}: {len(a)} frames, {a.shape[1]} channels, {rate} Hz, peak {peak:.4f}, "
          f"first non-zero frame {first_nonzero(a)}")
    if a.shape[1] != CHANNELS:
        failures.append(f"{name}: {a.shape[1]} channels, expected {CHANNELS}")
    if rate != RATE:
        failures.append(f"{name}: sample rate {rate}, expected {RATE}")
    if len(a) < RENDER_FRAMES:
        failures.append(f"{name}: {len(a)} frames, expected {RENDER_FRAMES} (did scsynth stop early?)")
    return a, peak


def largest_difference(name, a, b, n):
    diff = np.abs(a[:n] - b[:n]).max(axis=1)
    worst = float(diff.max()) if n else float("inf")
    print(f"{name}: largest sample difference over {n} frames, both channels: {worst:.2e} "
          f"(at frame {int(diff.argmax()) if n else -1})")
    return worst


# 1. SuperPos against GrainBuf, bit for bit.
for sp_name, ref_name in (("sp", "sp_grainbuf"), ("sp_03", "sp_grainbuf_03"), ("sp_o3", "sp_grainbuf_o3")):
    sp, sp_peak = load(sp_name)
    ref, ref_peak = load(ref_name)
    if sp_peak < EXPECTED_MIN_PEAK:
        failures.append(f"{sp_name}: peak {sp_peak:.3f}, expected at least {EXPECTED_MIN_PEAK}")
    n = min(len(sp), len(ref))
    worst = largest_difference(f"{sp_name} against {ref_name} (scsynth)", sp, ref, n)
    if worst != 0.0:
        failures.append(f"{sp_name} against {ref_name}: largest difference {worst:.2e}, expected 0")

# 2. SuperSonic against scsynth.
sp, _ = load("sp")
live, live_peak = load("supersonic")
nz_live, nz_sp = first_nonzero(live), first_nonzero(sp)
if nz_live is None or nz_sp is None:
    failures.append("no non-zero frame to align SuperSonic with scsynth")
else:
    n = min(len(live) - nz_live, PLAY_FRAMES - nz_sp)
    if n < RATE:
        failures.append(f"SuperSonic against scsynth: only {n} frames to compare")
    worst = largest_difference("SuperSonic against scsynth (SuperPos)", live[nz_live:], sp[nz_sp:], n)
    if not worst <= SUPERSONIC_MAX_DIFF:
        failures.append(f"SuperSonic against scsynth: largest difference {worst:.2e}, "
                        f"limit {SUPERSONIC_MAX_DIFF:.2e}")

# 3. The SynthDef with one output.
_, v1_peak = load("sp_v1")
if v1_peak != 0.0:
    failures.append(f"sp_v1: peak {v1_peak:.3f}, expected silence")
log = open(os.path.join(folder, "render.log"), errors="replace").read()
if "SuperPos: the SynthDef has a SuperPos UGen with 1 outputs" not in log:
    failures.append("sp_v1: render.log has no message from SuperPos about the outputs (did the SynthDef load?)")
else:
    print("sp_v1: SuperPos refused the SynthDef with one output (message in render.log)")

# 4. RandSeed.
seed1a, peak1 = load("sp_seed1a")
seed1b, _ = load("sp_seed1b")
seed2, _ = load("sp_seed2")
if peak1 < EXPECTED_MIN_PEAK / 2:
    failures.append(f"sp_seed1a: peak {peak1:.3f}, expected at least {EXPECTED_MIN_PEAK / 2}")
same = largest_difference("seed 1 against seed 1", seed1a, seed1b, min(len(seed1a), len(seed1b)))
if same != 0.0:
    failures.append(f"RandSeed: two renders with seed 1 differ by {same:.2e}")
other = largest_difference("seed 1 against seed 2", seed1a, seed2, min(len(seed1a), len(seed2)))
if not other > 0.01:
    failures.append(f"RandSeed: seed 1 and seed 2 differ by only {other:.2e}")

# 5. maxGrains.
_, pool1 = load("sp_pool1")
_, pool64 = load("sp_pool64")
print(f"maxGrains: peak {pool1:.4f} with 1 grain (limit {ONE_GRAIN_PEAK:.4f}), {pool64:.4f} with 64")
if not (0.1 < pool1 <= ONE_GRAIN_PEAK * 1.0001):
    failures.append(f"sp_pool1: peak {pool1:.4f}, expected above 0.1 and at most {ONE_GRAIN_PEAK:.4f}")
if not pool64 > 2 * pool1:
    failures.append(f"sp_pool64: peak {pool64:.4f}, expected more than twice the peak with 1 grain")

for f in failures:
    print("FAIL:", f)
if failures:
    sys.exit(1)
print("OK: the renders match")
