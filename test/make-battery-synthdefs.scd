// Writes the SynthDefs of the test battery (test/web/battery.spec.mjs): for
// each class file <Name>.sc in the class folder, a SynthDef battery_<Name>
// that plays the UGen <Name> at audio rate with its default inputs to bus 0.
// Also writes battery.json, the list of the UGen names.
// Needs the classes on the class path (test/make-battery.sh does this).
//   sclang make-battery-synthdefs.scd <class folder> <out folder>
{
    var classDir = thisProcess.argv[0], outDir = thisProcess.argv[1];
    var names = PathName(classDir).files
        .select { |f| f.extension == "sc" }
        .collect { |f| f.fileNameWithoutExtension }
        .sort;
    names.do { |name|
        var class = name.asSymbol.asClass;
        if(class.isNil) { Error("no class % (from %.sc)".format(name, name)).throw };
        SynthDef(("battery_" ++ name).asSymbol, { Out.ar(0, class.ar) }).writeDefFile(outDir);
    };
    File.use(outDir +/+ "battery.json", "w", { |f|
        f.write("[" ++ names.collect { |n| "\"" ++ n ++ "\"" }.join(", ") ++ "]\n");
    });
    "battery: % SynthDefs: %".format(names.size, names.join(" ")).postln;
    0.exit;
}.try { |error|
    error.reportError;
    1.exit;
};
