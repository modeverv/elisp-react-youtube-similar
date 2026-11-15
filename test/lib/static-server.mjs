// A small static file server for development and tests: GitHub Pages
// without the network.  Hidden files are never served.  A single "Range"
// is answered, which wasmacs's eval service uses to read Emacs's files on
// demand (without it, it downloads the whole package).
import { createReadStream, realpathSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, relative, resolve, sep } from "node:path";

const types = {
  ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript",
  ".mjs": "text/javascript", ".json": "application/json", ".wasm": "application/wasm",
  ".el": "text/plain; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png",
};

export function serveStatic(root, { host = "127.0.0.1", port = 0 } = {}) {
  root = realpathSync.native(resolve(root));
  const server = createServer((request, response) => {
    let path;
    try {
      path = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
    } catch {
      return response.writeHead(400).end("bad request");
    }
    if (path.includes("\0") || path.split("/").some((part) => part.startsWith("."))) {
      return response.writeHead(404).end("not found");
    }
    let file, info;
    try {
      file = realpathSync.native(join(root, path));
      const inside = relative(root, file);
      if (inside.startsWith("..") || inside.split(sep).some((part) => part.startsWith("."))) throw new Error("outside");
      info = statSync(file);
      if (info.isDirectory()) {
        if (!path.endsWith("/")) return response.writeHead(301, { Location: `${path}/` }).end();
        file = join(file, "index.html");
        info = statSync(file);
      }
    } catch {
      return response.writeHead(404).end("not found");
    }
    const headers = {
      "Content-Type": types[extname(file)] || "application/octet-stream",
      "Access-Control-Allow-Origin": "*",
      "Accept-Ranges": "bytes",
      "Cache-Control": "no-cache",
    };
    const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range || "");
    if (range && (range[1] || range[2])) {
      let start = range[1] ? Number(range[1]) : info.size - Number(range[2]);
      let end = range[1] && range[2] ? Math.min(Number(range[2]), info.size - 1) : info.size - 1;
      start = Math.max(0, start);
      if (start > end || start >= info.size) {
        return response.writeHead(416, { "Content-Range": `bytes */${info.size}` }).end();
      }
      response.writeHead(206, { ...headers, "Content-Range": `bytes ${start}-${end}/${info.size}`, "Content-Length": end - start + 1 });
      if (request.method === "HEAD") return response.end();
      return createReadStream(file, { start, end }).pipe(response);
    }
    response.writeHead(200, { ...headers, "Content-Length": info.size });
    if (request.method === "HEAD") return response.end();
    createReadStream(file).pipe(response);
  });
  return new Promise((done) => server.listen(port, host, () => {
    done({ server, origin: `http://${host}:${server.address().port}` });
  }));
}
