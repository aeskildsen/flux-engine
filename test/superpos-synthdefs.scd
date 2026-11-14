// The SuperPos test SynthDefs, for test/native-superpos.sh and the web test.
//
// sp:          SuperPos, mono, to bus `out`.
// sp_grainbuf: the same cloud made of SuperCollider's own UGens (Impulse,
//              Phasor, GrainBuf). SuperPos must give the same output.
//
// The arguments have the values of the test as defaults. amp keeps the
// peak below 1: the recording of SuperSonic clips at full scale. The other scripts
// load this file with executeFile; make-superpos-synthdefs.scd writes the
// SynthDef files.
~superposDefs = [
    SynthDef(\sp, { |out = 0, buf = 0, pointerRate = 0.5, grainDur = 0.05, overlap = 4, transpose = 7, amp = 0.5|
        Out.ar(out, SuperPos.ar(buf, pointerRate, grainDur, overlap, transpose) * amp);
    }),
    SynthDef(\sp_grainbuf, { |out = 0, buf = 0, pointerRate = 0.5, grainDur = 0.05, overlap = 4, transpose = 7, amp = 0.5|
        var frames = BufFrames.kr(buf);
        var trig = Impulse.ar(overlap * grainDur.reciprocal);
        var pos = Phasor.ar(0, pointerRate * BufRateScale.kr(buf), 0, frames) / frames;
        // SuperPos has 64 grains; GrainBuf starts no grain when 64 are
        // active, so it needs 65.
        Out.ar(out, GrainBuf.ar(1, trig, grainDur, buf, transpose.midiratio, pos, 2, 0, -1, 65) * amp);
    })
];

// The test buffer: 8192 frames, a sum of sines made by /b_gen sine1 (flags 5:
// normalise and clear). The same commands fill it in every engine.
~superposBufferFrames = 8192;
~superposPartials = [1, 0.5, 0.8, 0.25, 0.6, 0.1, 0.45, 0.3, 0.05, 0.35, 0.2, 0.15];

