// Writes the SuperPos test SynthDefs (sp.scsyndef, sp_grainbuf.scsyndef) to
// the folder given as the first argument. Needs the SuperPos class.
//   sclang make-superpos-synthdefs.scd <folder>
this.executeFile(thisProcess.nowExecutingPath.dirname +/+ "superpos-synthdefs.scd");
~superposDefs.do { |def| def.writeDefFile(thisProcess.argv[0]) };
0.exit;
