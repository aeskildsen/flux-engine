// Renders the SuperPos test in native scsynth (non-real-time mode): sp.wav
// with SuperPos and sp_grainbuf.wav with GrainBuf, both 2 s, stereo, 32-bit
// float. Writes into the folder given as the first argument.
// UGEN_PLUGINS_PATH (folders separated by ":") is the plugin path of scsynth.
//   sclang native-superpos-render.scd <folder>
var dir = thisProcess.argv[0];
var pluginsPath = "UGEN_PLUGINS_PATH".getenv;
var options, render;
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
render.(~superposDefs[0], "sp", {
    render.(~superposDefs[1], "sp_grainbuf", { 0.exit });
});
