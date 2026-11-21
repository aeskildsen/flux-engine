// The IsoSuperPos test SynthDefs, for test/native-superpos.sh and the web test.
//
// sp:          IsoSuperPos, stereo, to buses `out` and `out` + 1, without its
//              level control (normalize 0), so that it is the plain sum of
//              the grains, as GrainBuf.
// sp_grainbuf: the same cloud made of SuperCollider's own UGens (Impulse,
//              Phasor, GrainBuf with two channels). IsoSuperPos must give the
//              same output in both channels, bit for bit. The trigger rate is
//              overlap / grainDur, a float division, as in IsoSuperPos;
//              grainDur.reciprocal is an approximation on x86.
// sp_live:     IsoSuperPosLive on a sine that is 440 Hz for 1 s and 880 Hz
//              after, recorded into buffer `buf` (1 s), the grains 0.1 s
//              behind the record head. Freeze goes on at `freezeAt` seconds
//              (the default, 100, is never in a test).
// sp_seeded:   IsoSuperPos with random timing, detune, scatter and spread, after
//              RandSeed with `seed`, so that a seed gives the same render.
//              maxGrains sets the pool size.
//
// The arguments have the values of the test as defaults. amp keeps the
// peak below 1: the recording of SuperSonic clips at full scale. The other scripts
// load this file with executeFile; make-superpos-synthdefs.scd writes the
// SynthDef files.
~superposDefs = [
    SynthDef(\sp, { |out = 0, buf = 0, pointerRate = 0.5, grainDur = 0.05, overlap = 4, transpose = 7, amp = 0.5|
        Out.ar(out, IsoSuperPos.ar(buf, pointerRate, grainDur, overlap, transpose, normalize: 0) * amp);
    }),
    SynthDef(\sp_grainbuf, { |out = 0, buf = 0, pointerRate = 0.5, grainDur = 0.05, overlap = 4, transpose = 7, amp = 0.5|
        var frames = BufFrames.kr(buf);
        var trig = Impulse.ar(overlap / grainDur);
        var pos = Phasor.ar(0, pointerRate * BufRateScale.kr(buf), 0, frames) / frames;
        // IsoSuperPos has 64 grains; GrainBuf starts no grain when 64 are
        // active, so it needs 65.
        Out.ar(out, GrainBuf.ar(2, trig, grainDur, buf, transpose.midiratio, pos, 2, 0, -1, 65) * amp);
    }),
    SynthDef(\sp_live, { |out = 0, buf = 1, freezeAt = 100, position = 0.1, grainDur = 0.05, overlap = 4, amp = 0.5|
        var in = SinOsc.ar(Env.step([440, 880], [1, 1]).kr);
        var freeze = Sweep.kr(0, 1) >= freezeAt;
        Out.ar(out, IsoSuperPosLive.ar(in, buf, freeze, position, grainDur, overlap, normalize: 0) * amp);
    }),
    SynthDef(\sp_seeded, { |out = 0, buf = 0, seed = 1, overlap = 4, maxGrains = 64, amp = 0.5|
        RandSeed.ir(1, seed);
        Out.ar(out, IsoSuperPos.ar(buf, 0.5, 0.03, overlap, 0, regularity: 1, detuneStep: 0.5, scatter: 0.05,
            stereoSpread: 0.5, normalize: 0, maxGrains: maxGrains) * amp);
    })
];

// The live record buffer: 1 s, mono, at 48 kHz.
~superposLiveFrames = 48000;

// The test buffer: 30000 frames, a sum of sines made by /b_gen sine1 (flags 5:
// normalise and clear). The same commands fill it in every engine. The length
// is not a power of two, so 1 / frames is not exact in float, and the
// comparison with GrainBuf checks that IsoSuperPos rounds as `Phasor / BufFrames`.
~superposBufferFrames = 30000;
~superposPartials = [1, 0.5, 0.8, 0.25, 0.6, 0.1, 0.45, 0.3, 0.05, 0.35, 0.2, 0.15];

