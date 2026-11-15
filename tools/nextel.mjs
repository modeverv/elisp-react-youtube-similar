#!/usr/bin/env node
// pages/ as routes: write nextel/routes.el and the <script> tags of index.html.
//
//   node tools/nextel.mjs            write them
//   node tools/nextel.mjs --check    fail if they are not up to date (CI)
//   node tools/nextel.mjs --watch    write them again whenever pages/, api/ or shared/ change
//
// A page's address is its file's path: pages/index.el is "/", pages/watch.el
// "/watch", pages/channel/[id].el "/channel/[id]" (a parameter), and
// pages/x/[...rest].el the rest of a path.  The file names its component with
// (nextel-page NAME ...); pages/_layout.el has (nextel-layout NAME ...) and
// pages/404.el the page of an address that no file has.  Files and
// directories whose name starts with _ are loaded but are no page.
//
// The page loads its Lisp from <script> tags, in order: index.html has two
// places for the ones written here, between
//   <!-- nextel:framework -->  <!-- /nextel:framework -->   nextel/ and shared/, before the application's files
//   <!-- nextel:pages -->      <!-- /nextel:pages -->       pages/ and nextel/routes.el, after them
// api/ needs nothing written: the server reads that directory itself
// (nextel/nextel-server.el); its routes are listed in routes.el for reading.
import { existsSync, readdirSync, readFileSync, statSync, watch, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const args = process.argv.slice(2);
const mountAt = args.includes("--mount") ? args[args.indexOf("--mount") + 1] : "#app";

/** The .el files under DIRECTORY (relative to it, with /), sorted. */
function lispFiles(directory) {
  const found = [];
  (function walk(at) {
    if (!existsSync(join(directory, at))) return;
    for (const entry of readdirSync(join(directory, at), { withFileTypes: true })) {
      if (entry.name.startsWith(".")) continue;
      const path = at ? `${at}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(path);
      else if (entry.name.endsWith(".el")) found.push(path);
    }
  })("");
  return found.sort();
}

const isPrivate = (path) => path.split("/").some((part) => part.startsWith("_"));

/** "channel/[id].el" -> "/channel/[id]"; "index.el" -> "/". */
export function patternOf(file) {
  const parts = file.replace(/\.el$/, "").split("/").filter(Boolean);
  if (parts.at(-1) === "index") parts.pop();
  return `/${parts.join("/")}`;
}

// Fixed segments before parameters, parameters before [...rest]; of two
// that agree as far as both go, the longer first (as nextel-route.el sorts).
const rank = (pattern) => pattern.split("/").filter(Boolean)
  .map((segment) => (segment.startsWith("[...") ? 2 : segment.startsWith("[") ? 1 : 0));
export function patternOrder(a, b) {
  const ra = rank(a), rb = rank(b);
  for (let i = 0; i < Math.min(ra.length, rb.length); i++) if (ra[i] !== rb[i]) return ra[i] - rb[i];
  return rb.length - ra.length || a.localeCompare(b);
}

/** What pages/ and api/ say: the routes, the layout, the 404 page, the files. */
export function readProject(directory = root) {
  const pagesDirectory = join(directory, "pages");
  const pages = lispFiles(pagesDirectory);
  const named = (file, form) => {
    const text = readFileSync(join(pagesDirectory, file), "utf8");
    const match = new RegExp(`\\(${form}\\s+([^\\s()]+)`).exec(text);
    if (!match) throw new Error(`pages/${file} has no (${form} NAME ...)`);
    return match[1];
  };
  const routes = [];
  let layout = null, notFound = null;
  const helpers = [], pageFiles = [];
  for (const file of pages) {
    if (file === "_layout.el") { layout = named(file, "nextel-layout"); helpers.unshift(file); continue; }
    if (file === "404.el") { notFound = named(file, "nextel-page"); pageFiles.push(file); continue; }
    if (isPrivate(file)) { helpers.push(file); continue; }
    const pattern = patternOf(file);
    const clash = routes.find((route) => route.pattern === pattern);
    if (clash) throw new Error(`pages/${clash.file} and pages/${file} are both ${pattern}`);
    routes.push({ pattern, page: named(file, "nextel-page"), file });
    pageFiles.push(file);
  }
  routes.sort((a, b) => patternOrder(a.pattern, b.pattern));
  const api = lispFiles(join(directory, "api")).filter((file) => !isPrivate(file))
    .map((file) => ({ pattern: patternOf(`api/${file}`), file: `api/${file}` }))
    .sort((a, b) => patternOrder(a.pattern, b.pattern));
  const shared = lispFiles(join(directory, "shared")).map((file) => `shared/${file}`);
  return { routes, layout, notFound, api, shared,
           pageScripts: [...helpers, ...pageFiles.sort()].map((file) => `pages/${file}`) };
}

const lispString = (text) => `"${text.replace(/[\\"]/g, "\\$&")}"`;

export function routesFile({ routes, layout, notFound, api }, mount = mountAt) {
  const width = Math.max(...routes.map((route) => route.pattern.length + 2), 0);
  return `;;; routes.el --- which page is which address  -*- lexical-binding: t; -*-

;; Written by tools/nextel.mjs from pages/: do not edit, run it again.
;;
;; The server's routes, from api/ (nextel/nextel-server.el reads that directory itself):
${api.map((route) => `;;   ${route.pattern.padEnd(width)}  ${route.file}`).join("\n") || ";;   (none)"}

(nextel-define-routes
 '(${routes.map((route) => `(${lispString(route.pattern)} . ${route.page})`).join("\n   ")})${layout ? `\n :layout '${layout}` : ""}${notFound ? `\n :not-found '${notFound}` : ""})

(nextel-start ${lispString(mount)})

;;; routes.el ends here
`;
}

const script = (src) => `    <script type="text/emacs-lisp" src="${src}"></script>`;

/** index.html with the two places filled in. */
export function indexHtml(html, project) {
  const fill = (name, sources) => {
    const pattern = new RegExp(`([ \\t]*<!-- nextel:${name} -->)[\\s\\S]*?([ \\t]*<!-- /nextel:${name} -->)`);
    if (!pattern.test(html)) throw new Error(`index.html has no <!-- nextel:${name} --> ... <!-- /nextel:${name} -->`);
    html = html.replace(pattern, (_all, open, close) => `${open}\n${sources.map(script).join("\n")}\n${close}`);
  };
  fill("framework", ["nextel/nextel-schema.el", "nextel/nextel-route.el", "nextel/nextel.el", ...project.shared]);
  fill("pages", [...project.pageScripts, "nextel/routes.el"]);
  return html;
}

function build({ check = false } = {}) {
  const project = readProject();
  const outputs = [
    [join(root, "nextel/routes.el"), routesFile(project)],
    [join(root, "index.html"), indexHtml(readFileSync(join(root, "index.html"), "utf8"), project)],
  ];
  const stale = outputs.filter(([file, text]) => !existsSync(file) || readFileSync(file, "utf8") !== text);
  if (check) {
    if (stale.length) {
      console.error(`not up to date: ${stale.map(([file]) => relative(root, file)).join(", ")}; run node tools/nextel.mjs`);
      process.exitCode = 1;
    }
    return;
  }
  for (const [file, text] of stale) writeFileSync(file, text);
  console.log(`${project.routes.length} pages, ${project.api.length} API routes${stale.length ? `: wrote ${stale.map(([file]) => relative(root, file)).join(", ")}` : ", nothing changed"}`);
  for (const route of project.routes) console.log(`  ${route.pattern.padEnd(18)} ${route.page.padEnd(16)} pages/${route.file}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  build({ check: args.includes("--check") });
  if (args.includes("--watch")) {
    let timer = null;
    for (const name of ["pages", "api", "shared"]) {
      if (!existsSync(join(root, name)) || !statSync(join(root, name)).isDirectory()) continue;
      watch(join(root, name), { recursive: true }, (_event, file) => {
        if (!String(file).endsWith(".el") && !String(file).includes(sep)) return;
        clearTimeout(timer);
        timer = setTimeout(() => { try { build(); } catch (error) { console.error(error.message); } }, 150);
      });
    }
    console.log("watching pages/, api/ and shared/");
  }
}
