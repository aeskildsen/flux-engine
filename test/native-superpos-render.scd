// Renders the SuperPos tests in native scsynth (non-real-time mode): sp.wav
// with SuperPos and sp_grainbuf.wav with GrainBuf, both 2 s, stereo, 32-bit
// float; and the SuperPosLive renders (see renderLive). Writes into the
// folder given as the first argument.
// UGEN_PLUGINS_PATH (folders separated by ":") is the plugin path of scsynth.
//   sclang native-superpos-render.scd <folder>
var dir = thisProcess.argv[0];
var pluginsPath = "UGEN_PLUGINS_PATH".getenv;
var options, render, renderLive;
this.executeFile(thisProcess.nowExecutingPath.dirname +/+ "superpos-synthdefs.scd");
options = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).sampleRate_(48000).ugenPluginsPath_(pluginsPath);
render = { |def, name, next|
    var score = [
        [0.0, ['/b_alloc', 0, ~superposBufferFrames, 1]],
        [0.0, ['/b_gen', 0, "sine1", 5] ++ ~superposPartials],
        [0.0, ['/d_recv', def.asBytes]],
        [0.0, ['/s_new', def.name, 1000, 0, 0, \buf, 0]],
        [2.0, ['/c_set', 0, 0]]
    ];
    Score.recordNRT(score, dir +/+ name ++ ".osc", dir +/+ name ++ ".wav", options: options, duration: 2.0,
        headerFormat: "WAV", sampleFormat: "float", action: next);
};
// SuperPosLive, 2 s: open (sp_live_open.wav) and frozen at 0.5 s
// (sp_live_frozen.wav). The synths stop before the end: scsynth 3.14.1 can
// crash at the end of a non-real-time render while a grain UGen still runs.
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
render.(~superposDefs[0], "sp", {
    render.(~superposDefs[1], "sp_grainbuf", {
        renderLive.("sp_live_open", 100, {
            renderLive.("sp_live_frozen", 0.5, { 0.exit });
        });
    });
});
