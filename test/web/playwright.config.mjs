// Playwright tests of the web engine in build/web/dist (scripts/build-web.sh).
//
// Two projects, one for each transport mode:
//  - SAB: the server sends COOP and COEP, the page is cross-origin isolated
//    and SuperSonic uses shared memory.
//  - postMessage: the server sends no such headers, the same as GitHub Pages,
//    where Flux is deployed. SuperSonic uses postMessage.
//
//   npx playwright test -c test/web

import { defineConfig } from "@playwright/test";

const ports = { sab: 8011, postMessage: 8012 };

export default defineConfig({
  testDir: ".",
  testMatch: "*.spec.mjs",
  timeout: 30000,
  retries: 0,
  outputDir: "../../build/test/web/results",
  use: {
    headless: true,
    browserName: "chromium",
    launchOptions: {
      args: ["--autoplay-policy=no-user-gesture-required"],
    },
  },
  projects: [
    {
      name: "SAB",
      use: { baseURL: `http://localhost:${ports.sab}`, supersonicMode: "sab" },
    },
    {
      name: "postMessage",
      use: { baseURL: `http://localhost:${ports.postMessage}`, supersonicMode: "postMessage" },
    },
  ],
  webServer: [
    {
      command: "node server.mjs",
      env: { PORT: String(ports.sab), ISOLATE: "1" },
      port: ports.sab,
      reuseExistingServer: false,
    },
    {
      command: "node server.mjs",
      env: { PORT: String(ports.postMessage), ISOLATE: "0" },
      port: ports.postMessage,
      reuseExistingServer: false,
    },
  ],
});
