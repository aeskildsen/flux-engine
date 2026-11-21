// Renders the IsoSuperPos tests in native scsynth (non-real-time mode), 2 s each,
// stereo, 32-bit float, into the folder given as the first argument:
//   sp.wav, sp_grainbuf.wav        IsoSuperPos and the same cloud with GrainBuf
//   sp_03.wav, sp_grainbuf_03.wav  the same at grainDur 0.03
//   sp_o3.wav, sp_grainbuf_o3.wav  the same at overlap 3, grainDur 0.027:
//                                  overlap 4 is a power of two, so
//                                  overlap * (1 / grainDur) would be exact
//                                  there too, and only an overlap like 3
//                                  shows the float division
//   sp_v1.wav                      the IsoSuperPos SynthDef of the first class
//                                  file (one output, assets/sp_v1.scsyndef)
//   sp_seed1a.wav, sp_seed1b.wav, sp_seed2.wav
//                                  sp_seeded with seed 1 (twice) and seed 2
//   sp_pool1.wav, sp_pool64.wav    sp_seeded at overlap 8 with a pool of 1
//                                  and of 64 grains
//   sp_live_open.wav, sp_live_frozen.wav
//                                  IsoSuperPosLive (see renderLive)
// UGEN_PLUGINS_PATH (folders separated by ":") is the plugin path of scsynth.
//   sclang native-superpos-render.scd <folder>
var dir = thisProcess.argv[0];
var here = thisProcess.nowExecutingPath.dirname;
var pluginsPath = "UGEN_PLUGINS_PATH".getenv;
var options, render, renderLive, jobs, next;
this.executeFile(here +/+ "superpos-synthdefs.scd");
options = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).sampleRate_(48000).ugenPluginsPath_(pluginsPath);
// One render of SynthDef `defName` with the arguments `args`. `load` is the
// command that gives the server the SynthDef. The synth stops before the
// end: scsynth 3.14.1 can crash at the end of a non-real-time render while a
// grain UGen still runs.
render = { |load, defName, name, args, next|
    var score = [
        [0.0, ['/b_alloc', 0, ~superposBufferFrames, 1]],
        [0.0, ['/b_gen', 0, "sine1", 5] ++ ~superposPartials],
        [0.0, load],
        [0.0, ['/s_new', defName, 1000, 0, 0, \buf, 0] ++ args],
        [1.99, ['/n_free', 1000]],
        [2.0, ['/c_set', 0, 0]]
    ];
    Score.recordNRT(score, dir +/+ name ++ ".osc", dir +/+ name ++ ".wav", options: options, duration: 2.0,
        headerFormat: "WAV", sampleFormat: "float", action: next);
};
// IsoSuperPosLive, 2 s: open (sp_live_open.wav) and frozen at 0.5 s
// (sp_live_frozen.wav).
renderLive = { |name, freezeAt, next|
    var score = [
        [0.0, ['/b_alloc', 1, ~superposLiveFrames, 1]],
        [0.0, ['/d_recv', ~superposDefs[2].asBytes]],
        [0.0, ['/s_new', \sp_live, 1000, 0, 0, \buf, 1, \freezeAt, freezeAt]],
        [1.99, ['/n_free', 1000]],
        [2.0, ['/c_set', 0, 0]]
    ];
    Score.recordNRT(score, dir +/+ name ++ ".osc", dir +/+ name ++ ".wav", options: options, duration: 2.0,
        headerFormat: "WAV", sampleFormat: "float", action: next);
};
jobs = [
    { |n| render.(['/d_recv', ~superposDefs[0].asBytes], \sp, "sp", [], n) },
    { |n| render.(['/d_recv', ~superposDefs[1].asBytes], \sp_grainbuf, "sp_grainbuf", [], n) },
    { |n| render.(['/d_recv', ~superposDefs[0].asBytes], \sp, "sp_03", [\grainDur, 0.03], n) },
    { |n| render.(['/d_recv', ~superposDefs[1].asBytes], \sp_grainbuf, "sp_grainbuf_03", [\grainDur, 0.03], n) },
    { |n| render.(['/d_recv', ~superposDefs[0].asBytes], \sp, "sp_o3", [\overlap, 3, \grainDur, 0.027], n) },
    { |n| render.(['/d_recv', ~superposDefs[1].asBytes], \sp_grainbuf, "sp_grainbuf_o3", [\overlap, 3, \grainDur, 0.027], n) },
    { |n| render.(['/d_load', here +/+ "assets/sp_v1.scsyndef"], \sp, "sp_v1", [], n) },
    { |n| render.(['/d_recv', ~superposDefs[3].asBytes], \sp_seeded, "sp_seed1a", [\seed, 1], n) },
    { |n| render.(['/d_recv', ~superposDefs[3].asBytes], \sp_seeded, "sp_seed1b", [\seed, 1], n) },
    { |n| render.(['/d_recv', ~superposDefs[3].asBytes], \sp_seeded, "sp_seed2", [\seed, 2], n) },
    { |n| render.(['/d_recv', ~superposDefs[3].asBytes], \sp_seeded, "sp_pool1", [\overlap, 8, \maxGrains, 1], n) },
    { |n| render.(['/d_recv', ~superposDefs[3].asBytes], \sp_seeded, "sp_pool64", [\overlap, 8, \maxGrains, 64], n) },
    { |n| renderLive.("sp_live_open", 100, n) },
    { |n| renderLive.("sp_live_frozen", 0.5, n) }
];
// Runs the jobs one after the other, then exits.
next = { |i| if(i < jobs.size) { jobs[i].({ next.(i + 1) }) } { 0.exit } };
next.(0);
