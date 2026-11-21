/**
 * A measurement, not a test: how many IsoSuperPos voices the web engine can play
 * in real time, at overlap 5, 20 and 60. It runs only when SUPERPOS_CPU is set:
 *
 *   scripts/in-image.sh env SUPERPOS_CPU=1 npx playwright test -c test/web superpos-cpu
 *
 * SuperSonic gives no DSP load on the web, so the measurement uses the count
 * of processed blocks, as battery.spec.mjs does: for each overlap the voice
 * count doubles until the engine processes less than MIN_RATE of its blocks
 * in real time. Each voice is the IsoSuperPos test SynthDef (test/assets/
 * sp.scsyndef: grainDur 0.05, transpose 7, normalize 0, 64 grains) on the test
 * buffer. The result is printed; the run fails only on a /fail.
 */

import { test as base, expect } from "@playwright/test";

const BUFFER_FRAMES = 30000;
const PARTIALS = [1, 0.5, 0.8, 0.25, 0.6, 0.1, 0.45, 0.3, 0.05, 0.35, 0.2, 0.15];
const OVERLAPS = [5, 20, 60];
const VOICES = [8, 16, 32, 64, 128, 256, 512];
const MIN_RATE = 0.95;
const BLOCK = 128;

const test = base.extend({
  sonicConfig: async ({}, use, testInfo) => {
    await use({
      baseURL: "/dist/",
      workerBaseURL: "/dist/workers/",
      wasmBaseURL: "/dist/wasm/",
      wasmUrl: "/dist/wasm/clockwork-scsynth.wasm",
      synthdefBaseURL: "/dist/synthdefs/",
      sampleBaseURL: "/dist/samples/",
      snapshotIntervalMs: 25,
      mode: testInfo.project.use.supersonicMode,
    });
  },
  harness: async ({ page }, use) => {
    await page.goto("/harness.html");
    await page.waitForFunction(() => window.supersonicReady === true);
    await use(page);
  },
});

test.skip(!process.env.SUPERPOS_CPU, "a measurement; set SUPERPOS_CPU=1 to run it");
test.setTimeout(300000);

test("IsoSuperPos voices in real time on the web", async ({ harness, sonicConfig }) => {
  const results = await harness.evaluate(
    async ({ config, frames, partials, overlaps, voiceSteps, minRate, block }) => {
      const sonic = new window.SuperSonic(config);
      const fails = [];
      sonic.on("in", (msg) => { if (msg[0] === "/fail") fails.push(msg); });
      await sonic.init();
      await sonic.loadSynthDef("/assets/sp.scsyndef");
      await sonic.allocSample(0, frames, 1);
      await sonic.request("/b_gen", [0, "sine1", 5, ...partials],
                          { reply: "/done", match: (m) => m[1] === "/b_gen" });
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      const blockRate = sonic.node.context.sampleRate / block;
      const rows = [];
      for (const overlap of overlaps) {
        let kept = 0;
        for (const voices of voiceSteps) {
          for (let i = 0; i < voices; i++)
            await sonic.send("/s_new", "sp", 3000 + i, 0, 0, "buf", 0, "overlap", overlap, "amp", 0.01);
          await sleep(500);
          const c0 = sonic.getMetrics().engineProcessCount;
          const t0 = performance.now();
          await sleep(2000);
          const c1 = sonic.getMetrics().engineProcessCount;
          const t1 = performance.now();
          for (let i = 0; i < voices; i++) await sonic.send("/n_free", 3000 + i);
          await sleep(300);
          const rate = (c1 - c0) / ((t1 - t0) / 1000) / blockRate;
          rows.push({ overlap, voices, rate });
          if (rate < minRate) break;
          kept = voices;
        }
        rows.push({ overlap, kept });
      }
      return { rows, fails };
    },
    { config: sonicConfig, frames: BUFFER_FRAMES, partials: PARTIALS, overlaps: OVERLAPS, voiceSteps: VOICES,
      minRate: MIN_RATE, block: BLOCK },
  );
  for (const r of results.rows) {
    if (r.kept !== undefined) console.log(`superpos-cpu: overlap ${r.overlap}: ${r.kept} voices kept real time`);
    else console.log(`superpos-cpu: overlap ${r.overlap}, ${r.voices} voices: ${(r.rate * 100).toFixed(1)} % of real time`);
  }
  expect(results.fails).toEqual([]);
});
