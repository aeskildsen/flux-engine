/**
 * The test battery: every UGen of the engine package, in SAB and in
 * postMessage mode.
 *
 * test/make-battery.sh writes one SynthDef for each class file in
 * build/classes: the UGen with its default inputs, to bus 0. Thus a new UGen
 * (from the isospin release or a [[sources]] entry of ugens.toml) is in the
 * battery with no change here. For each UGen the battery checks:
 *  - the SynthDef loads and plays with no /fail, and the output has no NaN
 *    or infinite value;
 *  - CPU budget: with VOICES nodes of the UGen, the engine still processes
 *    its blocks in real time.
 *
 * The default inputs need not make a sound (PhysWoodbar strikes only on a
 * gate), so the battery does not check for sound. The specs of each UGen
 * (woodbar.spec.mjs, plaits.spec.mjs) check that.
 *
 * SuperSonic gives no CPU load on the web (/status.reply has 0 for the
 * average and peak CPU). The budget check uses the count of processed blocks
 * instead: when the audio thread cannot do its work in time, the browser
 * calls the engine less often than sampleRate / 128 times a second.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { test as base, expect } from "@playwright/test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const batteryJSON = path.join(root, "build/test/battery/battery.json");
const classes = fs.existsSync(path.join(root, "build/classes"))
  ? fs.readdirSync(path.join(root, "build/classes"))
      .filter((f) => f.endsWith(".sc"))
      .map((f) => f.slice(0, -3))
      .sort()
  : [];
const ugens = fs.existsSync(batteryJSON) ? JSON.parse(fs.readFileSync(batteryJSON, "utf8")) : [];

// Nodes of one UGen at the same time in the CPU budget check, and the part of
// the real-time block rate that the engine must keep with them.
const VOICES = 16;
const MIN_RATE = 0.9;
// Frames in one engine block (SuperSonic's web engine).
const BLOCK = 128;

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

// Boots the engine, loads one battery SynthDef and records every /fail reply
// in window.fails. Runs in the page.
const BOOT = `
  async function boot(config, name) {
    const sonic = new window.SuperSonic(config);
    window.fails = [];
    sonic.on("in", (msg) => { if (msg[0] === "/fail") window.fails.push(msg); });
    await sonic.init();
    await sonic.loadSynthDef("/battery/battery_" + name + ".scsyndef");
    return sonic;
  }
`;

test("the battery has a SynthDef for each UGen class of the package", () => {
  expect(classes.length, "no class files in build/classes (run scripts/prepare.py)").toBeGreaterThan(0);
  expect(ugens, "the battery SynthDefs are missing or old (run test/make-battery.sh)").toEqual(classes);
});

for (const ugen of ugens) {
  test(`${ugen} plays its default inputs with finite output`, async ({ harness, sonicConfig }) => {
    const result = await harness.evaluate(
      async ({ config, BOOT, ugen }) => {
        eval(BOOT);
        const sonic = await boot(config, ugen);
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

        await sonic.send("/s_new", "battery_" + ugen, 1000, 0, 0);
        let peak = 0, finite = true;
        const t0 = performance.now();
        while (performance.now() - t0 < 1000) {
          for (let ch = 0; ch < 2; ch++) {
            analysers[ch].getFloatTimeDomainData(bufs[ch]);
            for (const x of bufs[ch]) {
              if (!Number.isFinite(x)) finite = false;
              else peak = Math.max(peak, Math.abs(x));
            }
          }
          await new Promise((r) => setTimeout(r, 20));
        }
        await sonic.send("/n_free", 1000);
        return { peak, finite, fails: window.fails };
      },
      { config: sonicConfig, BOOT, ugen },
    );

    console.log(`battery ${ugen}: peak ${result.peak.toFixed(4)}`);
    expect(result.fails).toEqual([]);
    expect(result.finite, "NaN or infinite values in the output").toBe(true);
  });

  test(`${ugen} keeps real time with ${VOICES} voices`, async ({ harness, sonicConfig }) => {
    const result = await harness.evaluate(
      async ({ config, BOOT, ugen, voices }) => {
        eval(BOOT);
        const sonic = await boot(config, ugen);
        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
        for (let i = 0; i < voices; i++) await sonic.send("/s_new", "battery_" + ugen, 2000 + i, 0, 0);
        // Let all nodes start, then count the blocks for 2 s.
        await sleep(500);
        const count0 = sonic.getMetrics().engineProcessCount;
        const t0 = performance.now();
        await sleep(2000);
        const count1 = sonic.getMetrics().engineProcessCount;
        const t1 = performance.now();
        for (let i = 0; i < voices; i++) await sonic.send("/n_free", 2000 + i);
        return {
          blocks: count1 - count0,
          seconds: (t1 - t0) / 1000,
          sampleRate: sonic.node.context.sampleRate,
          fails: window.fails,
        };
      },
      { config: sonicConfig, BOOT, ugen, voices: VOICES },
    );

    const rate = result.blocks / result.seconds / (result.sampleRate / BLOCK);
    console.log(`battery ${ugen}: ${VOICES} voices, ${result.blocks} blocks in ${result.seconds.toFixed(2)} s, ${(rate * 100).toFixed(1)} % of real time`);
    expect(result.fails).toEqual([]);
    expect(rate).toBeGreaterThanOrEqual(MIN_RATE);
  });
}
