// Static server for the web engine tests.
//
//   /dist/...    the built engine (build/web/dist)
//   /assets/...  test assets (test/assets)
//   /battery/... the SynthDefs of the test battery (test/make-battery.sh)
//   /...         this folder (the harness page)
//
// With ISOLATE=1 the server sends the COOP and COEP headers, so the page is
// cross-origin isolated and SuperSonic can use shared memory (SAB mode).
// With ISOLATE=0 it sends no such headers, the same as GitHub Pages: the page
// is not isolated and SuperSonic must use postMessage mode.
//
//   PORT=8011 ISOLATE=1 node test/web/server.mjs

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const port = Number(process.env.PORT || 8011);
const isolate = process.env.ISOLATE !== "0";

const mounts = [
  ["/dist/", path.join(root, "build/web/dist")],
  ["/assets/", path.join(root, "test/assets")],
  ["/battery/", path.join(root, "build/test/battery")],
  ["/", here],
];

const types = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".mjs": "application/javascript",
  ".wasm": "application/wasm",
  ".json": "application/json",
  ".css": "text/css",
  ".flac": "audio/flac",
  ".wav": "audio/wav",
  ".scsyndef": "application/octet-stream",
};

function resolve(urlPath) {
  for (const [prefix, dir] of mounts) {
    if (!urlPath.startsWith(prefix)) continue;
    const file = path.join(dir, urlPath.slice(prefix.length));
    // Refuse paths that go out of the mounted folder.
    return file.startsWith(dir + path.sep) ? file : null;
  }
  return null;
}

http
  .createServer((req, res) => {
    const file = resolve(decodeURIComponent(req.url.split("?")[0]));
    fs.stat(file ?? "", (err, stats) => {
      if (!file || err || !stats.isFile()) {
        res.writeHead(404);
        res.end("Not found");
        return;
      }
      if (isolate) {
        res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
        res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
      }
      res.setHeader("Content-Type", types[path.extname(file)] ?? "application/octet-stream");
      res.setHeader("Content-Length", stats.size);
      res.writeHead(200);
      if (req.method === "HEAD") res.end();
      else fs.createReadStream(file).pipe(res);
    });
  })
  .listen(port, () => {
    console.log(`web test server on http://localhost:${port} (isolated: ${isolate})`);
  });
