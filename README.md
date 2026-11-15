# elisp-react-youtube-similar

**Parens**: a video browser in the shape of YouTube's top page and watch page, written in Emacs Lisp with [elisp-react](https://github.com/modeverv/elisp-react) and developed in [elisp-studio](https://github.com/modeverv/elisp-studio). Videos and their data come from YouTube.

It is an experiment with a question: what do elisp-react and elisp-studio lack for developing a real application? The answer is in [doc/findings.md](doc/findings.md) ([日本語](doc/findings.ja.md)).

Live: <https://modeverv.github.io/elisp-react-youtube-similar/>. The first visit downloads Emacs (about 5 MB); GNU Emacs 30.2 runs in the page as WebAssembly ([wasmacs](https://github.com/modeverv/wasmacs)), and the application is Emacs Lisp.

[日本語](README.ja.md)

> Not affiliated with YouTube or Google. Parens uses YouTube's embedded player and YouTube's public endpoints; see [YouTube's Terms of Service](https://www.youtube.com/t/terms) and the [Google Privacy Policy](https://policies.google.com/privacy). It has a name, a logo and colours of its own, and every video links back to YouTube.

## What it does

- A home page: a grid of videos with thumbnails, lengths, channels, views and dates; chips to filter; more results as you scroll.
- A watch page: the player, title, channel, "watch later", share (copies the link), "open on YouTube", a description with links, timestamps that seek the player and #tags that search, comments, and a column of videos to play next, played automatically when one ends.
- Search, a page per channel, history and "watch later" (kept in the browser for 30 days at most), a settings dialog (an API key, Japanese or English, a dark or light theme), keyboard shortcuts (`/` `k` `j` `l` `?` `Esc`).
- Addresses for everything (`#/watch?v=…`, `#/results?search_query=…`): links can be shared and the Back button works.

## Where the videos come from

| Mode | When | What there is |
|---|---|---|
| No key (`curated`) | Default, e.g. on GitHub Pages | 35 chosen videos (ids in [lisp/parens-data.el](lisp/parens-data.el)); titles and channels from YouTube's oEmbed. No views, dates, descriptions or comments. |
| API (`api`) | The visitor enters a YouTube Data API v3 key in Settings | YouTube's popular chart for Japan, categories, search, descriptions, channels, comments. The key stays in that browser's localStorage. Google's API allows other sites' pages (CORS). |
| Server (`server`) | The page is served by a native Emacs running [server.el](server.el) | The latest long-form uploads of the chosen channels with views, likes, dates and descriptions, read from their RSS feeds. A page cannot read those feeds (no CORS); a server can. |

Restrict an API key to HTTP referrers and to the YouTube Data API v3. Never commit one: the repository is public.

## Running it

```sh
node tools/serve.mjs          # a static copy, as on GitHub Pages: http://localhost:8941/
```

`tools/serve.mjs` uses Emacs from a wasmacs checkout next to this one (`../wasmacs/docs`) when there is one, otherwise the public site. Use `localhost`, not `127.0.0.1`: YouTube's player refuses to play for a page whose Referer is `http://127.0.0.1:…`.

With the server (feeds, no key): from a checkout of elisp-studio next to this one,

```sh
../elisp-studio/tools/serve-project.sh . 8931     # then http://localhost:8931/
```

In elisp-studio, on your own machine (edit the files with any editor, the page follows):

```sh
node ../elisp-studio/tools/studio.mjs .           # opens http://127.0.0.1:5190/elisp-studio/?project=local
```

Open the studio at `http://localhost:5190/...` rather than the printed `127.0.0.1` address if you want the player to play.

## What is where

This branch (`experiment/next-routing`) is written with **nextel**, a Next.js-like layer of its own over elisp-react: a file of `pages/` is an address, a file of `api/` is a route of the server, and `shared/` holds the types that both sides check. See [doc/nextel.md](doc/nextel.md) ([日本語](doc/nextel.ja.md)).

```text
index.html                the page: the Lisp files in order, and the "port" script (below)
nextel/                   the framework: nextel.el (router, pages, links, requests),
                          nextel-schema.el (types), nextel-route.el (addresses),
                          nextel-server.el (api/ for server.el), routes.el (written)
nextel/nextel-build.el    reads pages/, writes nextel/routes.el and index.html's page scripts,
                          in Emacs (M-x nextel-write-routes, nextel-routes-mode)
tools/nextel-routes.sh    the same in batch, for npm and CI (--check, --watch)
pages/_layout.el          around every page: the header, the sidebar, the dialogs, messages
pages/index.el            /                    the home page
pages/watch.el            /watch?v=ID&t=S      a video
pages/results.el          /results?search_query=TEXT
pages/channel/[id].el     /channel/ID
pages/feed/history.el     /feed/history
pages/playlist.el         /playlist?list=WL    "watch later"
pages/404.el              an address that no file has
api/feed.el               GET /api/feed        the channels' latest uploads (api/_feeds.el)
api/later.el              GET, POST /api/later "watch later", kept by the server
api/later/[id].el         DELETE /api/later/ID
shared/parens-types.el    parens-video, parens-channel, parens-feed, parens-later-entry
server.el                 loads nextel/nextel-server.el, which answers with api/
lisp/parens-util.el       words (ja/en), numbers (1.2万 / 1.2K), dates, durations, links in text
lisp/parens-port.el       Lisp's side of the port: messages from the page, commands to it
lisp/parens-data.el       the chosen videos and channels (identifiers only)
lisp/parens-source.el     the three sources: oEmbed, the Data API, server.el; one shape of data
lisp/parens-state.el      addresses, settings, history and "watch later": the application's state
lisp/parens-ui.el         cards, avatars, icons, chips
lisp/parens-pages.el      what the pages share: lists that load more, the library, the dialogs
style.css                 the look; icons are CSS masks (elisp-react cannot draw SVG)
test/parens-test.el       the whole application in a native Emacs, no browser (ERT)
test/nextel-test.el       the framework: types, addresses, the router, requests, api/
test/e2e.mjs              the page in headless Chrome, YouTube answered by fixtures
```

### The port

When Parens was written, elisp-react gave Lisp the DOM, its events, timers, fetch and localStorage, and nothing else. It has more now: on this branch the address, the Back button and the title are elisp-react's, and nextel's router follows them. Keys pressed outside Lisp's elements, the clipboard and YouTube's player are still the port's. The script in `index.html` can, and the two talk through elements that Lisp renders ([lisp/parens-port.el](lisp/parens-port.el)):

- page → Lisp: a hidden `<input>`; the script puts a JSON message into its value and fires an `input` event;
- Lisp → page: one `<data data-cmd="JSON">` element per command; the script sees it appear (MutationObserver), carries it out and acknowledges it.

The script has no logic of the application: keys are interpreted and the player driven in Lisp. It is inline because elisp-studio's preview cannot load a project's own script files.

## Tests

```sh
npm run routes       # tools/nextel-routes.sh: after adding, removing or renaming a page (routes:watch keeps doing it);
                     # in Emacs, also elisp-studio's: M-x nextel-write-routes, or M-x nextel-routes-mode
npm run test:lisp    # test/run-ert.sh: the application in a native Emacs (react.el from ../elisp-react or $ELISP_REACT,
                     # app-server.el from ../elisp-studio or $ELISP_STUDIO)
npm run test:e2e     # test/e2e.mjs: headless Chrome, offline (fixtures for YouTube)
```

## Licence

MIT ([LICENSE](LICENSE)). The Lisp files run inside GNU Emacs (GPL-3.0-or-later); MIT is GPL-compatible. Nothing of Emacs is in this repository: the page downloads it from the wasmacs site, whose [NOTICE.md](https://github.com/modeverv/wasmacs/blob/master/NOTICE.md) gives its licences and sources. `test/lib/cdp.mjs` comes from elisp-react (MIT, same author).
