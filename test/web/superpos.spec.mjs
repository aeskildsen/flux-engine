/**
 * SuperPos (isospin) in the web engine, in SAB and in postMessage mode.
 *
 * test/assets/sp.scsyndef is the SuperPos test SynthDef (made by
 * test/make-superpos-synthdefs.scd; test/native-superpos.sh checks that the
 * fixture is the same as the SynthDef that the class makes). The test fills
 * the test buffer as superpos-synthdefs.scd does (/b_alloc, then /b_gen
 * sine1), plays the cloud and checks that the output is a finite sound of
 * the expected level. The native test compares the sound itself with
 * scsynth.
 *
 * The output is observed with an AnalyserNode on the engine's output node, as
 * in woodbar.spec.mjs. The test reads for 1 s: the cloud starts at once.
 */

import { test as base, expect } from "@playwright/test";

// The same values as ~superposBufferFrames and ~superposPartials in
// test/superpos-synthdefs.scd.
const BUFFER_FRAMES = 8192;
const PARTIALS = [1, 0.5, 0.8, 0.25, 0.6, 0.1, 0.45, 0.3, 0.05, 0.35, 0.2, 0.15];

const test = base.extend({
  sonicMode: async ({}, use, testInfo) => {
    await use(testInfo.project.use.supersonicMode);
  },
  sonicConfig: async ({ sonicMode }, use) => {
    await use({
      baseURL: "/dist/",
      workerBaseURL: "/dist/workers/",
      wasmBaseURL: "/dist/wasm/",
      wasmUrl: "/dist/wasm/clockwork-scsynth.wasm",
      synthdefBaseURL: "/dist/synthdefs/",
      sampleBaseURL: "/dist/samples/",
      snapshotIntervalMs: 25,
      mode: sonicMode,
    });
  },
  harness: async ({ page }, use) => {
    const errors = [];
    page.on("pageerror", (err) => errors.push(err.message));
    await page.goto("/harness.html");
    await page.waitForFunction(() => window.supersonicReady === true);
    await use(page);
    expect(errors).toEqual([]);
  },
});

test("SuperPos plays a cloud from a buffer at the output node", async ({ harness, sonicConfig }) => {
  const result = await harness.evaluate(
    async ({ config, frames, partials }) => {
      const sonic = new window.SuperSonic(config);
      window.fails = [];
      sonic.on("in", (msg) => { if (msg[0] === "/fail") window.fails.push(msg); });
      await sonic.init();
      await sonic.loadSynthDef("/assets/sp.scsyndef");

      // The test buffer. /b_gen reads the amplitudes as floats; it also
      // takes the integer 1 as a number.
      await sonic.allocSample(0, frames, 1);
      await sonic.request("/b_gen", [0, "sine1", 5, ...partials],
                          { reply: "/done", match: (m) => m[1] === "/b_gen" });

      const ctx = sonic.node.context;
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 2048;
      sonic.node.connect(analyser);
      const buf = new Float32Array(analyser.fftSize);

      await sonic.send("/s_new", "sp", 1000, 0, 0, "buf", 0);

      // Read the analyser every 20 ms for 1 s.
      let peak = 0, finite = true, reads = 0;
      const t0 = performance.now();
      while (performance.now() - t0 < 1000) {
        analyser.getFloatTimeDomainData(buf);
        for (const v of buf) {
          if (!Number.isFinite(v)) finite = false;
          else peak = Math.max(peak, Math.abs(v));
        }
        reads++;
        await new Promise((r) => setTimeout(r, 20));
      }
      await sonic.send("/n_free", 1000);
      return { peak, finite, reads, fails: window.fails };
    },
    { config: sonicConfig, frames: BUFFER_FRAMES, partials: PARTIALS },
  );

  expect(result.fails).toEqual([]);
  expect(result.finite).toBe(true);
  // The native renders of the same cloud peak at 0.614. The cloud is on the
  // left channel only, and the analyser mixes the two channels down to one
  // with a gain of 0.5 for each, so it sees a peak of about 0.307.
  expect(result.peak).toBeGreaterThan(0.25);
  expect(result.peak).toBeLessThan(0.35);
});
