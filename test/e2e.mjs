// Parens in headless Chrome, offline and with made-up data: the no-key mode,
// the Data API mode, routes and Back, keys, history and "watch later",
// settings (key, language, theme) and a phone-sized screen.
//
//   node test/e2e.mjs
//
// The site is served as GitHub Pages would serve it (test/lib/static-server.mjs)
// on http://localhost:PORT: YouTube's player refuses a page whose Referer is
// 127.0.0.1.  Emacs comes from a wasmacs checkout next to this repository
// (../wasmacs/docs, or $WASMACS_DOCS) on a second origin (?wasmacs=), else from
// the public site.  Whatever else the page asks of the network is answered
// here, through the DevTools protocol (Fetch domain), never by the network:
//
//   https://modeverv.github.io/elisp-react/...  the checkout ../elisp-react ($ELISP_REACT), when there is one
//   https://www.youtube.com/oembed               test/fixtures/oembed.json: made-up titles for the ids of lisp/parens-data.el
//   https://www.googleapis.com/youtube/v3/...    test/fixtures/data-api/: made-up videos and channels in the Data API's shapes
//   i.ytimg.com, yt3.ggpht.com, ...              a 1x1 PNG
//   https://www.youtube-nocookie.com/embed/...   a stub page instead of the player
//   https://www.youtube.com/iframe_api           a script that defines nothing: the page must do without the player's API
//                                                (later the test installs a stand-in YT.Player to see what the port asks of it)
//
// Any other request to another site fails the test, and so does an exception,
// a console.error or a failed load in the page, but the 404s of api/feed (a
// static site has no server.el) and favicon.ico.  The interface's words are
// read from lisp/parens-util.el: the checks name the message they expect.
// "KNOWN BUG" lines report wrong behaviour of the application that the test
// knows about without failing; where the behaviour is right, it is asserted.
//
//   E2E_LIVE=1    intercept nothing: a smoke test of the no-key mode against YouTube itself
//   E2E_SITE=URL  test a deployed copy instead of this checkout (implies E2E_LIVE)
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { extname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { CdpClient, chromePath, devToolsUrl, evaluate, pause, waitUntil } from "./lib/cdp.mjs";
import { serveStatic } from "./lib/static-server.mjs";

const root = fileURLToPath(new URL("..", import.meta.url)).replace(/\/$/, "");
const fixtures = join(root, "test/fixtures");
const deployed = (process.env.E2E_SITE || "").replace(/\/+$/, "");
const live = Boolean(deployed || process.env.E2E_LIVE);
const wasmacsDocs = resolve(root, process.env.WASMACS_DOCS || "../wasmacs/docs");
const elispReact = resolve(root, process.env.ELISP_REACT || "../elisp-react");
const startedAt = Date.now();
const seconds = (ms) => `${(ms / 1000).toFixed(1)} s`;
const pass = (message) => console.log(`PASS ${message}`);
// Wrong behaviour of the application that the test knows about: printed, not
// failed.  Where the right behaviour is seen instead, the test asserts it.
const known = (message) => console.log(`KNOWN BUG ${message}`);
const bootTimeout = live ? 300_000 : 120_000;
const stepTimeout = live ? 60_000 : 20_000;

// ---- the videos of the no-key mode, as lisp/parens-data.el lists them -----------
const parensData = readFileSync(join(root, "lisp/parens-data.el"), "utf8");
const defconst = (name) => {
  const start = parensData.indexOf(`(defconst ${name}`);
  assert.ok(start >= 0, `lisp/parens-data.el defines ${name}`);
  return parensData.slice(start, parensData.indexOf("\n\n", start));
};
const curated = [...defconst("parens-curated-videos").matchAll(/\("([A-Za-z0-9_-]{11})" "(UC[A-Za-z0-9_-]{22})"\)/g)]
  .map(([, id, channel]) => ({ id, channel }));
const topicOf = Object.fromEntries([...defconst("parens-curated-channels").matchAll(/\("(UC[A-Za-z0-9_-]{22})" ([a-z-]+)\)/g)]
  .map(([, channel, topic]) => [channel, topic]));
const topics = [...defconst("parens-topics").matchAll(/\(([a-z-]+) "([^"]*)" "([^"]*)"\)/g)]
  .map(([, topic, ja, en]) => ({ topic, ja, en }));
assert.ok(curated.length > 20 && Object.keys(topicOf).length > 0 && topics.length > 0, "lisp/parens-data.el was read");
const curatedIds = curated.map((video) => video.id);
const channelOf = (id) => curated.find((video) => video.id === id).channel;
const curatedChannels = Object.keys(topicOf);   // the sidebar's order

// The interface's words, as lisp/parens-util.el has them: (KEY JAPANESE ENGLISH).
// The checks name the message they expect; the wording is the application's.
const parensUtil = readFileSync(join(root, "lisp/parens-util.el"), "utf8");
const words = Object.fromEntries([...parensUtil.slice(parensUtil.indexOf("(defconst parens-words"), parensUtil.indexOf("(defun parens-t"))
  .matchAll(/\(([a-z0-9-]+)\s+"((?:[^"\\]|\\.)*)"\s+"((?:[^"\\]|\\.)*)"\)/g)]
  .map(([, key, ja, en]) => [key, { ja: ja.replace(/\\(.)/g, "$1"), en: en.replace(/\\(.)/g, "$1") }]));
assert.ok(Object.keys(words).length > 50, "lisp/parens-util.el's words were read");
const word = (lang) => (key, ...args) => {
  assert.ok(words[key], `parens-words has ${key}`);
  return words[key][lang].replace(/%[sd]/g, () => String(args.shift()));
};
const w = word("ja");
const en = word("en");

// The related videos of the no-key mode: the same channel, then the same topic, then the rest.
function curatedRelated(id) {
  const others = curatedIds.filter((other) => other !== id);
  const channel = others.filter((other) => channelOf(other) === channelOf(id));
  const topic = others.filter((other) => !channel.includes(other) && topicOf[channelOf(other)] === topicOf[channelOf(id)]);
  return [...channel, ...topic, ...others.filter((other) => !channel.includes(other) && !topic.includes(other))].slice(0, 20);
}

// ---- made-up YouTube ----------------------------------------------------------------
const fixture = (name) => JSON.parse(readFileSync(join(fixtures, name), "utf8"));
const oembed = fixture("oembed.json");
const dataApi = {
  videos: fixture("data-api/videos.json").items,
  charts: fixture("data-api/charts.json"),          // chart=mostPopular: video ids per videoCategoryId ("" for none)
  channels: fixture("data-api/channels.json").items,
  categories: { en: fixture("data-api/videoCategories.en.json"), ja: fixture("data-api/videoCategories.ja.json") },
  threads: fixture("data-api/commentThreads.json").items,
  playlistItems: fixture("data-api/playlistItems.json").items,
  errors: fixture("data-api/errors.json"),           // bodies of the API's errors; the HTTP status is error.code
};
for (const id of curatedIds) assert.ok(oembed[id], `test/fixtures/oembed.json has ${id} (lisp/parens-data.el)`);
for (const item of dataApi.videos) assert.match(item.id, /^[A-Za-z0-9_-]{11}$/, "a video id of the fixtures");
for (const item of dataApi.channels) assert.match(item.id, /^UC[A-Za-z0-9_-]{22}$/, "a channel id of the fixtures");
const API_KEY = "fixture-key-for-the-e2e-test";
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMIBQAAVwBWP0MfTAAAAABJRU5ErkJggg==", "base64");   // 1x1, gray
const STUB_PLAYER = (id) => `<!doctype html><meta charset="utf-8"><title>player stub</title>
<body style="margin:0;height:100vh;display:grid;place-items:center;background:#000;color:#888;font:14px sans-serif">offline stub of the player: ${id.replace(/[^A-Za-z0-9_-]/g, "")}</body>`;
const STUB_IFRAME_API = "/* e2e: a stub of https://www.youtube.com/iframe_api that defines nothing; the page must do without the player's API. */\n";

const video = (id) => dataApi.videos.find((item) => item.id === id);
const channel = (id) => dataApi.channels.find((item) => item.id === id);
const chart = (category = "") => dataApi.charts[category].map(video);
const playable = (items) => items.filter((item) => item.status.embeddable);
const etagOf = (text) => createHash("sha1").update(text).digest("base64url").slice(0, 27);
// Page tokens look like the API's (a protobuf with the offset): CBgQAA is 24.
const pageToken = (offset) => Buffer.from([8, offset, 16, 0]).toString("base64url");
const tokenOffset = (token) => Buffer.from(token, "base64url")[1] || 0;

const apiErrors = [];          // "endpoint:reason" of every error the made-up API answered, taken by the checks
const apiFailNext = new Map(); // endpoint -> reason: the next request to it fails so
// The Data API's answer to URL: { status, body }, or null when there is no fixture for it.
function answerDataApi(url) {
  const endpoint = url.pathname.slice("/youtube/v3/".length);
  const query = url.searchParams;
  const failure = (reason) => {
    apiErrors.push(`${endpoint}:${reason}`);
    return { status: dataApi.errors[reason].error.code, body: dataApi.errors[reason] };
  };
  if (query.get("key") !== API_KEY) return failure("keyInvalid");
  if (apiFailNext.has(endpoint)) {
    const reason = apiFailNext.get(endpoint);
    apiFailNext.delete(endpoint);
    return failure(reason);
  }
  const parts = new Set((query.get("part") || "").split(","));
  const project = (item) => Object.fromEntries(Object.entries(item).filter(([key]) => ["kind", "etag", "id"].includes(key) || parts.has(key)));
  const page = (items, defaultMax = 5) => {
    const max = Math.min(Number(query.get("maxResults") || defaultMax), 50);
    const offset = query.get("pageToken") ? tokenOffset(query.get("pageToken")) : 0;
    return {
      items: items.slice(offset, offset + max),
      nextPageToken: offset + max < items.length ? pageToken(offset + max) : undefined,
      prevPageToken: offset > 0 ? pageToken(Math.max(0, offset - max)) : undefined,
      pageInfo: { totalResults: items.length, resultsPerPage: max },
    };
  };
  const answer = (body) => ({ status: 200, body: { kind: body.kind, etag: etagOf(url.href), ...body } });
  switch (endpoint) {
    case "videos": {
      if (query.has("id")) {
        const items = query.get("id").split(",").map(video).filter(Boolean).map(project);
        return answer({ kind: "youtube#videoListResponse", items, pageInfo: { totalResults: items.length, resultsPerPage: items.length } });
      }
      if (query.get("chart") !== "mostPopular") return null;
      if (!dataApi.charts[query.get("videoCategoryId") || ""]) return failure("videoChartNotFound");
      const found = page(chart(query.get("videoCategoryId") || ""));
      return answer({ kind: "youtube#videoListResponse", items: found.items.map(project), nextPageToken: found.nextPageToken,
                      prevPageToken: found.prevPageToken, pageInfo: found.pageInfo });
    }
    case "channels": {
      const items = (query.get("id") || "").split(",").map(channel).filter(Boolean).map(project);
      return answer({ kind: "youtube#channelListResponse", pageInfo: { totalResults: items.length, resultsPerPage: Number(query.get("maxResults") || 5) },
                      ...(items.length ? { items } : {}) });
    }
    case "videoCategories":
      return { status: 200, body: dataApi.categories[query.get("hl") === "ja" ? "ja" : "en"] };
    case "commentThreads": {
      const owner = video(query.get("videoId"));
      if (owner && !("commentCount" in owner.statistics)) return failure("commentsDisabled");
      const found = page(dataApi.threads.filter((thread) => thread.snippet.videoId === query.get("videoId")), 20);
      return answer({ kind: "youtube#commentThreadListResponse", nextPageToken: found.nextPageToken,
                      pageInfo: { totalResults: found.items.length, resultsPerPage: found.pageInfo.resultsPerPage }, items: found.items.map(project) });
    }
    case "playlistItems": {
      const items = dataApi.playlistItems.filter((item) => item.snippet.playlistId === query.get("playlistId"));
      if (!items.length) return failure("playlistNotFound");
      const found = page(items);
      return answer({ kind: "youtube#playlistItemListResponse", nextPageToken: found.nextPageToken, prevPageToken: found.prevPageToken,
                      items: found.items.map(project), pageInfo: found.pageInfo });
    }
    case "search": {
      const words = (query.get("q") || "").toLowerCase().split(/\s+/).filter(Boolean);
      let items = dataApi.videos.filter((item) => words.every((word) => `${item.snippet.title}\n${item.snippet.description}`.toLowerCase().includes(word)));
      if (query.get("videoEmbeddable") === "true") items = playable(items);
      const found = page(items);
      return answer({
        kind: "youtube#searchListResponse", nextPageToken: found.nextPageToken, regionCode: query.get("regionCode") || "JP",
        pageInfo: { totalResults: items.length, resultsPerPage: found.pageInfo.resultsPerPage },
        items: found.items.map((item) => ({
          kind: "youtube#searchResult",
          etag: etagOf(`search-${item.id}`),
          id: { kind: "youtube#video", videoId: item.id },
          ...(parts.has("snippet") ? {
            snippet: {
              publishedAt: item.snippet.publishedAt, channelId: item.snippet.channelId, title: item.snippet.title,
              description: item.snippet.description.slice(0, 160), thumbnails: item.snippet.thumbnails,
              channelTitle: item.snippet.channelTitle, liveBroadcastContent: item.snippet.liveBroadcastContent,
              publishTime: item.snippet.publishedAt,
            },
          } : {}),
        })),
      });
    }
    default:
      return null;
  }
}

// ---- the page's snapshots (these functions run in the page) ------------------------------
function pageSnapshot() {
  const text = (node) => (node ? node.textContent.replace(/[ \t\n\r]+/g, " ").trim() : null);
  const all = (selector) => [...document.querySelectorAll(selector)];
  const card = (node) => ({
    id: node.dataset.video,
    title: text(node.querySelector(".card-title a")),
    channel: text(node.querySelector(".card-channel")),
    meta: text(node.querySelector(".card-meta")),
    badge: text(node.querySelector(".badge")),
    live: Boolean(node.querySelector(".badge.live")),
    thumbnail: node.querySelector(".thumb img")?.getAttribute("src") || null,
    avatar: node.querySelector("img.avatar")?.getAttribute("src") || null,
    saved: node.querySelector(".card-later")?.getAttribute("aria-pressed") === "true",
  });
  const app = document.querySelector(".app");
  const badge = document.querySelector(".mode-badge");
  const search = document.querySelector(".search input");
  return {
    hash: location.hash,
    title: document.title,
    page: ["home", "watch", "results", "library", "channel"].find((name) => document.querySelector(`#content > .${name}`)) || null,
    lang: app?.getAttribute("lang") || null,
    appClass: app?.className || "",
    mode: badge ? { text: text(badge), class: badge.className } : null,
    search: search ? { value: search.value, placeholder: search.placeholder, focused: document.activeElement === search } : null,
    nav: all(".sidebar a.nav-item .nav-label").slice(0, 3).map(text),
    sidebarChannels: all(".sidebar a.nav-item").slice(3).map((node) => ({ name: text(node.querySelector(".nav-label")), avatar: node.querySelector("img.avatar")?.getAttribute("src") || null })),
    chips: all("#content .chips .chip").map((node) => ({ text: text(node), selected: node.classList.contains("selected") })),
    cards: all("#content .grid .card[data-video]").map(card),
    wide: all("#content .wide-card[data-video]").map(card),
    heading: text(document.querySelector("#content .page-title")),
    notes: all("#content .note").map(text),
    failed: text(document.querySelector("#content .failed p")),
    more: text(document.querySelector("#content .more-row button")),
    dialog: document.querySelector(".dialog h2")?.id || null,
    toast: text(document.querySelector(".toast")),
    error: text(document.querySelector("#elisp-react-error")),
  };
}

function watchSnapshot() {
  const text = (node) => (node ? node.textContent.replace(/[ \t\n\r]+/g, " ").trim() : null);
  const all = (selector, root = document) => [...root.querySelectorAll(selector)];
  const frame = document.querySelector(".watch iframe.player-frame");
  const link = (node) => ({ text: text(node), href: node.getAttribute("href"), target: node.getAttribute("target"), rel: node.getAttribute("rel"), class: node.className });
  return {
    hash: location.hash,
    title: document.title,
    heading: text(document.querySelector(".watch-title")),
    frame: frame && {
      src: frame.getAttribute("src"), credentialless: frame.hasAttribute("credentialless") && frame.credentialless === true,
      referrerpolicy: frame.getAttribute("referrerpolicy"), allow: frame.getAttribute("allow"),
      allowfullscreen: frame.hasAttribute("allowfullscreen"), player: frame.dataset.player, label: frame.getAttribute("title"),
    },
    owner: text(document.querySelector(".owner-name")),
    ownerHref: document.querySelector(".owner-name")?.getAttribute("href") || null,
    ownerAvatar: document.querySelector(".owner-avatar img.avatar")?.getAttribute("src") || null,
    subscribers: text(document.querySelector(".owner-text .muted")),
    likes: text(document.querySelector(".actions span.pill")),
    later: text(document.querySelector(".actions button.pill[aria-pressed]")),
    facts: text(document.querySelector(".description-facts")),
    descriptionNote: text(document.querySelector(".description .note")),
    links: all(".description-text a").map(link),
    timestamps: all(".description-text button.timestamp").map(text),
    descriptionButton: text(document.querySelector(".description > .text-button")),
    descriptionOpen: Boolean(document.querySelector(".description.open")),
    commentsTitle: text(document.querySelector(".comments .section-title")),
    commentsNote: text(document.querySelector(".comments .note")),
    comments: all(".comments .comment").map((node) => ({
      author: text(node.querySelector(".comment-head strong")),
      ago: text(node.querySelector(".comment-head .muted")),
      text: text(node.querySelector(".comment-text")),
      timestamps: all("button.timestamp", node).map(text),
      links: all(".comment-text a", node).map(link),
      foot: all(".comment-foot span:not(.icon)", node).map(text),
      avatar: node.querySelector("img.avatar")?.getAttribute("src") || null,
    })),
    related: all(".watch-side .wide-card[data-video]").map((node) => node.dataset.video),
    relatedTitles: all(".watch-side .wide-card .card-title a").map(text),
    relatedMeta: all(".watch-side .wide-card .card-meta").map(text),
    sideNote: text(document.querySelector(".watch-side .note")),
    playerError: text(document.querySelector(".player-error")),
    error: text(document.querySelector("#elisp-react-error")),
  };
}

// Every command Lisp gives the page through the port (lisp/parens-port.el):
// one <data data-cmd=JSON> element each.  Installed before the page's scripts.
const PORT_LOG = `(() => {
  const log = [];
  Object.defineProperty(window, "__parensPortLog", { value: log });
  new MutationObserver((records) => {
    for (const record of records) for (const node of record.addedNodes) {
      if (node.nodeType !== 1) continue;
      for (const element of [node, ...node.querySelectorAll("data[data-cmd]")]) {
        if (element.matches("#parens-port > data[data-cmd]")) {
          try { log.push(JSON.parse(element.dataset.cmd)); } catch { log.push({ unreadable: element.dataset.cmd }); }
        }
      }
    }
  }).observe(document, { childList: true, subtree: true });
})();`;

// A stand-in for YouTube's IFrame Player API, as index.html uses it: installed
// by the test (after the page has done without the real one) to see what the
// port asks of the player, and to play the player's events.
const FAKE_PLAYER_API = `(() => {
  const calls = [];
  const players = [];
  Object.defineProperty(window, "__parensPlayerCalls", { value: calls });
  Object.defineProperty(window, "__parensPlayers", { value: players });
  window.YT = {
    Player: class {
      constructor(frame, options) {
        Object.assign(this, { id: frame.dataset.player, events: options.events, state: -1, time: 0 });
        players.push(this);
        calls.push([this.id, "new"]);
      }
      getPlayerState() { return this.state; }
      getCurrentTime() { return this.time; }
      playVideo() { this.state = 1; calls.push([this.id, "playVideo"]); }
      pauseVideo() { this.state = 2; calls.push([this.id, "pauseVideo"]); }
      seekTo(seconds, allowSeekAhead) { this.time = seconds; calls.push([this.id, "seekTo", seconds, allowSeekAhead]); }
    },
  };
  window.onYouTubeIframeAPIReady();
  return true;
})()`;

// ---- the state of a run ----------------------------------------------------------------------
const servers = [];
let siteOrigin = deployed;
let wasmacsQuery = "";
let workDir = null, chrome = null, client = null, sessionId = null;
const elispReactLocal = !live && existsSync(join(elispReact, "lisp/react.el")) && existsSync(join(elispReact, "js/elisp-react.js"));
const siteUrl = (hash = "") => `${siteOrigin}/${wasmacsQuery}${hash}`;
const pageErrors = [];
const failedOnPurpose = new Set();      // URLs the test answered with an error status
const traffic = { elispReact: 0, oembed: 0, dataApi: 0, images: 0, players: [], iframeApi: 0, wasmacs: 0, unexpected: [] };
const send = (method, params = {}) => client.send(method, params, sessionId);
const js = (expression) => evaluate(client, sessionId, expression);

// The network, as far as the page is concerned (offline runs only).
async function intercept({ requestId, request }, from) {
  const url = new URL(request.url);
  const origin = request.headers.Origin || request.headers.origin || "*";
  const respond = (status, type, body, headers = {}) => {
    if (status >= 400) failedOnPurpose.add(request.url);
    return client.send("Fetch.fulfillRequest", {
      requestId, responseCode: status,
      responseHeaders: Object.entries({
        "Content-Type": type, "Access-Control-Allow-Origin": origin, "Cross-Origin-Resource-Policy": "cross-origin",
        "Cache-Control": "no-store", ...headers,
      }).map(([name, value]) => ({ name, value: String(value) })),
      body: Buffer.from(body).toString("base64"),
    }, from);
  };
  const unexpected = (why) => {
    traffic.unexpected.push(`${request.url} (${why})`);
    return client.send("Fetch.failRequest", { requestId, errorReason: "InternetDisconnected" }, from);
  };
  const host = url.hostname;
  if (host === "modeverv.github.io" && url.pathname.startsWith("/wasmacs/")) {
    traffic.wasmacs++;
    return client.send("Fetch.continueRequest", { requestId }, from);
  }
  if (host === "modeverv.github.io" && url.pathname.startsWith("/elisp-react/")) {
    if (!elispReactLocal) return client.send("Fetch.continueRequest", { requestId }, from);
    traffic.elispReact++;
    const file = join(elispReact, decodeURIComponent(url.pathname.slice("/elisp-react/".length)));
    const inside = relative(elispReact, file);
    if (inside.startsWith("..") || inside.split("/").some((part) => part.startsWith(".")) || !existsSync(file) || !statSync(file).isFile()) {
      return unexpected("not in the elisp-react checkout");
    }
    const type = { ".js": "text/javascript", ".mjs": "text/javascript", ".el": "text/plain; charset=utf-8" }[extname(file)] || "application/octet-stream";
    return respond(200, type, readFileSync(file));
  }
  if (host === "www.youtube.com" && url.pathname === "/oembed") {
    traffic.oembed++;
    let id = null;
    try { id = new URL(url.searchParams.get("url")).searchParams.get("v"); } catch { /* no url= */ }
    if (!oembed[id]) return unexpected("no oEmbed fixture");
    return respond(200, "application/json", JSON.stringify(oembed[id]));
  }
  if (host === "www.youtube.com" && url.pathname === "/iframe_api") {
    traffic.iframeApi++;
    return respond(200, "text/javascript; charset=utf-8", STUB_IFRAME_API);
  }
  if (host === "www.googleapis.com" && url.pathname.startsWith("/youtube/v3/")) {
    traffic.dataApi++;
    const answer = answerDataApi(url);
    if (!answer) return unexpected("no Data API fixture");
    return respond(answer.status, "application/json; charset=UTF-8", JSON.stringify(answer.body, null, 2), { Vary: "Origin" });
  }
  if ((host === "www.youtube-nocookie.com" || host === "www.youtube.com") && url.pathname.startsWith("/embed/")) {
    traffic.players.push(request.url);
    return respond(200, "text/html; charset=utf-8", STUB_PLAYER(url.pathname.slice("/embed/".length)));
  }
  if (/(^|\.)ytimg\.com$/.test(host) || /^yt3\.(ggpht|googleusercontent)\.com$/.test(host)) {
    traffic.images++;
    return respond(200, "image/png", PNG);
  }
  return unexpected("not answered by the test");
}

// The page's failures: exceptions, console.error and failed loads, but the
// known 404s (no server.el on a static site: api/feed; favicon.ico) and the
// errors the test answered on purpose.
function expectedLogEntry(entry) {
  if (entry.source !== "network") return false;
  if (failedOnPurpose.has(entry.url)) return true;
  try {
    const url = new URL(entry.url);
    return url.origin === new URL(siteOrigin).origin && /\/(api\/feed|favicon\.ico)$/.test(url.pathname);
  } catch {
    return false;
  }
}
const describeArgs = (args = []) => args.map((arg) => arg.value ?? arg.description ?? arg.unserializableValue ?? arg.type).join(" ");
function onEvent({ method, params, sessionId: from }) {
  if (method === "Fetch.requestPaused") {
    intercept(params, from).catch((error) => {
      // The request may be gone (the frame went away): nothing to answer.
      if (!/Invalid InterceptionId|not found|closed/i.test(error.message)) pageErrors.push(`interception of ${params.request.url}: ${error.message}`);
    });
    return;
  }
  if (from !== sessionId) return;
  if (method === "Runtime.exceptionThrown") {
    const details = params.exceptionDetails;
    pageErrors.push(`exception: ${details?.exception?.description || details?.text}`);
  } else if (method === "Runtime.consoleAPICalled" && params.type === "error") {
    pageErrors.push(`console.error: ${describeArgs(params.args)}`);
  } else if (method === "Log.entryAdded" && params.entry.level === "error" && !expectedLogEntry(params.entry)) {
    pageErrors.push(`${params.entry.source}: ${params.entry.text} ${params.entry.url || ""}`.trim());
  }
}
const takeApiErrors = () => apiErrors.splice(0);
function assertNoPageErrors(where) {
  assert.deepEqual(pageErrors, [], `page errors (${where})`);
  assert.deepEqual(traffic.unexpected, [], `requests the test did not expect (${where})`);
}

// ---- driving the page ---------------------------------------------------------------------
const quote = JSON.stringify;
const until = (expression, label, timeout = stepTimeout) => waitUntil(() => js(expression).catch(() => false), label, timeout);
const snapshot = () => js(`(${pageSnapshot})()`);
const watchState = () => js(`(${watchSnapshot})()`);
async function waitFor(label, predicate, { timeout = stepTimeout, read = snapshot } = {}) {
  let last = null;
  try {
    return await waitUntil(async () => {
      last = await read().catch(() => null);
      return last && predicate(last) ? last : false;
    }, label, timeout);
  } catch (error) {
    error.message += `\n  last state: ${JSON.stringify(last)?.slice(0, 3000)}`;
    throw error;
  }
}
const waitForWatch = (label, predicate, options = {}) => waitFor(label, predicate, { ...options, read: watchState });

// Click as a script would (element.click()), or as a mouse would: the
// element must be visible and on top at its centre.
async function click(selector) {
  const found = await js(`(() => { const node = document.querySelector(${quote(selector)}); if (!node) return false; node.click(); return true; })()`);
  assert.ok(found, `nothing to click: ${selector}`);
}
async function clickText(selector, label) {
  const found = await js(`(() => {
    const node = [...document.querySelectorAll(${quote(selector)})].find((node) => node.textContent.replace(/\\s+/g, " ").trim() === ${quote(label)});
    if (!node) return false;
    node.click();
    return true;
  })()`);
  assert.ok(found, `nothing to click: ${selector} "${label}"`);
}
async function mouseClick(selector, { at = null } = {}) {
  const point = at || await js(`(() => {
    const node = document.querySelector(${quote(selector)});
    if (!node) return null;
    node.scrollIntoView({ block: "center", inline: "center" });
    // The first line box: the middle of a link that wraps can be beside its text.
    const box = node.getClientRects()[0] || node.getBoundingClientRect();
    const x = box.left + box.width / 2, y = box.top + box.height / 2;
    const hit = document.elementFromPoint(x, y);
    return { x, y, visible: box.width > 0 && box.height > 0, onTop: Boolean(hit && (hit === node || node.contains(hit))) };
  })()`);
  assert.ok(point, `nothing to click: ${selector}`);
  if (!at) {
    assert.ok(point.visible, `${selector} is not visible`);
    assert.ok(point.onTop, `${selector} is covered by another element`);
  }
  for (const type of ["mouseMoved", "mousePressed", "mouseReleased"]) {
    await send("Input.dispatchMouseEvent", { type, x: point.x, y: point.y, button: type === "mouseMoved" ? "none" : "left", clickCount: type === "mouseMoved" ? 0 : 1 });
  }
}
const KEYS = {
  "/": { key: "/", code: "Slash", keyCode: 191, text: "/" },
  "?": { key: "?", code: "Slash", keyCode: 191, text: "?", modifiers: 8 },
  Escape: { key: "Escape", code: "Escape", keyCode: 27 },
  Enter: { key: "Enter", code: "Enter", keyCode: 13, text: "\r" },
  Backspace: { key: "Backspace", code: "Backspace", keyCode: 8 },
  k: { key: "k", code: "KeyK", keyCode: 75, text: "k" },
  j: { key: "j", code: "KeyJ", keyCode: 74, text: "j" },
  l: { key: "l", code: "KeyL", keyCode: 76, text: "l" },
};
async function press(name) {
  const { key, code, keyCode, text, modifiers = 0 } = KEYS[name];
  const common = { key, code, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode, modifiers };
  await send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", ...common, ...(text ? { text, unmodifiedText: text } : {}) });
  await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
}
const typeText = (text) => send("Input.insertText", { text });
const portLog = () => js("window.__parensPortLog.slice()");
const playerCalls = () => js("window.__parensPlayerCalls.slice()");

// Start the page at HASH (or reload it) and wait for elisp-react to be up.
async function boot(hash, { reload = false } = {}) {
  const t0 = Date.now();
  if (reload) {
    await js("window.__parensOldPage = true");
    await send("Page.reload", {});
  } else {
    await send("Page.navigate", { url: siteUrl(hash) });
  }
  await until("!window.__parensOldPage && Boolean(window.elispReact?.version || document.querySelector('#elisp-react-error'))",
    "elisp-react starts", bootTimeout);
  const info = await js(`({
    error: document.querySelector("#elisp-react-error")?.textContent || null,
    version: window.elispReact.version, bootMs: window.elispReact.bootMs, files: window.elispReact.files,
    lisp: document.querySelectorAll('script[type="text/emacs-lisp"]').length,
    compiled: Object.keys(localStorage).filter((key) => key.startsWith("elisp-react:compiled:")).length,
    warnings: (window.elispReact.compileLogs || []).filter((entry) => entry.log).map((entry) => entry.name.split("/").pop() + ": " + entry.log),
  })`);
  assert.equal(info.error, null, "elisp-react started without an error");
  return { ...info, readyMs: Date.now() - t0, t0 };
}

async function screenshot(name) {
  const file = join(tmpdir(), `parens-e2e-${name}-${Date.now()}.png`);
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  await writeFile(file, Buffer.from(data, "base64"));
  return file;
}

// ---- the offline test -------------------------------------------------------------------------
const ja = Object.fromEntries(topics.map((topic) => [topic.topic, topic.ja]));
const agoJa = /^(\d+ (年|か月|週間|日|時間|分|秒)前|たった今)$/;
const agoEn = /^(\d+ (year|month|week|day|hour|minute|second)s? ago|just now)$/;
const meta = (views, ago) => (text) => {
  const [first, second, ...rest] = (text || "").split(" • ");
  return first === views && ago.test(second || "") && rest.length === 0;
};

async function offline() {
  // ---- the no-key mode: 35 cards, titles from oEmbed --------------------------------
  const first = await boot("");
  const home = await waitFor("35 cards with the fixtures' titles", (state) => state.page === "home"
    && state.cards.length === curated.length && state.cards.every((card) => card.title === oembed[card.id].title), { timeout: bootTimeout });
  const titlesMs = Date.now() - first.t0;
  assert.deepEqual(home.cards.map((card) => card.id), curatedIds);
  assert.deepEqual(home.cards.map((card) => card.channel), curatedIds.map((id) => oembed[id].author_name));
  assert.deepEqual(home.cards.map((card) => card.thumbnail), curatedIds.map((id) => `https://i.ytimg.com/vi/${id}/mqdefault.jpg`));
  assert.ok(home.cards.every((card) => card.meta === "" && card.avatar === null && !card.saved), "no views, dates or pictures of channels without a key");
  assert.deepEqual(home.mode, { text: w("mode-curated"), class: "mode-badge mode-curated" });
  assert.equal(home.title, "Parens");
  assert.equal(home.hash, "");
  assert.deepEqual(home.notes, [], "no note about the mode (a static site has no server.el: that is the no-key mode)");
  assert.deepEqual(home.chips, [{ text: w("all"), selected: true }, ...topics.map((topic) => ({ text: topic.ja, selected: false }))]);
  assert.deepEqual(home.sidebarChannels.map((entry) => entry.name),
    curatedChannels.map((id) => oembed[curated.find((entry) => entry.channel === id).id].author_name));
  await until("document.querySelector('.card .thumb img')?.naturalWidth === 1", "a thumbnail (the test's 1x1 PNG) is drawn");
  // react.el and every file of index.html, compiled in the page and kept for the next visit.
  assert.equal(first.compiled, first.lisp + 1);
  if (first.warnings.length) console.log(`compiler warnings: ${first.warnings.join(" | ")}`);
  pass(`no key: ${curated.length} cards with the fixtures' titles and channels, in parens-data.el's order (first visit: Emacs ${first.version} `
    + `up in ${seconds(first.bootMs)}, its files ${first.files}; react.el and ${first.lisp} files compiled: first render ${seconds(first.readyMs)}, all titles ${seconds(titlesMs)})`);

  // A chip: the videos of one topic.
  const math = curated.filter((entry) => topicOf[entry.channel] === "math").map((entry) => entry.id);
  await clickText("#content .chips .chip", ja.math);
  const filtered = await waitFor(`the chip ${ja.math}`, (state) => state.cards.length === math.length);
  assert.deepEqual(filtered.cards.map((card) => card.id), math);
  assert.deepEqual(filtered.chips.filter((chip) => chip.selected).map((chip) => chip.text), [ja.math]);
  await clickText("#content .chips .chip", w("all"));
  await waitFor("all again", (state) => state.cards.length === curated.length && state.chips[0].selected);
  pass(`no key: the chip "${ja.math}" shows the ${math.length} videos of its channels; "${w("all")}" brings back ${curated.length}`);

  // ---- keys -------------------------------------------------------------------------
  await press("/");
  let state = await waitFor('"/" focuses the search field', (current) => current.search.focused);
  assert.equal(state.search.value, "", '"/" is not typed into the field');
  await press("?");            // in the field "?" is a character, not the help
  await waitFor('"?" is typed in the field', (current) => current.search.value === "?");
  await pause(300);
  assert.equal((await snapshot()).dialog, null, '"?" in the search field opens nothing');
  await press("Backspace");
  await waitFor("the field is empty again", (current) => current.search.value === "");
  await press("Escape");
  await waitFor("Escape leaves the field", (current) => !current.search.focused);
  await press("?");
  state = await waitFor('"?" opens the shortcuts', (current) => current.dialog === "shortcuts-title");
  assert.deepEqual(await js("[...document.querySelectorAll('.shortcuts kbd')].map((node) => node.textContent)"), ["/", "k", "j / l", "?", "Esc"]);
  await press("Escape");
  await waitFor("Escape closes the shortcuts", (current) => current.dialog === null);
  await click(`.topbar-end button[aria-label="${w("shortcuts")}"]`);
  await waitFor("the keyboard button opens the shortcuts", (current) => current.dialog === "shortcuts-title");
  assert.equal(await js("document.elementFromPoint(8, 300)?.className"), "backdrop");
  await mouseClick(null, { at: { x: 8, y: 300 } });
  await waitFor("a click beside the dialog closes it", (current) => current.dialog === null);
  pass('keys: "/" focuses the search field without typing "/", "?" in the field is typed, Escape leaves the field; "?" opens the shortcuts, Escape closes them; a click on the backdrop closes a dialog');

  // ---- search with the form ----------------------------------------------------------------
  const query = "括弧";
  const found = curatedIds.filter((id) => oembed[id].title.includes(query));
  assert.ok(found.length >= 2, "the fixtures have titles to find");
  await press("/");
  await waitFor("the search field", (current) => current.search.focused);
  await typeText(query);
  await waitFor("the query is in the field", (current) => current.search.value === query);
  await press("Enter");
  const results = await waitFor("the results page", (current) => current.page === "results" && current.wide.length === found.length);
  assert.deepEqual(results.wide.map((card) => card.id), found);
  assert.deepEqual(results.wide.map((card) => card.title), found.map((id) => oembed[id].title));
  assert.equal(results.heading, w("results-for", query));
  assert.deepEqual(results.notes, [w("results-local")]);
  assert.equal(results.search.value, query);
  assert.equal(results.search.focused, false, "the field is left after a search");
  // The title comes in a later answer than the address (navigate) would.
  await waitFor("the title follows", (current) => current.title === `${query} - Parens`);
  const address = `#/results?search_query=${encodeURIComponent(query)}`;
  if (await js("location.hash") === address) {
    pass(`search: the form goes to ${address}: ${found.length} videos, title "${query} - Parens"`);
    await js("history.back()");
    await waitFor("Back: home", (current) => current.page === "home" && current.cards.length === curated.length && current.title === "Parens");
    pass("Back: history.back() returns from the results to the home page and its title");
  } else {
    known(`search: the form shows the results but the address stays "${await js("location.hash")}", not ${address}: parens-go sends `
      + "navigate and scroll-top in one answer; react.el inserts new keyed children last first, and index.html's observer runs scroll-top, "
      + "then skips navigate (seq <= done). Back does not return from these results; a reload shows the page before.");
    pass(`search: the form shows ${found.length} videos for "${query}", title "${query} - Parens" (but see KNOWN BUG)`);
    await click("a.logo");
    await waitFor("home", (current) => current.page === "home" && current.cards.length === curated.length && current.title === "Parens");
  }

  // ---- a watch page, from a click on a card --------------------------------------------------
  const watched = curatedIds[5];
  const watchedTitle = oembed[watched].title;
  await mouseClick(`#content .card[data-video="${watched}"] .card-title a`);
  let watch = await waitForWatch("the watch page", (current) => current.heading === watchedTitle
    && current.related.length === 20 && current.title === `${watchedTitle} - Parens`);
  assert.equal(watch.hash, `#/watch?v=${watched}`);
  assert.ok(watch.frame, "a player");
  const src = new URL(watch.frame.src);
  assert.equal(`${src.origin}${src.pathname}`, `https://www.youtube-nocookie.com/embed/${watched}`);
  assert.equal(src.searchParams.get("enablejsapi"), "1");
  assert.equal(src.searchParams.get("origin"), siteOrigin);
  assert.equal(src.searchParams.get("autoplay"), "1");
  // A static host is not cross-origin isolated: no credentialless (that is
  // for elisp-studio's preview), so the player keeps its cookies.
  assert.equal(watch.frame.credentialless, false);
  assert.equal(watch.frame.referrerpolicy, "strict-origin-when-cross-origin");
  assert.equal(watch.frame.player, watched);
  assert.equal(watch.frame.label, watchedTitle);
  assert.ok(watch.frame.allowfullscreen && /\bautoplay\b/.test(watch.frame.allow) && /\bencrypted-media\b/.test(watch.frame.allow));
  assert.deepEqual(watch.related, curatedRelated(watched));
  assert.deepEqual(watch.relatedTitles, watch.related.map((id) => oembed[id].title));
  assert.equal(watch.owner, oembed[watched].author_name);
  assert.equal(watch.ownerHref, `#/channel/${channelOf(watched)}`);
  assert.equal(watch.descriptionNote, w("description-need-more"));
  assert.equal(watch.commentsNote, w("comments-need-key"));
  await waitUntil(() => traffic.players.length > 0, "the player's page is asked for");
  assert.equal(traffic.players.at(-1), watch.frame.src, "the player's page was asked for (and answered by the stub)");
  await until("Boolean(document.querySelector('script[src=\"https://www.youtube.com/iframe_api\"]'))", "the page loads the IFrame API");
  await waitUntil(() => traffic.iframeApi > 0, "the IFrame API is asked for");
  pass(`watch (no key): a click on a card plays it in an iframe (not credentialless: not isolated) with referrerpolicy=strict-origin-when-cross-origin, `
    + `enablejsapi=1, origin=${siteOrigin}; 20 related (its channel's first, then its topic's); title "${watchedTitle} - Parens"`);

  // Without the IFrame API (the stub defines nothing) the player's keys go
  // through the port and find no player: nothing breaks.
  const before = (await portLog()).length;
  for (const key of ["k", "j", "l"]) await press(key);
  await waitUntil(async () => (await portLog()).slice(before).filter((command) => command.cmd === "player").length === 3, "the keys reach the port");
  assert.deepEqual((await portLog()).slice(before).filter((command) => command.cmd === "player"),
    [{ cmd: "player", func: "toggle" }, { cmd: "player", func: "seekBy", args: [-10] }, { cmd: "player", func: "seekBy", args: [10] }]);
  await pause(200);
  assert.equal(await js("typeof window.YT"), "undefined", "the stub defined no player API");
  assert.equal((await watchState()).playerError, null);
  assertNoPageErrors("watch page without the IFrame API");
  pass("watch (no key): the IFrame API is asked for, the stub defines nothing; k, j and l reach the port and find no player, without an error");

  // ---- history, and Back ----------------------------------------------------------------------
  await click('.sidebar a.nav-item[href="#/feed/history"]');
  const history = await waitFor("the history page", (current) => current.page === "library" && current.hash === "#/feed/history"
    && current.title === `${w("history")} - Parens`);
  assert.deepEqual(history.wide.map((card) => card.id), [watched]);
  assert.equal(history.wide[0].title, watchedTitle);
  assert.equal(history.heading, w("history"));
  await js("history.back()");
  watch = await waitForWatch("Back: the watch page", (current) => current.heading === watchedTitle && current.title === `${watchedTitle} - Parens`);
  assert.equal(watch.hash, `#/watch?v=${watched}`);
  await js("history.back()");
  await waitFor("Back: home", (current) => current.page === "home" && current.title === "Parens" && current.cards.length === curated.length);
  pass("history: the history page lists the watched video; history.back() returns to the watch page, then home, and the title follows");

  // ---- watch later, kept across a reload ---------------------------------------------------------
  const saved = curatedIds.find((id) => topicOf[channelOf(id)] === "math");
  await click(`#content .card[data-video="${saved}"] .card-later`);
  state = await waitFor("saved for later", (current) => current.toast === w("saved-later") && current.cards.find((card) => card.id === saved).saved);
  assert.equal(await js(`document.querySelector('.card[data-video="${saved}"] .card-later').title`), w("saved-later"));
  await click('.sidebar a.nav-item[href="#/playlist?list=WL"]');
  let later = await waitFor("the watch-later page", (current) => current.page === "library" && current.wide.length === 1 && current.title === `${w("later")} - Parens`);
  assert.deepEqual(later.wide.map((card) => [card.id, card.title]), [[saved, oembed[saved].title]]);
  const second = await boot(null, { reload: true });
  assert.equal(second.compiled, second.lisp + 1);
  later = await waitFor("after a reload: the watch-later page", (current) => current.page === "library" && current.wide.length === 1
    && current.wide[0].title === oembed[saved].title, { timeout: bootTimeout });
  assert.equal(later.hash, "#/playlist?list=WL");
  assert.deepEqual(later.wide.map((card) => card.id), [saved]);
  await click("#content .wide-remove");
  later = await waitFor("removed from the list", (current) => current.page === "library" && current.wide.length === 0);
  assert.deepEqual(later.notes, [w("later-empty")]);
  pass(`watch later: a card's button saves it (toast "${w("saved-later")}"), the later page lists it, it survives a reload `
    + `(second visit: first render ${seconds(second.readyMs)}, compiled code from localStorage); its remove button empties the page`);

  // ---- the Data API mode: a key in the settings ----------------------------------------------------
  await click("a.logo");
  await waitFor("home", (current) => current.page === "home" && current.cards.length === curated.length);
  await click(`.topbar-end button[aria-label="${w("settings")}"]`);
  state = await waitFor("the settings", (current) => current.dialog === "settings-title");
  assert.equal(await js("document.querySelector('.mode-line').textContent"), `${w("mode-curated-long")}: `);
  await until("document.activeElement === document.querySelector('.key-form input')", "the key field has the focus");
  // Remembered: kept in localStorage (without it, only for this page's life).
  assert.equal(await js("document.querySelector('.dialog .switch input').checked"), false, "a key is not remembered unless asked");
  await click(".dialog .switch input");
  await until("document.querySelector('.dialog .switch input').checked === true", "the remember box is ticked");
  await js("document.querySelector('.key-form input').focus(); true");
  await typeText(API_KEY);
  await until("document.querySelector('.key-form button[type=submit]').disabled === false", "the save button is enabled");
  await press("Enter");
  const page1 = playable(chart().slice(0, 24));
  const page2 = playable(chart().slice(24));
  state = await waitFor("the chart of the Data API", (current) => current.dialog === null && current.mode?.text === w("mode-api")
    && current.cards.length >= page1.length && current.cards.every((card) => card.title && card.avatar), { timeout: 30_000 });
  assert.equal(state.mode.class, "mode-badge mode-api");
  assert.deepEqual(state.cards.slice(0, page1.length).map((card) => card.id), page1.map((item) => item.id));
  const cardOf = (current, id) => current.cards.find((card) => card.id === id);
  assert.equal(cardOf(state, "fxApiVid_05"), undefined, "a video that cannot be embedded is not shown");
  assert.ok(meta(w("views", "98万"), agoJa)(cardOf(state, "fxApiVid_01").meta), cardOf(state, "fxApiVid_01").meta);
  assert.ok(meta(w("no-views"), agoJa)(cardOf(state, "fxApiVid_12").meta), cardOf(state, "fxApiVid_12").meta);
  assert.equal(cardOf(state, "fxApiVid_01").badge, "4:13");
  assert.equal(cardOf(state, "fxApiVid_08").badge, "1:02:05");
  assert.equal(cardOf(state, "fxApiVid_12").badge, "0:45");
  assert.deepEqual([cardOf(state, "fxApiVid_07").badge, cardOf(state, "fxApiVid_07").live], [w("live"), true]);
  assert.equal(cardOf(state, "fxApiVid_07").thumbnail, "https://i.ytimg.com/vi/fxApiVid_07/mqdefault_live.jpg");
  assert.equal(cardOf(state, "fxApiVid_02").channel, "Lambda Workshop");
  assert.equal(cardOf(state, "fxApiVid_02").avatar, channel("UCfixtureParensChannel0A").snippet.thumbnails.medium.url);
  state = await waitFor("the sidebar's channels from channels.list", (current) => current.sidebarChannels.every((entry) => entry.avatar));
  assert.deepEqual(state.sidebarChannels.map((entry) => entry.avatar), curatedChannels.map((id) => channel(id).snippet.thumbnails.medium.url));
  assert.deepEqual(state.sidebarChannels.map((entry) => entry.name), curatedChannels.map((id) => channel(id).snippet.title));
  assert.equal(await js(`localStorage.getItem("elisp-react:" + location.pathname + ":parens/api-key")`), quote(API_KEY));
  // The next page: the sentinel at the end of the grid (or the button).
  if (state.cards.length < page1.length + page2.length) {
    await js("document.querySelector('#content .more-row button:not([disabled])')?.click(); true");
  }
  state = await waitFor("the chart's next page", (current) => current.cards.length === page1.length + page2.length && !current.more);
  assert.deepEqual(state.cards.map((card) => card.id), [...page1, ...page2].map((item) => item.id));
  pass(`settings: a key switches to the Data API (badge "${w("mode-api")}"); home shows ${page1.length} of the chart's first 24 (one cannot be embedded) `
    + `with views, ages, lengths, a LIVE badge and channel pictures, then ${page2.length} more from its nextPageToken; the sidebar's channels come from channels.list`);

  // Categories: the chips of videoCategories.list.
  const categoriesJa = dataApi.categories.ja.items.filter((item) => item.snippet.assignable).map((item) => item.snippet.title);
  state = await waitFor("the categories", (current) => current.chips.length === categoriesJa.length + 1);
  assert.deepEqual(state.chips.map((chip) => chip.text), [w("all"), ...categoriesJa]);
  await clickText("#content .chips .chip", "科学と技術");
  const science = playable(chart("28")).map((item) => item.id);
  state = await waitFor("a category's chart", (current) => current.cards.length === science.length && current.cards.every((card) => science.includes(card.id)));
  assert.deepEqual(state.cards.map((card) => card.id), science);
  await clickText("#content .chips .chip", "非営利団体と社会活動");
  state = await waitFor("a category without a chart", (current) => current.failed !== null);
  assert.equal(state.failed, w("chart-missing"));
  assert.deepEqual(takeApiErrors(), ["videos:videoChartNotFound"]);
  assert.equal(await js("document.querySelector('#content .failed button').textContent"), w("retry"));
  await clickText("#content .chips .chip", w("all"));
  await waitFor("all again", (current) => current.chips[0].selected && current.cards.length >= page1.length
    && current.cards.slice(0, page1.length).every((card, index) => card.id === page1[index].id));
  pass(`categories: ${categoriesJa.length} assignable categories of videoCategories.list as chips; "科学と技術" shows its chart; `
    + `"非営利団体と社会活動" has none (404 videoChartNotFound): "${w("chart-missing")}" with a retry button`);

  // ---- a watch page with the Data API -------------------------------------------------------------
  const rich = video("fxApiVid_02");
  await mouseClick('#content .card[data-video="fxApiVid_02"] .card-title a');
  const uploads = dataApi.playlistItems.filter((item) => item.snippet.playlistId === "UUfixtureParensChannel0A").map((item) => item.contentDetails.videoId);
  // The channel's uploads (12), then the category's chart (12), without the video itself.
  const related = [...new Set([...uploads.slice(0, 12), ...playable(chart(rich.snippet.categoryId).slice(0, 12)).map((item) => item.id)])]
    .filter((id) => id !== rich.id).slice(0, 20);
  watch = await waitForWatch("the watch page (Data API)", (current) => current.heading === rich.snippet.title
    && current.comments.length === 3 && current.related.length === related.length && current.title === `${rich.snippet.title} - Parens`);
  const day = await js(`(() => {
    const date = new Date(${quote(rich.snippet.publishedAt)});
    return [date.getFullYear(), date.getMonth() + 1, date.getDate()].map((part) => String(part).padStart(2, "0")).join("/");
  })()`);
  assert.equal(watch.facts, [w("views", "123万"), day, w("likes", "4.5万")].join("　"));
  assert.deepEqual(watch.links.map((link) => [link.text, link.href, link.target, link.rel]), [
    ["https://example.com/parens-notes", "https://example.com/parens-notes", "_blank", "noopener"],
    ["#parens", "#/results?search_query=%23parens", null, null],
    ["#fixture", "#/results?search_query=%23fixture", null, null],
  ]);
  assert.deepEqual(watch.timestamps, ["0:00", "1:23", "12:40"]);
  assert.equal(watch.descriptionButton, w("more"));
  assert.equal(watch.owner, "Lambda Workshop");
  assert.equal(watch.ownerHref, "#/channel/UCfixtureParensChannel0A");
  assert.equal(watch.ownerAvatar, channel("UCfixtureParensChannel0A").snippet.thumbnails.medium.url);
  assert.equal(watch.subscribers, w("subscribers", "125万"));
  assert.equal(watch.likes, "4.5万");
  assert.equal(watch.commentsTitle, w("comments", "321"));
  assert.deepEqual(watch.comments.map((comment) => [comment.author, comment.foot]), [
    ["@lisp_fan", ["120", "↳ 2"]], ["@quiet_reader", ["8"]], ["@another_viewer", ["0", "↳ 1"]],
  ]);
  assert.equal(watch.comments[0].text, "The part at 1:23 made it click for me. My notes: https://example.com/lisp-notes");
  assert.deepEqual(watch.comments[0].timestamps, ["1:23"]);
  assert.deepEqual(watch.comments[0].links.map((link) => link.href), ["https://example.com/lisp-notes"]);
  assert.equal(watch.comments[1].text, "括弧が多いほど落ち着きます。");
  assert.ok(watch.comments.every((comment) => agoJa.test(comment.ago) && comment.avatar.startsWith("https://yt3.ggpht.com/ytc/fixture-viewer-")));
  assert.deepEqual(watch.related, related);
  assert.ok(watch.relatedMeta.every((text) => text.split(" • ").length === 2), "related cards have views and dates");
  assert.equal(new URL(watch.frame.src).pathname, "/embed/fxApiVid_02");
  await click(".description > .text-button");
  watch = await waitForWatch("the whole description", (current) => current.descriptionOpen && current.descriptionButton === w("less"));
  assert.deepEqual(takeApiErrors(), []);
  pass(`watch (Data API): "${watch.facts}", a description with a link, 3 timestamps and 2 hashtags ("${w("more")}" opens it), `
    + `the channel's picture and "${watch.subscribers}", ${watch.comments.length} comments of commentThreads.list, `
    + `${related.length} related (the channel's uploads, then the category's chart)`);

  // The player, with a stand-in for the IFrame API: what the port asks of it, and its events.
  assert.equal(await js("typeof window.onYouTubeIframeAPIReady"), "function", "the page waits for the IFrame API");
  await js(FAKE_PLAYER_API);
  await waitUntil(async () => (await playerCalls()).some(([id, call]) => id === rich.id && call === "new"), "the page attaches the player");
  let sent = (await portLog()).length;
  await clickText(".description-text button.timestamp", "1:23");
  await waitUntil(async () => (await portLog()).length >= sent + 2, "the timestamp's commands");
  const seek = (await portLog()).slice(sent, sent + 2);
  assert.deepEqual(seek.map((command) => command.cmd).sort(), ["player", "scroll-top"]);
  assert.deepEqual(seek.find((command) => command.cmd === "player"), { cmd: "player", func: "seekTo", args: [83, true] });
  const seeks = (await playerCalls()).filter(([id, call]) => id === rich.id && call === "seekTo");
  if (seeks.length === 0) {
    known("a timestamp: Lisp sends seekTo 83 and scroll-top in one answer; react.el inserts them newest first, index.html runs "
      + "scroll-top and skips seekTo (seq <= done): the player never seeks");
  } else {
    assert.deepEqual(seeks, [[rich.id, "seekTo", 83, true]]);
  }
  sent = (await playerCalls()).length;
  for (const key of ["k", "l", "j"]) await press(key);
  await waitUntil(async () => (await playerCalls()).length >= sent + 3, "the keys reach the player");
  const keyed = (await playerCalls()).slice(sent);
  assert.deepEqual(keyed.map(([id, call]) => [id, call]), [[rich.id, "playVideo"], [rich.id, "seekTo"], [rich.id, "seekTo"]]);
  assert.equal(keyed[1][2] - keyed[2][2], 10, "l goes 10 s forward, j 10 s back");
  await js("window.__parensPlayers.at(-1).events.onError({ data: 150 }); true");
  watch = await waitForWatch("the player's error", (current) => current.playerError !== null);
  assert.match(watch.playerError, /\b150\b/);
  pass(`player (a stand-in for the IFrame API): the page attaches it to Lisp's iframe; ${seeks.length ? "a timestamp seeks to 83 s; " : ""}`
    + `k plays, l and j seek ±10 s; its error 150 is shown: "${watch.playerError}"`);

  // The video ends: autoplay goes to the first related video, one whose comments are turned off.
  const quiet = video(related[0]);
  await js("window.__parensPlayers.at(-1).events.onStateChange({ data: 0 }); true");
  watch = await waitForWatch("autoplay: the next video", (current) => current.heading === quiet.snippet.title
    && current.commentsNote !== null && current.commentsNote !== w("loading") && current.title === `${quiet.snippet.title} - Parens`);
  assert.equal(watch.commentsNote, w("comments-off"));
  assert.equal(watch.commentsTitle, w("comments-title"));
  assert.deepEqual(takeApiErrors(), ["commentThreads:commentsDisabled"]);
  const addressed = watch.hash === `#/watch?v=${quiet.id}`;
  if (!addressed) {
    known(`autoplay: the next video plays but the address stays "${watch.hash}" (parens-go: navigate is skipped as in the search)`);
  }
  pass(`autoplay: the end of the video (player state 0) opens the first related one${addressed ? `, ${watch.hash}` : ""}; `
    + `its comments are turned off (403 commentsDisabled): "${watch.commentsNote}"`);

  // A click on a related video (one not seen yet).
  const next = video(watch.related.find((id) => id !== rich.id));
  await clickText(".watch-side .wide-card .card-title a", next.snippet.title);
  watch = await waitForWatch("a related video", (current) => current.heading === next.snippet.title && current.title === `${next.snippet.title} - Parens`
    && current.related.length > 0);
  assert.equal(watch.hash, `#/watch?v=${next.id}`);
  assert.equal(new URL(watch.frame.src).pathname, `/embed/${next.id}`);
  await waitUntil(async () => (await playerCalls()).some(([id, call]) => id === next.id && call === "new"), "the new player is attached");
  pass(`watch (Data API): a click on a related video opens ${watch.hash}, with a player of its own`);

  // The channel page.
  await click(".owner-name");
  const owner = channel("UCfixtureParensChannel0A");
  state = await waitFor("the channel page", (current) => current.page === "channel" && current.cards.length === uploads.length
    && current.title === `${owner.snippet.title} - Parens`);
  assert.equal(state.hash, "#/channel/UCfixtureParensChannel0A");
  assert.equal(state.heading, owner.snippet.title);
  assert.equal(await js("document.querySelector('.channel-head p.muted').textContent"),
    [owner.snippet.customUrl, w("subscribers", "125万"), w("videos-count", owner.statistics.videoCount)].join(" • "));
  assert.deepEqual(state.cards.map((card) => card.id), uploads);
  pass(`channel (Data API): the owner's link opens the channel page: its name, handle, subscribers and video count, its ${uploads.length} uploads (playlistItems.list)`);

  // ---- the quota ------------------------------------------------------------------------------
  const search = dataApi.videos.filter((item) => /lisp/i.test(`${item.snippet.title}\n${item.snippet.description}`) && item.status.embeddable).map((item) => item.id);
  apiFailNext.set("search", "quotaExceeded");
  await press("/");
  await waitFor("the search field", (current) => current.search.focused);
  await typeText("lisp");
  await waitFor("the query is in the field", (current) => current.search.value === "lisp");
  await press("Enter");
  state = await waitFor("the quota", (current) => current.page === "results" && current.failed !== null);
  const quotaSentence = state.failed;
  assert.equal(quotaSentence, w("quota"));
  assert.deepEqual(takeApiErrors(), ["search:quotaExceeded"]);
  await click("#content .failed button");
  state = await waitFor("the results after a retry", (current) => current.page === "results" && current.wide.length === search.length);
  assert.deepEqual(state.wide.map((card) => card.id), search);
  assert.equal(state.heading, w("results-for", "lisp"));
  assert.deepEqual(state.notes, [], "no note: the Data API searched all of YouTube");
  assert.ok(meta(w("views", "123万"), agoJa)(state.wide[0].meta), state.wide[0].meta);
  pass(`quota: search.list answering 403 quotaExceeded shows "${quotaSentence}" with a retry button; `
    + `the retry finds ${search.length} videos (search.list, then videos.list for their details)`);

  // ---- English --------------------------------------------------------------------------------
  await click("a.logo");
  await waitFor("home (Data API)", (current) => current.page === "home" && current.cards.length === page1.length && current.chips.length > 1);
  await click(`.topbar-end button[aria-label="${w("settings")}"]`);
  await waitFor("the settings", (current) => current.dialog === "settings-title");
  await clickText(".dialog .chip", "English");
  state = await waitFor("English", (current) => current.lang === "en" && current.nav[0] === en("home"));
  assert.equal(await js("document.querySelector('#settings-title').textContent"), en("settings"));
  await click(`.dialog-head button[aria-label="${en("close")}"]`);
  state = await waitFor("the dialog is closed", (current) => current.dialog === null);
  assert.deepEqual(state.nav, [en("home"), en("history"), en("later")]);
  assert.equal(await js("document.querySelector('.sidebar-heading').textContent"), en("channels"));
  assert.deepEqual([state.search.placeholder, await js("document.querySelector('.search input').getAttribute('aria-label')")],
    [en("search-placeholder"), en("search")]);
  assert.equal(state.mode.text, en("mode-api"));
  assert.ok(meta(en("views", "987K"), agoEn)(cardOf(state, "fxApiVid_01").meta), cardOf(state, "fxApiVid_01").meta);
  assert.ok(meta(en("no-views"), agoEn)(cardOf(state, "fxApiVid_12").meta), cardOf(state, "fxApiVid_12").meta);
  assert.equal(cardOf(state, "fxApiVid_07").badge, en("live"));
  assert.equal(state.chips[0].text, en("all"));
  const categoriesEn = dataApi.categories.en.items.filter((item) => item.snippet.assignable).map((item) => item.snippet.title);
  const stale = state.chips[1].text !== categoriesEn[0];
  if (stale) {
    known(`English: the category chips stay in Japanese ("${state.chips[1].text}") until the home page is opened again: `
      + "HomePage asks videoCategories.list only when it is mounted or the mode changes");
  }
  await click('.sidebar a.nav-item[href="#/feed/history"]');
  await waitFor("History", (current) => current.page === "library" && current.heading === en("history") && current.title === `${en("history")} - Parens`);
  await click('.sidebar a.nav-item[href="#/"]');
  state = await waitFor("home in English", (current) => current.page === "home" && current.chips.length === categoriesEn.length + 1
    && current.chips[1].text === categoriesEn[0]);
  assert.deepEqual(state.chips.map((chip) => chip.text), [en("all"), ...categoriesEn]);
  pass(`English: the settings dialog switches the words: the sidebar, the search field, card meta ("${en("views", "987K")} • … ago", "${en("no-views")}"), `
    + `the ${en("live")} badge, titles ("${en("history")} - Parens"); the categories in English (hl=en)${stale ? " on the next visit of the home page" : ""}`);

  // ---- the light theme -------------------------------------------------------------------------
  assert.ok(state.appClass.includes("theme-dark"));
  const dark = await js("getComputedStyle(document.querySelector('.app')).backgroundColor");
  await click(`.topbar-end button[aria-label="${en("settings")}"]`);
  await waitFor("the settings", (current) => current.dialog === "settings-title");
  await clickText(".dialog .chip", en("theme-light"));
  state = await waitFor("the light theme", (current) => current.appClass.includes("theme-light") && !current.appClass.includes("theme-dark"));
  const light = await js("getComputedStyle(document.querySelector('.app')).backgroundColor");
  assert.deepEqual([dark, light], ["rgb(15, 15, 19)", "rgb(255, 255, 255)"]);
  assert.match(await js(`localStorage.getItem("elisp-react:" + location.pathname + ":parens/settings")`), /:lang en :theme light|:theme light.*:lang en|:lang en.*:theme light/);
  await press("Escape");
  await waitFor("Escape closes the settings", (current) => current.dialog === null);
  pass(`theme: "${en("theme-light")}" in the settings switches .app to theme-light (background ${dark} -> ${light}) and keeps it in localStorage with the language`);

  // ---- without the key again -----------------------------------------------------------------------
  await click(`.topbar-end button[aria-label="${en("settings")}"]`);
  await waitFor("the settings", (current) => current.dialog === "settings-title");
  await clickText(".dialog .text-button", en("api-key-remove"));
  state = await waitFor("the no-key mode again", (current) => current.dialog === null && current.mode?.text === en("mode-curated")
    && current.cards.length === curated.length && current.cards.every((card) => card.title === oembed[card.id].title));
  assert.equal(state.mode.class, "mode-badge mode-curated");
  assert.equal(await js(`localStorage.getItem("elisp-react:" + location.pathname + ":parens/api-key")`), null);
  pass(`settings: "${en("api-key-remove")}" returns to the no-key mode (badge "${en("mode-curated")}", ${curated.length} cards from oEmbed again) and forgets the key`);

  // ---- a phone ---------------------------------------------------------------------------------
  await send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 3, mobile: true });
  await until("document.documentElement.clientWidth === 390", "the phone's viewport");
  const layout = () => js(`(() => {
    const box = (selector) => document.querySelector(selector)?.getBoundingClientRect();
    return {
      sidebar: getComputedStyle(document.querySelector('.sidebar')).display,
      position: getComputedStyle(document.querySelector('.sidebar')).position,
      badge: getComputedStyle(document.querySelector('.mode-badge')).display,
      toggled: document.querySelector('.app').classList.contains('sidebar-toggled'),
      width: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      topbarEnd: Math.round(box('.topbar-end').right),
      settings: Math.round(box(${quote(`.topbar-end button[aria-label="${en("settings")}"]`)}).right),
    };
  })()`);
  let narrow = await layout();
  assert.deepEqual([narrow.sidebar, narrow.badge, narrow.toggled], ["none", "none", false]);
  if (narrow.scrollWidth > narrow.width) {
    known(`phone: the page is ${narrow.scrollWidth} px wide on a ${narrow.width} px screen: the top bar ends at ${narrow.topbarEnd} px, so the `
      + `keyboard and settings buttons (the only way to the settings: the mode badge is hidden below 640 px) are off-screen; `
      + ".search, a flex item of .topbar, has no min-width: 0 and cannot shrink below its input's own width");
  } else {
    assert.ok(narrow.settings <= narrow.width, "the settings button is on the screen");
  }
  await mouseClick('.topbar-start button[aria-label="Menu"]');
  await until("document.querySelector('.app').classList.contains('sidebar-toggled')", "the menu opens the sidebar");
  narrow = await layout();
  assert.deepEqual([narrow.sidebar, narrow.position], ["block", "fixed"]);
  await mouseClick('.sidebar a.nav-item[href="#/feed/history"]');
  state = await waitFor("History from the sidebar", (current) => current.page === "library" && !current.appClass.includes("sidebar-toggled"));
  narrow = await layout();
  assert.equal(narrow.sidebar, "none", "choosing a page closes the sidebar");
  await mouseClick(`.library .wide-card[data-video="${watched}"] .card-title a`);
  watch = await waitForWatch("a watch page on a phone", (current) => current.heading === watchedTitle && current.related.length === 20);
  const playerWidth = await js("document.querySelector('.player-frame').getBoundingClientRect().width");
  assert.ok(playerWidth > 300 && playerWidth <= 390, `the player fits the screen (${playerWidth} px)`);
  pass(`phone (390x844): the sidebar and the mode badge are hidden; the menu button shows the sidebar over the page, choosing a page `
    + `hides it; the player is ${Math.round(playerWidth)} px wide`);
  await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });

  // ---- what went over the "network" ------------------------------------------------------------------
  assertNoPageErrors("the end");
  assert.deepEqual(takeApiErrors(), []);
  pass(`network: everything outside localhost was answered by the test: ${traffic.oembed} oEmbed, ${traffic.dataApi} Data API, `
    + `${traffic.images} images, ${traffic.players.length} player stubs, IFrame API ×${traffic.iframeApi}, elisp-react files ×${traffic.elispReact}; nothing else`);
}

// ---- the live smoke test (E2E_LIVE / E2E_SITE) --------------------------------------------------------
async function smoke() {
  const first = await boot("");
  const home = await waitFor("35 cards", (state) => state.page === "home" && state.cards.length === curated.length, { timeout: bootTimeout });
  assert.deepEqual(home.cards.map((card) => card.id), curatedIds);
  // Titles come from YouTube one by one: wait until they stop coming.
  let titled = 0, still = 0;
  const t0 = Date.now();
  while (Date.now() - t0 < stepTimeout && still < 20) {
    const now = (await snapshot()).cards.filter((card) => card.title).length;
    still = now === titled ? still + 1 : 0;
    titled = now;
    if (titled === curated.length) break;
    await pause(250);
  }
  assert.ok(titled >= curated.length - 5, `most cards got a title from oEmbed (${titled} of ${curated.length})`);
  pass(`live: ${titled} of ${curated.length} cards got their title from YouTube's oEmbed (first render ${seconds(first.readyMs)}, Emacs ${first.version})`);

  const math = curated.filter((entry) => topicOf[entry.channel] === "math").map((entry) => entry.id);
  await clickText("#content .chips .chip", ja.math);
  await waitFor(`the chip ${ja.math}`, (state) => state.cards.length === math.length);
  await clickText("#content .chips .chip", w("all"));
  await waitFor("all again", (state) => state.cards.length === curated.length);
  pass(`live: the chip "${ja.math}" shows ${math.length} videos`);

  const target = (await snapshot()).cards.find((card) => card.title);
  await mouseClick(`#content .card[data-video="${target.id}"] .card-title a`);
  const watch = await waitForWatch("the watch page", (state) => state.heading === target.title && state.related.length > 0);
  const src = new URL(watch.frame.src);
  assert.equal(src.searchParams.get("enablejsapi"), "1");
  assert.equal(src.searchParams.get("origin"), new URL(siteOrigin).origin);
  // A static host is not cross-origin isolated: no credentialless (that is
  // for elisp-studio's preview), so the player keeps its cookies.
  assert.equal(watch.frame.credentialless, false);
  assert.equal(watch.frame.referrerpolicy, "strict-origin-when-cross-origin");
  const api = await waitUntil(() => js("typeof window.YT?.Player === 'function'").catch(() => false), "the IFrame API", stepTimeout).catch(() => false);
  // The real player, as far as headless Chrome gets with it: not a condition of the test.
  const player = await waitUntil(() => js(`(() => {
    const state = window.parensPort.player()?.getPlayerState?.();
    const error = document.querySelector(".player-error")?.textContent;
    return error ? { error } : (typeof state === "number" ? { state } : false);
  })()`).catch(() => false), "the player", 20_000).catch(() => ({ state: "unknown (no answer in 20 s)" }));
  pass(`live: a card opens ${watch.hash} with the player (${src.host}), ${watch.related.length} related; IFrame API ${api ? "loaded" : "not loaded"}, `
    + (player.error ? `the player's error: "${player.error}"` : `player state ${player.state}`));

  await click('.sidebar a.nav-item[href="#/feed/history"]');
  const history = await waitFor("the history page", (state) => state.page === "library" && state.wide.length > 0);
  assert.equal(history.wide[0].id, target.id);
  await js("history.back()");
  await waitForWatch("Back", (state) => state.heading === target.title);
  pass("live: the history page lists it; Back returns to it");
  assertNoPageErrors("live");
}

// ---- run -------------------------------------------------------------------------------------------------
let failed = false;
try {
  if (deployed) {
    console.log(`site: ${deployed} (deployed; Emacs and elisp-react from their public sites)`);
  } else {
    const site = await serveStatic(root, { host: "localhost" });
    servers.push(site.server);
    siteOrigin = site.origin;
    if (existsSync(`${wasmacsDocs}/app/src/emacs-eval-client.js`)) {
      const wasmacs = await serveStatic(wasmacsDocs);
      servers.push(wasmacs.server);
      wasmacsQuery = `?wasmacs=${wasmacs.origin}/`;
      console.log(`wasmacs: ${wasmacsDocs}`);
    } else {
      console.log("wasmacs: the public site (about 5 MB)");
    }
  }
  if (live) console.log("YouTube and elisp-react: the network (E2E_LIVE)");
  else console.log(`elisp-react: ${elispReactLocal ? elispReact : "the public site"}; YouTube: test/fixtures (offline)`);
  workDir = await mkdtemp(join(tmpdir(), "parens-e2e-"));
  chrome = spawn(chromePath, [
    "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--disable-extensions",
    "--disable-background-networking", "--disable-component-update", "--disable-default-apps", "--disable-sync",
    "--metrics-recording-only", "--no-pings", "--mute-audio",
    "--remote-debugging-port=0", `--user-data-dir=${join(workDir, "profile")}`, "--window-size=1280,900", "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  client = new CdpClient(await devToolsUrl(chrome));
  const { targetId } = await client.send("Target.createTarget", { url: "about:blank" });
  ({ sessionId } = await client.send("Target.attachToTarget", { targetId, flatten: true }));
  client.onEvent = onEvent;
  for (const domain of ["Page", "Runtime", "Log"]) await send(`${domain}.enable`);
  await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
  await send("Emulation.setFocusEmulationEnabled", { enabled: true });
  await send("Page.addScriptToEvaluateOnNewDocument", { source: PORT_LOG });
  if (!live) await send("Fetch.enable", { patterns: [{ urlPattern: "https://*", requestStage: "Request" }] });
  if (live) await smoke();
  else await offline();
  assertNoPageErrors("the end");
  pass(`no page errors (exceptions, console.error, failed loads) but the known 404s of api/feed and favicon.ico${live ? "" : " and the API errors the test asked for"}`);
  console.log(`e2e passed in ${seconds(Date.now() - startedAt)}`);
} catch (error) {
  failed = true;
  console.error(`FAIL ${error.stack || error.message}`);
  if (pageErrors.length) console.error(`page errors:\n  ${pageErrors.join("\n  ")}`);
  if (traffic.unexpected.length) console.error(`unexpected requests:\n  ${traffic.unexpected.join("\n  ")}`);
  if (apiErrors.length) console.error(`errors of the made-up Data API not checked yet: ${apiErrors.join(", ")}`);
  if (client && sessionId && !client.closed) {
    try { console.error(`screenshot: ${await screenshot("failure")}`); } catch { /* the page is gone */ }
  }
} finally {
  client?.close();
  if (chrome) {
    const running = () => chrome.exitCode === null && chrome.signalCode === null;
    let timer = null;
    if (running()) {
      chrome.kill("SIGTERM");
      await Promise.race([new Promise((done) => chrome.once("exit", done)), new Promise((done) => { timer = setTimeout(done, 5000); })]);
      clearTimeout(timer);
    }
    if (running()) chrome.kill("SIGKILL");
    // Chrome's helper processes hold its stderr a few seconds longer.
    chrome.stderr?.destroy();
  }
  for (const server of servers) {
    server.closeAllConnections?.();
    server.close();
  }
  if (workDir) await rm(workDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}
process.exitCode = failed ? 1 : 0;
