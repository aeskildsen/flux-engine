"""Checks the IsoSuperPosLive renders (native-superpos-render.scd).

The input is a sine at 440 Hz for 1 s and 880 Hz after. The grains play the
input 0.1 s behind the record head. So:

- sp_live_open.wav (the recording goes on): the energy is near 440 Hz from
  0.6 to 0.95 s and near 880 Hz from 1.5 to 2.0 s: the output follows the
  input;
- sp_live_frozen.wav (freeze at 0.5 s): the energy is near 440 Hz in both
  windows, with the same level: the frozen buffer repeats.

The energy is measured in bands, not as the frequency of one peak: with
freeze, each grain reads the same frames, so the output repeats with the
grain interval (12.5 ms) and its spectrum has peaks at multiples of 80 Hz
near 440 Hz, not at 440 Hz.

Both files must be finite, loud enough, and have equal channels (pan 0).

Usage: compare-superpos-live.py <sp_live_open.wav> <sp_live_frozen.wav>
Exit status 0 when all checks pass.
"""
import pathlib
import sys

import numpy as np

# read_wav() of compare-superpos.py. That script runs its checks when it is
# loaded, so only the part before the checks is run here.
_source = pathlib.Path(__file__).with_name("compare-superpos.py").read_text().split("\nfailures = []")[0]
_namespace = {}
exec(_source, _namespace)
read_wav = _namespace["read_wav"]

RATE = 48000
MIN_PEAK = 0.1
# The bands around the two input frequencies (Hz), and how much more energy
# the expected band must have than the other.
BANDS = {440: (340.0, 540.0), 880: (780.0, 980.0)}
MIN_BAND_RATIO_DB = 20.0
# The largest level change of the frozen output between the two windows.
MAX_FROZEN_LEVEL_CHANGE_DB = 1.0
WINDOWS = ((0.6, 0.95), (1.5, 2.0))
EXPECTED = {"open": (440, 880), "frozen": (440, 440)}

failures = []


def band_energy(a, start, end):
    """The energy in each band of BANDS, with a Hann window, in dB."""
    x = a[int(start * RATE):int(end * RATE)]
    power = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    return {f: 10 * np.log10(power[(freqs >= lo) & (freqs <= hi)].sum() + 1e-30)
            for f, (lo, hi) in BANDS.items()}


def rms_db(a, start, end):
    x = a[int(start * RATE):int(end * RATE)]
    return 10 * np.log10((x ** 2).mean() + 1e-30)


for name, path in (("open", sys.argv[1]), ("frozen", sys.argv[2])):
    a, rate = read_wav(path)
    if rate != RATE or a.shape[1] != 2:
        failures.append(f"{name}: {rate} Hz, {a.shape[1]} channels; expected {RATE} Hz, 2 channels")
        continue
    peak = float(np.abs(a).max())
    finite = bool(np.isfinite(a).all())
    same = float(np.abs(a[:, 0] - a[:, 1]).max())
    print(f"{name}: peak {peak:.3f}, finite {finite}, left - right {same:.2e}")
    if not finite or peak < MIN_PEAK or same != 0.0:
        failures.append(f"{name}: peak {peak:.3f} (at least {MIN_PEAK}), finite {finite}, left - right {same:.2e}")
    for (start, end), expected in zip(WINDOWS, EXPECTED[name]):
        energy = band_energy(a[:, 0], start, end)
        other = 880 if expected == 440 else 440
        ratio = energy[expected] - energy[other]
        print(f"{name}: {start}-{end} s: the {expected} Hz band is {ratio:.1f} dB above the {other} Hz band")
        if ratio < MIN_BAND_RATIO_DB:
            failures.append(f"{name}: {start}-{end} s: {expected} Hz band only {ratio:.1f} dB above {other} Hz")
    if name == "frozen":
        change = rms_db(a[:, 0], *WINDOWS[1]) - rms_db(a[:, 0], *WINDOWS[0])
        print(f"frozen: level change from the first to the second window {change:+.2f} dB")
        if abs(change) > MAX_FROZEN_LEVEL_CHANGE_DB:
            failures.append(f"frozen: the level changes by {change:+.2f} dB")

for f in failures:
    print("FAIL:", f)
if failures:
    sys.exit(1)
print("OK: the live renders follow the input, and freeze keeps it")
