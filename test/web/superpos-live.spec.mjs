/**
 * SuperPosLive (isospin) in the web engine, in SAB and in postMessage mode.
 *
 * test/assets/sp_live.scsyndef is the SuperPosLive test SynthDef (made by
 * test/make-superpos-synthdefs.scd; test/native-superpos.sh checks that the
 * fixture is the same as the SynthDef that the class makes). Its input is a
 * sine made in the engine, so no device input is needed. The test allocates
 * the record buffer (/b_alloc), plays the SynthDef and checks that the output
 * is a finite sound of the expected level. The native test checks the
 * content (the output follows the input; freeze keeps it).
 *
 * The output is observed with an AnalyserNode on the engine's output node, as
 * in woodbar.spec.mjs. The test reads for 1 s: the grains start at once and
 * read the input 0.1 s behind the record head.
 */

import { test as base, expect } from "@playwright/test";

// The same value as ~superposLiveFrames in test/superpos-synthdefs.scd.
const BUFFER_FRAMES = 48000;

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

test("SuperPosLive plays its input from the record buffer at the output node", async ({ harness, sonicConfig }) => {
  const result = await harness.evaluate(
    async ({ config, frames }) => {
      const sonic = new window.SuperSonic(config);
      window.fails = [];
      sonic.on("in", (msg) => { if (msg[0] === "/fail") window.fails.push(msg); });
      await sonic.init();
      await sonic.loadSynthDef("/assets/sp_live.scsyndef");

      // The record buffer: buffer 1, as the default of the SynthDef.
      await sonic.allocSample(1, frames, 1);

      const ctx = sonic.node.context;
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 2048;
      sonic.node.connect(analyser);
      const buf = new Float32Array(analyser.fftSize);

      await sonic.send("/s_new", "sp_live", 1000, 0, 0, "buf", 1);

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
    { config: sonicConfig, frames: BUFFER_FRAMES },
  );

  expect(result.fails).toEqual([]);
  expect(result.finite).toBe(true);
  // The native renders of the same SynthDef peak at 0.707 in each channel.
  // The analyser mixes the two equal channels down to one with a gain of 0.5
  // for each, so it sees the same peak.
  expect(result.peak).toBeGreaterThan(0.6);
  expect(result.peak).toBeLessThan(0.8);
});
