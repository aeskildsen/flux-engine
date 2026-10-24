// Renders the woodbar test note in native scsynth (non-real-time mode) with
// the installed PhysWoodbar plugin. Writes nrt.wav to the folder given as the
// first argument. The note and its timing are the same as in
// native-headless-test.py.
//   sclang native-reference-render.scd <folder>
var dir = thisProcess.argv[0];
var score = [
  [0.0, ['/d_recv', SynthDef(\wb, { |out=0, freq=220, gain=0.7, gate=1| Out.ar(out, PhysWoodbar.ar(freq: freq, gain: gain, gate: gate)) }).asBytes]],
  [0.0, ['/s_new', \wb, 1000, 0, 0, \freq, 220, \gain, 0.8]],
  [2.0, ['/n_set', 1000, \gate, 0]],
  [2.5, ['/c_set', 0, 0]]
];
Score.recordNRT(score, dir +/+ "nrt.osc", dir +/+ "nrt.wav", options: ServerOptions.new.numOutputBusChannels_(2).sampleRate_(48000).numInputBusChannels_(0), duration: 2.5, headerFormat: "WAV", sampleFormat: "int24", action: { 0.exit });
