// Writes the woodbar test SynthDef (wb.scsyndef) to the folder given as the
// first argument. Needs the PhysWoodbar class on the class path.
//   sclang make-synthdef.scd <folder>
SynthDef(\wb, { |out=0, freq=220, gain=0.7, gate=1|
    var sig = PhysWoodbar.ar(freq: freq, gain: gain, gate: gate);
    Out.ar(out, sig);
}).writeDefFile(thisProcess.argv[0]);
0.exit;
