/**
 * MiPlaits in the web engine, in SAB and in postMessage mode.
 *
 * test/assets/plaits_test.scsyndef is the MiPlaits test SynthDef (made by
 * test/make-plaits-synthdef.scd with the MiPlaits class): MiPlaits with no
 * trigger and no level input, so every engine sounds continuously. The test
 * plays each of the 24 engines in turn and checks that the output is not
 * silent, has no NaN or infinite values, and that the engine sends no /fail.
 *
 * The output is observed with AnalyserNodes on the engine's output node, as
 * in woodbar.spec.mjs; this works in both modes.
 */

import { test as base, expect } from "@playwright/test";

const test = base.extend({
  sonicMode: async ({}, use, testInfo) => {
    await use(testInfo.project.use.supersonicMode);
  },
  sonicConfig: async ({ sonicMode }, use) => {
    await use({
      baseURL: "/dist/",
      workerBaseURL: "/dist/workers/",
      wasmBaseURL: "/dist/wasm/",
      wasmUrl: "/dist/wasm/scsynth-nrt.wasm",
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

const ENGINES = 24;

test("each MiPlaits engine makes a finite, not silent sound", async ({ harness, sonicConfig }) => {
  test.setTimeout(60_000);
  const result = await harness.evaluate(
    async ({ config, engines }) => {
      const sonic = new window.SuperSonic(config);
      const fails = [];
      sonic.on("in", (msg) => { if (msg[0] === "/fail") fails.push(msg); });
      await sonic.init();
      await sonic.loadSynthDef("/assets/plaits_test.scsyndef");
      const ctx = sonic.node.context;

      const splitter = ctx.createChannelSplitter(2);
      sonic.node.connect(splitter);
      const analysers = [0, 1].map((ch) => {
        const a = ctx.createAnalyser();
        a.fftSize = 2048;
        splitter.connect(a, ch);
        return a;
      });
      const bufs = analysers.map((a) => new Float32Array(a.fftSize));

      const results = [];
      for (let engine = 0; engine < engines; engine++) {
        const id = 1000 + engine;
        // harm 0.3: harm selects the patch of the six-op FM engines, and at
        // 0.5 the patch of engine 19 is almost silent (peak 0.003, the same
        // in native scsynth with the stock MiPlaits).
        await sonic.send("/s_new", "plaits_test", id, 0, 0, "engine", engine, "harm", 0.3);
        // Let the sound reach the analysers, then read for 300 ms.
        await new Promise((r) => setTimeout(r, 150));
        let peak = 0, finite = true;
        const t0 = performance.now();
        while (performance.now() - t0 < 300) {
          for (let ch = 0; ch < 2; ch++) {
            analysers[ch].getFloatTimeDomainData(bufs[ch]);
            for (const x of bufs[ch]) {
              if (!Number.isFinite(x)) finite = false;
              else peak = Math.max(peak, Math.abs(x));
            }
          }
          await new Promise((r) => setTimeout(r, 20));
        }
        await sonic.send("/n_free", id);
        // Let the freed node leave the analyser windows.
        await new Promise((r) => setTimeout(r, 100));
        results.push({ engine, peak, finite });
      }
      return { results, fails };
    },
    { config: sonicConfig, engines: ENGINES },
  );

  console.log(`engines: ${result.results.map((r) => `${r.engine}:${r.peak.toFixed(3)}`).join(" ")}`);
  expect(result.fails).toEqual([]);
  for (const r of result.results) {
    expect.soft(r.finite, `engine ${r.engine} has NaN or infinite values`).toBe(true);
    expect.soft(r.peak, `engine ${r.engine} is silent`).toBeGreaterThan(0.01);
    expect.soft(r.peak, `engine ${r.engine} is too loud`).toBeLessThanOrEqual(1.0);
  }
});
