// Writes the MiPlaits test SynthDef (plaits_test.scsyndef) to the folder given as
// the first argument. Needs the MiPlaits class on the class path. pitch is a
// MIDI note, as the UGen takes it; no trigger and no level input, so the
// Plaits low-pass gate is bypassed and every engine sounds continuously.
//   sclang make-plaits-synthdef.scd <folder>
SynthDef(\plaits_test, { |out=0, pitch=60, engine=0, harm=0.5, timbre=0.5, morph=0.5, amp=0.3|
    Out.ar(out, MiPlaits.ar(pitch, engine, harm, timbre, morph) * amp);
}).writeDefFile(thisProcess.argv[0]);
0.exit;
