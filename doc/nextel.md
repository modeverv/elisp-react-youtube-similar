# nextel: files as pages, for elisp-react

[日本語](nextel.ja.md)

An experiment on the branch `experiment/next-routing`: how close can an elisp-react application come to the way Next.js is written, with a layer of its own (about 660 lines of Lisp and a 160-line generator), and what does that feel like? Parens is rewritten with it.

| | Next.js | nextel |
|---|---|---|
| A page | `app/watch/page.js` exports a component | `pages/watch.el` has `(nextel-page WatchPage ...)` |
| Its address | the file's path | the file's path: `pages/channel/[id].el` is `/channel/ID` |
| Around every page | `layout.js` | `pages/_layout.el`, `(nextel-layout Layout ...)`; it stays mounted |
| Not found | `not-found.js` | `pages/404.el` |
| Data for a page | server components, `fetch` in them | `:load` (an awaitable), in the page; `:loading` and `:error` meanwhile |
| Title and meta | `generateMetadata` | `:head` |
| A link | `<Link href>` | `(Link (:href (nextel-href "/watch" :v id)) ...)` |
| An API | `app/api/later/route.js` exports `GET`, `POST` | `api/later.el` has `(nextel-handle "GET" ...)`, `(nextel-handle "POST" ...)` |
| Types shared by both | TypeScript types in a shared file | `shared/*.el` with `nextel-defschema`; checked at run time on both sides |
| Finding the routes | the dev server watches `app/` | `node tools/nextel.mjs [--watch]` writes `nextel/routes.el` and the `<script>` tags |

## A page

```elisp
;;; pages/channel/[id].el --- /channel/ID
(nextel-page ChannelPage
  :load (lambda (route) (parens-load-channel (nextel-param route :id) nil))
  :head (lambda (route data) (list :title (parens-channel-page-title (nextel-param route :id))))
  :loading (lambda (route) (jsx (div (:class "channel") (parens-skeleton-grid 8))))
  :error (lambda (route error retry) (parens-failed (parens-failure-text error) retry))
  :render (lambda (self)
            (jsx (div (:class "channel") (parens-grid (plist-get (nextel-data self) :ids))))))
```

`nextel-page` is `react-define-component` plus four keys. The page gets the props `:route` (`:page :pattern :path :params :query`) and `:data`. What `:load` answered is kept by route (elisp-react's `react-query`): Back shows it at once, `(nextel-reload)` loads every page again. While `:load` waits, or loads again after a failure, the router shows `:loading`.

The address is in the hash by default (`#/channel/UC...`): any static host serves that, and elisp-studio's preview too. `nextel-url-mode` `path` uses `/channel/UC...` (links then go through Lisp; a server has to send `index.html` for every route).

`tools/nextel.mjs` reads `pages/` and writes which pattern is which page (`nextel/routes.el`) and the `<script>` tags between `<!-- nextel:pages -->` and `<!-- /nextel:pages -->` in `index.html`. The page cannot list a directory, so this has to be written; `--watch` keeps doing it while you work, and `--check` fails in CI when it is stale. A page's file names its component (`(nextel-page WatchPage`), as Next.js's file exports one: elisp-react loads each file under a name made of its URL, so a file cannot learn its own path.

## The server

```elisp
;;; api/later.el --- GET and POST /api/later
(nextel-handle "GET"
  :returns '(list-of parens-later-entry)
  :handler (lambda (_request) (parens-later)))

(nextel-handle "POST"
  :accepts 'parens-later-entry
  :returns '(list-of parens-later-entry)
  :handler (lambda (request) (parens-later-keep (cons (plist-get request :body) ...))))
```

`server.el` is two lines: `(load ".../nextel/nextel-server.el")` and `(nextel-server-load)`. The server can list its directory, so nothing is written for `api/`: each file is a route (files and directories that start with `_` are helpers). A body that is not of `:accepts` is refused with the field that is wrong (400, `body.id is required`); an answer that is not of `:returns` is the server's mistake (500, in the log), also one that comes later (`app-server-defer`). The same files run under a native Emacs (`run.sh`) and in elisp-studio's tab.

## The types

```elisp
;;; shared/parens-types.el --- loaded by the page and by the server
(nextel-defschema parens-later-entry
  (id string :required t)
  (title string)
  (saved number))
```

defines `make-parens-later-entry` (checked), `parens-later-entry-p`, `parens-later-entry-title` and so on. A record is a plist, so it crosses as printed Lisp. The page asks with the same type:

```elisp
(nextel-request "POST" "/api/later" :body entry :sends 'parens-later-entry
                :returns '(list-of parens-later-entry))
```

and a wrong answer fails the request with its place: `POST /api/later[0].id: expected string, got 42`. Parens builds every video and channel with `make-parens-video` and `make-parens-channel`, from the Data API, oEmbed and the server's feeds alike.

## What it was like

- **The structure reads like Next.js.** One file per address, the layout around them, the server's routes beside the pages. `lisp/` lost 560 lines to `pages/`: each page is one file, with the components only it uses.
- **Types catch mistakes at the boundary, not before.** There is no compiler: a field of the wrong type is found when the value crosses, with its path. That is a good deal better than a plist that is silently wrong three functions later, and less than TypeScript, which finds it while you type. The byte compiler's warnings still catch unknown functions and wrong argument counts (one below).
- **The page-side data loading is the part that helped most.** `:load` with `:loading` and `:error` replaced the hand-written status/retry/stale-answer code of two pages; Back shows their data at once.
- **What stays React-like.** Pages with lists that grow (home, infinite scroll) and the watch page (its player must not be rebuilt while the rest loads) keep loading in the page itself, as they would in a Next.js client component.
- **What Next.js has and this has not:** server rendering of the pages (the hash never reaches a server; with `path` mode, elisp-studio's `app-server-page-function` could render them, untried), code splitting (every page is loaded at the start), nested layouts, middleware, a type checker, and editor support for jumping from a link to its page.

## What the experiment found

- **The page's Emacs runs no hooks.** In wasmacs's eval service `run-hook-with-args` and `run-hooks` return at once: `Vrun_hooks` is nil there (a normal Emacs restores it from its dump). The router calls its functions itself. elisp-studio's `elisp-studio-after-load-functions`, run with `run-hook-with-args` in the preview, is affected the same way.
- **A schema's accessors share the application's namespace.** `parens-channel-title` was a function of the channel page before it was the accessor of the field `title` of `parens-channel`; the byte compiler said so (an inlined function called with two arguments). Name schemas so that their fields do not meet your functions.
- **`next-` is Emacs's.** The first name of the framework clashed with Emacs's own `next-match`; hence `nextel-`.

## Tests

`test/nextel-test.el`: types, patterns, the router (pages, `:load`, `:loading`, `:error` and retry, head, 404, the hook, the `path` mode and its links), `nextel-request`, and the server side with elisp-studio's `app-server.el` (routes from files, `:accepts`, `:returns` for answers now and later, 404, 405). `test/parens-test.el` adds Parens' server mode (watch later through the API, a feed of the wrong type) and the real `api/`. `test/e2e.mjs` runs unchanged in Chrome: the addresses of the old Parens are the file names of the new one.
