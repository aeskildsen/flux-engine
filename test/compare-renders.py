"""Compares the SuperSonic recording of the woodbar note with the native
scsynth reference render.

Both files are aligned at their first non-zero frame (the SuperSonic
recording starts with about 1 s of silence). Checks: the same peak and the
same spectral peak in both, and a largest sample difference below 1e-6 over
48000 frames. The reference is 24-bit, so its rounding alone gives up to
6e-8; a matching render differs by about 8.3e-7.

Usage: compare-renders.py <supersonic.wav> <reference.wav>
Exit status 0 when all checks pass.
"""
import sys

import numpy as np

from analyse_wav import load_any, first_nonzero, spectral_peak

FRAMES = 48000
MAX_DIFF = 1e-6
EXPECTED_PEAK = 0.305
EXPECTED_SPECTRAL_PEAK_HZ = 858.4

results = []
for p in sys.argv[1:3]:
    a, sr = load_any(p)
    nz = first_nonzero(a)
    if nz is None:
        sys.exit(f"FAIL: {p} is silent")
    peak = abs(a).max()
    fpeak = spectral_peak(a, sr, nz)
    print(f"{p}: {a.shape[0]} frames, {sr} Hz, peak {peak:.3f}, first non-zero frame {nz}, spectral peak {fpeak:.1f} Hz")
    results.append((a[nz:nz+FRAMES], sr, peak, fpeak))

(a, sr_a, peak_a, f_a), (b, sr_b, peak_b, f_b) = results
n = min(len(a), len(b), FRAMES)
diff = abs(a[:n] - b[:n]).max()
print(f"largest sample difference over {n} frames: {diff:.2e}")

failures = []
if sr_a != sr_b: failures.append(f"sample rates differ: {sr_a}, {sr_b}")
if n < FRAMES: failures.append(f"only {n} frames to compare")
for name, peak in (("SuperSonic", peak_a), ("reference", peak_b)):
    if round(peak, 3) != EXPECTED_PEAK: failures.append(f"{name} peak {peak:.3f}, expected {EXPECTED_PEAK}")
for name, f in (("SuperSonic", f_a), ("reference", f_b)):
    if round(f, 1) != EXPECTED_SPECTRAL_PEAK_HZ: failures.append(f"{name} spectral peak {f:.1f} Hz, expected {EXPECTED_SPECTRAL_PEAK_HZ}")
if diff >= MAX_DIFF: failures.append(f"largest difference {diff:.2e}, limit {MAX_DIFF:.0e}")

for f in failures: print("FAIL:", f)
if failures: sys.exit(1)
print("OK: the renders match")
