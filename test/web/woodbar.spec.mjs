/**
 * PhysWoodbar in the web engine, in SAB and in postMessage mode.
 *
 * test/assets/wb.scsyndef is the woodbar test SynthDef (made by
 * test/make-synthdef.scd with the PhysWoodbar class). Each test strikes one
 * note and checks the shape of the sound: loud enough, decays, and the left
 * and right channels differ (the two pickups of the bar).
 *
 * The output is observed with AnalyserNodes on the engine's output node. This
 * works in both modes. SuperSonic's audio capture reads shared memory, so the
 * capture test runs in SAB mode only.
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

// Boots the engine, loads the woodbar SynthDef and records every /fail reply
// in window.fails. Runs in the page.
const BOOT = `
  async function boot(config) {
    const sonic = new window.SuperSonic(config);
    window.fails = [];
    sonic.on("in", (msg) => { if (msg[0] === "/fail") window.fails.push(msg); });
    await sonic.init();
    await sonic.loadSynthDef("/assets/wb.scsyndef");
    return sonic;
  }
`;

test("the page and the engine use the expected transport mode", async ({ harness, sonicConfig, sonicMode }) => {
  const result = await harness.evaluate(
    async ({ config, BOOT }) => {
      eval(BOOT);
      const sonic = await boot(config);
      return { isolated: window.crossOriginIsolated, mode: sonic.getMetrics().mode };
    },
    { config: sonicConfig, BOOT },
  );
  expect(result.mode).toBe(sonicMode);
  // postMessage mode runs on a page with no COOP and COEP headers, as on
  // GitHub Pages.
  expect(result.isolated).toBe(sonicMode === "sab");
});

test("PhysWoodbar makes a decaying stereo sound at the output node", async ({ harness, sonicConfig }) => {
  const result = await harness.evaluate(
    async ({ config, BOOT }) => {
      eval(BOOT);
      const sonic = await boot(config);
      const ctx = sonic.node.context;

      // One analyser for each output channel.
      const splitter = ctx.createChannelSplitter(2);
      sonic.node.connect(splitter);
      const analysers = [0, 1].map((ch) => {
        const a = ctx.createAnalyser();
        a.fftSize = 2048;
        splitter.connect(a, ch);
        return a;
      });
      const bufs = analysers.map((a) => new Float32Array(a.fftSize));

      await sonic.send("/s_new", "wb", 1000, 0, 0, "freq", 220, "gain", 0.8);

      // Read both analysers every 20 ms for 1.5 s. Each read is a window of
      // 2048 frames; both reads in one task see the same audio frames.
      const reads = [];
      const t0 = performance.now();
      while (performance.now() - t0 < 1500) {
        analysers.forEach((a, i) => a.getFloatTimeDomainData(bufs[i]));
        let left = 0, right = 0, diff = 0;
        for (let i = 0; i < bufs[0].length; i++) {
          left = Math.max(left, Math.abs(bufs[0][i]));
          right = Math.max(right, Math.abs(bufs[1][i]));
          diff = Math.max(diff, Math.abs(bufs[0][i] - bufs[1][i]));
        }
        reads.push({ t: performance.now() - t0, left, right, diff });
        await new Promise((r) => setTimeout(r, 20));
      }
      await sonic.send("/n_free", 1000);

      const onset = reads.findIndex((r) => r.left > 0.01 || r.right > 0.01);
      const peakOf = (rs) => Math.max(0, ...rs.map((r) => Math.max(r.left, r.right)));
      const after = onset < 0 ? [] : reads.slice(onset);
      const tOnset = onset < 0 ? 0 : reads[onset].t;
      return {
        reads: reads.length,
        onsetMs: onset < 0 ? null : tOnset,
        peakAll: peakOf(after),
        peakEarly: peakOf(after.filter((r) => r.t - tOnset < 300)),
        peakLate: peakOf(reads.filter((r) => r.t > 1200)),
        lrDiff: Math.max(0, ...after.map((r) => r.diff)),
        fails: window.fails,
      };
    },
    { config: sonicConfig, BOOT },
  );

  console.log(`analyser: ${JSON.stringify({ ...result, fails: result.fails.length })}`);
  expect(result.fails).toEqual([]);
  expect(result.onsetMs).not.toBeNull();
  expect(result.peakAll).toBeGreaterThan(0.1);
  expect(result.peakAll).toBeLessThanOrEqual(1.0);
  // The bar rings out: the late part is quieter than the strike.
  expect(result.peakLate).toBeLessThan(result.peakEarly);
  // The two pickups differ, thus the output is not mono.
  expect(result.lrDiff).toBeGreaterThan(0.001);
});

test("PhysWoodbar in the audio capture", async ({ harness, sonicConfig, sonicMode }) => {
  test.skip(sonicMode !== "sab", "audio capture reads shared memory (SAB mode only)");
  const result = await harness.evaluate(
    async ({ config, BOOT }) => {
      eval(BOOT);
      const sonic = await boot(config);
      sonic.startCapture();
      await sonic.send("/s_new", "wb", 1000, 0, 0, "freq", 220, "gain", 0.8);
      await new Promise((r) => setTimeout(r, 600));
      const captured = sonic.stopCapture();

      const peak = (s, a, b) => {
        let p = 0;
        for (let i = a; i < b && i < s.length; i++) p = Math.max(p, Math.abs(s[i]));
        return p;
      };
      let lrDiff = 0;
      for (let i = 0; i < captured.frames; i++) {
        lrDiff = Math.max(lrDiff, Math.abs(captured.left[i] - captured.right[i]));
      }
      const n = captured.frames;
      return {
        frames: n,
        peakAll: peak(captured.left, 0, n),
        peakEarly: peak(captured.left, 0, Math.floor(n / 2)),
        peakLate: peak(captured.left, Math.floor((n * 3) / 4), n),
        lrDiff,
        fails: window.fails,
      };
    },
    { config: sonicConfig, BOOT },
  );

  expect(result.fails).toEqual([]);
  expect(result.frames).toBeGreaterThan(0);
  expect(result.peakAll).toBeGreaterThan(0.1);
  expect(result.peakAll).toBeLessThanOrEqual(1.0);
  expect(result.peakLate).toBeLessThan(result.peakEarly);
  expect(result.lrDiff).toBeGreaterThan(0.001);
});
