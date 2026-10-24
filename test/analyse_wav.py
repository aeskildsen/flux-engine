"""Peak, RMS, first non-zero frame and spectral peak of WAV files.

Usage: analyse_wav.py <file.wav> ...
Also writes <file.wav>.npy: 48000 frames from the first non-zero frame.
"""
import sys
import wave

import numpy as np


def load(p):
    w = wave.open(p); n = w.getnframes(); ch = w.getnchannels(); sw = w.getsampwidth(); raw = w.readframes(n)
    if sw == 2: a = np.frombuffer(raw, np.int16).astype(float) / 32768
    elif sw == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3); a = ((b[:,0].astype(np.int32)|(b[:,1].astype(np.int32)<<8)|(b[:,2].astype(np.int32)<<16))<<8>>8)/8388608.0
    elif sw == 4: a = np.frombuffer(raw, np.int32).astype(float) / 2**31
    return a.reshape(-1, ch), w.getframerate()


def load_any(p):
    try: return load(p)
    except Exception:
        import soundfile as sf
        return sf.read(p)


def first_nonzero(a):
    nz = np.nonzero(abs(a[:,0]) > 1e-4)[0]
    return nz[0] if len(nz) else None


def spectral_peak(a, sr, start):
    seg = a[start:start+16384, 0] if start is not None else a[:16384,0]
    sp = abs(np.fft.rfft(seg * np.hanning(len(seg)))); f = np.fft.rfftfreq(len(seg), 1/sr)
    return f[sp.argmax()]


def main():
    for p in sys.argv[1:]:
        a, sr = load_any(p)
        print(p.split('/')[-1], a.shape, sr, "peak %.3f rms %.4f" % (abs(a).max(), (a**2).mean()**.5))
        nz = first_nonzero(a); print(" first nonzero", nz)
        print(" spectral peak Hz %.1f" % spectral_peak(a, sr, nz))
        if nz is not None: np.save(p + ".npy", a[nz:nz+48000])


if __name__ == "__main__":
    main()
