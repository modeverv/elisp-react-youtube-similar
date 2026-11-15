// Serve the application as a static site (as GitHub Pages does) on
// http://localhost:8941/, with Emacs from a wasmacs checkout next to this
// one when there is one (../wasmacs/docs), on a second origin:
//
//   node tools/serve.mjs [PORT]
//
// Use "localhost", not 127.0.0.1: YouTube's player refuses to play for a
// page whose Referer is http://127.0.0.1:...
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { serveStatic } from "../test/lib/static-server.mjs";

const root = fileURLToPath(new URL("..", import.meta.url));
const port = Number(process.argv[2] || 8941);
const site = await serveStatic(root, { host: "localhost", port });
let query = "";
const wasmacs = process.env.WASMACS_DOCS || `${root}/../wasmacs/docs`;
if (existsSync(`${wasmacs}/app/src/emacs-eval-client.js`)) {
  const emacs = await serveStatic(wasmacs, { port: port + 1 });
  query = `?wasmacs=${emacs.origin}/`;
}
console.log(`${site.origin}/${query}`);
