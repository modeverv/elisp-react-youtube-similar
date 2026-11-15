# Parens and elisp-next

[日本語](elisp-next.ja.md)

Parens is written with [elisp-next](https://github.com/modeverv/elisp-next): files as pages for elisp-react, a layer between React and Next.js. elisp-next was written here, on the branch `experiment/next-routing`, as an experiment (how close can an elisp-react application come to the way Next.js is written, and what does that feel like?), and then taken out. Its README is the reference; this page says how Parens uses it and what the experiment found.

## Where it is

```text
vendor/elisp-next/        a copy of a release (VERSION); tools/update-elisp-next.sh puts another
index.html                <!-- nextel:framework --> and <!-- nextel:pages -->: the scripts elisp-next writes
routes.el                 which page is which address, written from pages/
pages/_layout.el          the header, the sidebar, the dialogs, around every page
pages/index.el            /                    pages/watch.el      /watch?v=ID&t=S
pages/results.el          /results?search_query=TEXT (with :load)
pages/channel/[id].el     /channel/ID (with :load)
pages/feed/history.el     /feed/history        pages/playlist.el   /playlist?list=WL
pages/404.el              an address that no file has
api/feed.el               GET /api/feed: the channels' latest uploads (api/_feeds.el)
api/later.el              GET, POST /api/later; api/later/[id].el: DELETE: "watch later" kept by the server
shared/parens-types.el    parens-video, parens-channel, parens-feed, parens-later-entry
server.el                 three lines: elisp-next's nextel-server.el answers with api/
```

The addresses are those of the Parens before elisp-next (`#/watch?v=ID`, `#/channel/ID`): the file names were chosen to keep them, so links still work and `test/e2e.mjs` ran unchanged. After adding, removing or renaming a page: `M-x nextel-write-routes` in Emacs (`M-x load-file RET vendor/elisp-next/lisp/nextel-build.el` first; elisp-studio's too), `M-x nextel-routes-mode` to do it at every save, or `npm run routes`.

## What it was like

- **The structure reads like Next.js.** One file per address, the layout around them, the server's routes beside the pages. `lisp/` lost 560 lines to `pages/`: each page is one file, with the components only it uses.
- **Types catch mistakes at the boundary, not before.** There is no compiler: a field of the wrong type is found when the value crosses, with its path. That is a good deal better than a plist that is silently wrong three functions later, and less than TypeScript, which finds it while you type. The byte compiler's warnings still catch unknown functions and wrong argument counts (one below).
- **The page-side data loading is the part that helped most.** `:load` with `:loading` and `:error` replaced the hand-written status/retry/stale-answer code of two pages; Back shows their data at once.
- **What stays React-like.** Pages with lists that grow (home, infinite scroll) and the watch page (its player must not be rebuilt while the rest loads) keep loading in the page itself, as they would in a Next.js client component.
- **What Next.js has and this has not:** server rendering of the pages (the hash never reaches a server; with `path` mode, elisp-studio's `app-server-page-function` could render them, untried), code splitting (every page is loaded at the start), nested layouts, middleware, a type checker, and editor support for jumping from a link to its page.

## What the experiment found

- **The page's Emacs ran no hooks.** wasmacs's eval service starts Emacs up to `kill-emacs`, whose `shut_down_emacs` had set `Vrun_hooks` to nil: `run-hook-with-args` and `run-hooks` returned at once, in every page of elisp-react and in elisp-studio's preview (its `elisp-studio-after-load-functions` never ran). Fixed in wasmacs on 2026-11-16 ([wasmacs#21](https://github.com/modeverv/wasmacs/issues/21)); the router calls its functions itself either way.
- **A schema's accessors share the application's namespace.** `parens-channel-title` was a function of the channel page before it was the accessor of the field `title` of `parens-channel`; the byte compiler said so (an inlined function called with two arguments). Name schemas so that their fields do not meet your functions.
- **`next-` is Emacs's.** The first name of the framework clashed with Emacs's own `next-match`; hence `nextel-`.

## Tests

`test/parens-test.el` runs the application in a native Emacs with elisp-next (pages, the server mode with "watch later" through the API, a feed of the wrong type, the real `api/` on elisp-studio's `app-server.el`); `test/e2e.mjs` runs it in Chrome. elisp-next's own tests are in its repository.
