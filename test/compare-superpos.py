"""Compares the SuperPos renders.

1. sp.wav (SuperPos in native scsynth) with sp_grainbuf.wav (the same cloud
   made of Impulse, Phasor and GrainBuf in native scsynth). Both start at
   frame 0, so they are compared frame by frame, without alignment.
2. supersonic.wav (SuperPos in headless SuperSonic) with sp.wav. The
   SuperSonic recording starts with silence, so both files are aligned at
   their first non-zero frame.

The limit for both is MAX_DIFF over FRAMES frames, and the cloud must be
loud enough (EXPECTED_MIN_PEAK) so that a silent pair does not pass.

Usage: compare-superpos.py <sp.wav> <sp_grainbuf.wav> <supersonic.wav>
Exit status 0 when all checks pass.
"""
import struct
import sys

import numpy as np

FRAMES = 48000
MAX_DIFF = 1e-5
EXPECTED_MIN_PEAK = 0.2


def read_wav(path):
    """The first channel of a WAV file (PCM 16, 24, 32 bit or IEEE float 32
    bit) as float64, and the sample rate."""
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
    return a.reshape(-1, channels)[:, 0], rate


def first_nonzero(a):
    nz = np.nonzero(np.abs(a) > 1e-6)[0]
    return int(nz[0]) if len(nz) else None


failures = []


def compare(name, a, b):
    n = min(len(a), len(b), FRAMES)
    if n < FRAMES:
        failures.append(f"{name}: only {n} frames to compare")
    diff = np.abs(a[:n] - b[:n])
    worst = float(diff.max()) if n else float("inf")
    print(f"{name}: largest sample difference over {n} frames: {worst:.2e} (at frame {int(diff.argmax()) if n else -1})")
    if not worst < MAX_DIFF:
        failures.append(f"{name}: largest difference {worst:.2e}, limit {MAX_DIFF:.0e}")


sp, sr_sp = read_wav(sys.argv[1])
ref, sr_ref = read_wav(sys.argv[2])
live, sr_live = read_wav(sys.argv[3])
for name, a, sr in (("sp", sp, sr_sp), ("sp_grainbuf", ref, sr_ref), ("supersonic", live, sr_live)):
    peak = float(np.abs(a).max()) if len(a) else 0.0
    print(f"{name}: {len(a)} frames, {sr} Hz, peak {peak:.3f}, first non-zero frame {first_nonzero(a)}")
    if sr != 48000:
        failures.append(f"{name}: sample rate {sr}, expected 48000")
    if peak < EXPECTED_MIN_PEAK:
        failures.append(f"{name}: peak {peak:.3f}, expected at least {EXPECTED_MIN_PEAK}")

compare("SuperPos against GrainBuf (scsynth)", sp, ref)

nz_live, nz_sp = first_nonzero(live), first_nonzero(sp)
if nz_live is None or nz_sp is None:
    failures.append("no non-zero frame to align SuperSonic with scsynth")
else:
    compare("SuperSonic against scsynth (SuperPos)", live[nz_live:], sp[nz_sp:])

for f in failures:
    print("FAIL:", f)
if failures:
    sys.exit(1)
print("OK: the renders match")
