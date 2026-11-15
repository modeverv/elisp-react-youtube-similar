# Findings: what elisp-react and elisp-studio lack for a real application

[日本語](findings.ja.md)

Parens was written to answer one question: what is missing when you build a real application with [elisp-react](https://github.com/modeverv/elisp-react) and develop it in [elisp-studio](https://github.com/modeverv/elisp-studio)? This page is the answer. Every gap has an issue in the repository that would fix it, with the evidence and a suggested fix.

## The short answer

Nothing stopped the application. Every feature Parens has (a home grid, a watch page with YouTube's player, search, channels, history, settings, two languages, three data sources, a server in Lisp) was built with the stack as it is, in about 2,000 lines of Emacs Lisp. No gap was a blocker.

But 57 gaps were found, and 20 of them are **major**: every real application meets them and needs significant workaround code, or risks bugs or security. They fall into five groups.

1. **Lisp cannot reach the page.** It cannot read or change the address ([R02](https://github.com/modeverv/elisp-react/issues/14)), call page JavaScript ([R01](https://github.com/modeverv/elisp-react/issues/13)), cancel an event's default action ([R04](https://github.com/modeverv/elisp-react/issues/16)), see modifier keys or coordinates ([R05](https://github.com/modeverv/elisp-react/issues/17)), read a response's headers or binary body ([N02](https://github.com/modeverv/elisp-react/issues/8)), or hold a live connection ([N03](https://github.com/modeverv/elisp-react/issues/9)). Parens wrote a "port" for this: about 90 lines of Lisp and 165 lines of inline JavaScript.
2. **State and asynchronous work.** There is no context or store ([R07](https://github.com/modeverv/elisp-react/issues/19)). One render error leaves components that stop updating ([R09](https://github.com/modeverv/elisp-react/issues/21)). `react-async` has no task to cancel or combine, and awaits that answer at once grow the stack ([R10](https://github.com/modeverv/elisp-react/issues/22)).
3. **Shipping.** A returning visitor can run code compiled against an older react.el ([R19](https://github.com/modeverv/elisp-react/issues/31)). Every first visit compiles the application on the visitor's CPU ([R20](https://github.com/modeverv/elisp-react/issues/32)). All applications on one origin share their stored data, and cached code can be planted by another page of that origin ([R23](https://github.com/modeverv/elisp-react/issues/35)). Nothing is released with a fixed version ([X01](https://github.com/modeverv/elisp-react/issues/43)). Each tab reserves 1 GiB of linear memory for Emacs, and no real phone has been tried ([X05](https://github.com/modeverv/wasmacs/issues/12)).
4. **The studio's development loop.** The preview has no address ([S01](https://github.com/modeverv/elisp-studio/issues/1)) and cannot fetch the project's own files ([S02](https://github.com/modeverv/elisp-studio/issues/2)). A change to several files stops at the first error and drops the rest silently ([S04](https://github.com/modeverv/elisp-studio/issues/4)). Errors have no location, and a failed render is reported as "not applied" although the new code is installed ([S07](https://github.com/modeverv/elisp-studio/issues/7)). `server.el` in the studio cannot share the application's code or reach sites without CORS ([S12](https://github.com/modeverv/elisp-studio/issues/11)).
5. **Testing.** There is no test kit for applications ([R26](https://github.com/modeverv/elisp-react/issues/38)); Parens built its own fake page.

## How this list was made

1. Parens was built (2026-11-15), and every workaround was written down as it was needed.
2. Four reviews looked at the stack from four sides: the component API, the studio's development loop, running and deploying, and a product checklist. Their candidates were merged into 51 items.
3. Each item was then checked again, by trying to refute it, against elisp-react `51f954a`, elisp-studio `c3aee20` and wasmacs `5e676c1` (Parens `c88aa04`). Claims were re-read in the code and the cheapest decisive probe was re-run, in native Emacs 30.2 and 31.1 and in headless Chrome 157. One more review looked for what the list missed (N01–N06) and for what already works well.

Verdicts: **confirmed** (true as reported), **partly** (the first report overstated it; the issue says what holds), **refuted** (the capability exists).
Severity, for building and shipping an application like Parens: **major** (every real application meets it and needs significant workaround code, or risks bugs or security), **minor** (a small workaround, or an uncommon case), **polish** (cosmetic or ergonomic). A **blocker** would have meant a normal feature cannot be built at all; there was none.

| | confirmed | partly | refuted | major | minor | polish |
|---|---|---|---|---|---|---|
| 57 items | 37 | 19 | 1 | 20 | 35 | 2 |

The probes ran on one Mac and are not published. Browser claims were checked in Chrome only.

## What already works well

A fair answer also says what the stack does well. Each point was checked against the code or measured.

- **UI code is short.** 15 components and 64 `jsx` forms make the whole interface; a complete video card is 28 lines. Helpers are ordinary functions.
- **Renders are cheap.** Keyed reconciliation moves only what must move, and `:pure` skips unchanged children. Re-rendering the root over 35 cards took 1.4 ms and 1 DOM operation; a list of 5,000 keyed rows re-renders in 38 ms.
- **Typing keeps up.** A keystroke costs 0.3–1.4 ms of Lisp; no key was lost at human typing speed.
- **Lisp never blocks the page.** Emacs runs in a worker. During a 2-second Lisp computation the page still drew a frame every 20 ms.
- **Hot reload keeps state.** A component edit appeared in about 0.9 s with its state, the route and even a playing YouTube player kept.
- **The whole application is tested in a native Emacs.** 12 tests mount the application and play the page against it in 1.5 s. They give the same results on Emacs 29, 30 and 31, and CI runs them on every push. A render is data in, operations out, so a fake page is a small list processor.
- **The output is plain DOM.** CSS, ARIA, DevTools and a CDP browser test (22 checks in 8.5 s) all work as on any page.
- **Lisp is good at text.** Links, timestamps that seek the player and `#tags` in a description take about 30 lines, and the result is element data, so nothing can be injected.
- **The same Lisp runs on the server.** `server.el` reads 9 RSS feeds in parallel with xml.el; the page reads the answer with `read-from-string`, with no JSON mapping in between.
- **Warm starts are fast.** Compiled code is cached: on a fast machine, compiling took 463 ms on a first visit and loading took 44 ms on the next; on a loaded machine, 11.8 s against 1.2 s.
- **Emacs downloads once.** About 5 MB the first time, then its files on demand; a cached start takes 150–175 ms.
- **Untrusted data is rendered safely.** The host never parses HTML, and executable attributes and `javascript:` URLs are refused.
- **Gaps can be filled in a few lines of Lisp.** `Promise.all` took 17 lines and an awaitable `async` 17 more. The issues below count the cost of each.
- **Long sessions do not leak.** The number of DOM nodes and component records stayed flat over 15 round trips between pages.
- **There is no build step.** Deploying means copying static files.

## All gaps

### elisp-react: reaching the page

| ID | Gap | Severity | Verdict | Issue |
|---|---|---|---|---|
| R01 | No supported way to extend the host or to talk between page JavaScript and Lisp | **major** | partly | [elisp-react#13](https://github.com/modeverv/elisp-react/issues/13) |
| R02 | No API for the page's location, history, title or meta | **major** | confirmed | [elisp-react#14](https://github.com/modeverv/elisp-react/issues/14) |
| R03 | Lisp cannot listen to window or document events, or use observers | minor | confirmed | [elisp-react#15](https://github.com/modeverv/elisp-react/issues/15) |
| R04 | Lisp cannot call preventDefault or stopPropagation, or choose listener options | **major** | confirmed | [elisp-react#16](https://github.com/modeverv/elisp-react/issues/16) |
| R05 | Event plists lack modifier keys, code, isComposing, coordinates and the target | **major** | confirmed | [elisp-react#17](https://github.com/modeverv/elisp-react/issues/17) |
| R06 | No public way to set DOM properties, call methods with arguments, or read values back | minor | partly | [elisp-react#18](https://github.com/modeverv/elisp-react/issues/18) |
| R11 | No inline SVG: elements are created in the HTML namespace | minor | partly | [elisp-react#23](https://github.com/modeverv/elisp-react/issues/23) |
| R15 | No sanitized way to insert HTML, and no HTML parser in the page's Emacs | minor | confirmed | [elisp-react#27](https://github.com/modeverv/elisp-react/issues/27) |
| R16 | Attributes: a list :class, numeric styles and ARIA booleans print wrongly | minor | partly | [elisp-react#28](https://github.com/modeverv/elisp-react/issues/28) |
| R27 | Document modal dialogs and focus handling; make showModal and close invocable | minor | refuted | [elisp-react#39](https://github.com/modeverv/elisp-react/issues/39) |
| N02 | react-fetch gives only status and text: no headers, binary bodies corrupted, few fetch options | **major** | confirmed | [elisp-react#8](https://github.com/modeverv/elisp-react/issues/8) |
| N03 | No realtime channel: no WebSocket, Server-Sent Events or streamed responses | **major** | confirmed | [elisp-react#9](https://github.com/modeverv/elisp-react/issues/9) |

### elisp-react: components, state and asynchronous work

| ID | Gap | Severity | Verdict | Issue |
|---|---|---|---|---|
| R07 | No context, store subscription or public force-update | **major** | partly | [elisp-react#19](https://github.com/modeverv/elisp-react/issues/19) |
| R08 | One function per lifecycle key: no reusable effects with dependencies and cleanup | minor | partly | [elisp-react#20](https://github.com/modeverv/elisp-react/issues/20) |
| R09 | A render error leaves components stuck and skips pending :did-mount calls; no error boundaries | **major** | confirmed | [elisp-react#21](https://github.com/modeverv/elisp-react/issues/21) |
| R10 | react-async gives no task handle or cancellation; immediate awaits grow the stack; generator.el pitfalls | **major** | partly | [elisp-react#22](https://github.com/modeverv/elisp-react/issues/22) |
| R12 | Forms: submit carries no data, a controlled input can lose keystrokes, a controlled select mounts wrong | minor | partly | [elisp-react#24](https://github.com/modeverv/elisp-react/issues/24) |
| R13 | A child list that starts with nil renders a `<nil>` element; no fragments | minor | confirmed | [elisp-react#25](https://github.com/modeverv/elisp-react/issues/25) |
| R14 | :pure compares function props with eq, so a lambda prop defeats it | minor | confirmed | [elisp-react#26](https://github.com/modeverv/elisp-react/issues/26) |
| R17 | No ref forwarding or instance handles; react-mount returns the selector | minor | confirmed | [elisp-react#29](https://github.com/modeverv/elisp-react/issues/29) |
| R18 | A misspelled component renders silently as an unknown HTML element | minor | confirmed | [elisp-react#30](https://github.com/modeverv/elisp-react/issues/30) |
| N04 | react-storage is a snapshot taken at start: another tab's writes are lost | minor | confirmed | [elisp-react#10](https://github.com/modeverv/elisp-react/issues/10) |
| N05 | A raw-byte string in a render drops the whole batch of DOM operations | minor | confirmed | [elisp-react#11](https://github.com/modeverv/elisp-react/issues/11) |
| N06 | No data-fetching layer: cache, de-duplication and invalidation are written by each app | minor | confirmed | [elisp-react#12](https://github.com/modeverv/elisp-react/issues/12) |

### elisp-react: start-up, shipping and running

| ID | Gap | Severity | Verdict | Issue |
|---|---|---|---|---|
| R19 | The bytecode cache ignores react.el: returning visitors run stale macro expansions | **major** | confirmed | [elisp-react#31](https://github.com/modeverv/elisp-react/issues/31) |
| R20 | Every first visit byte-compiles react.el and the app on the visitor's CPU; no ahead-of-time build | **major** | confirmed | [elisp-react#32](https://github.com/modeverv/elisp-react/issues/32) |
| R21 | Start-up has no progress events, timeout or abort, and network errors name no file | minor | partly | [elisp-react#33](https://github.com/modeverv/elisp-react/issues/33) |
| R22 | No render-to-string for pages, no hydration and no head/meta API | minor | confirmed | [elisp-react#34](https://github.com/modeverv/elisp-react/issues/34) |
| R23 | Storage spans the whole origin: apps read each other's data, and cached code can be planted | **major** | confirmed | [elisp-react#35](https://github.com/modeverv/elisp-react/issues/35) |
| R24 | Each host reply is its own Emacs request and flush; GC runs before the reply is posted | minor | partly | [elisp-react#36](https://github.com/modeverv/elisp-react/issues/36) |
| R28 | No timing hooks for Lisp time, operation counts or DOM apply | polish | partly | [elisp-react#40](https://github.com/modeverv/elisp-react/issues/40) |
| X01 | No versioned, immutable releases of elisp-react and the eval service | **major** | confirmed | [elisp-react#43](https://github.com/modeverv/elisp-react/issues/43) |
| X02 | Document the Content-Security-Policy the stack needs; drop the need for inline styles and blob: workers | minor | partly | [elisp-react#44](https://github.com/modeverv/elisp-react/issues/44) |
| X06 | No list of what the stack stores and contacts; no expiry for stored data | minor | confirmed | [elisp-react#45](https://github.com/modeverv/elisp-react/issues/45) |
| N01 | A long or endless Lisp computation freezes the app silently: no watchdog or restart | minor | confirmed | [elisp-react#7](https://github.com/modeverv/elisp-react/issues/7) |

### elisp-react: working as a team

| ID | Gap | Severity | Verdict | Issue |
|---|---|---|---|---|
| R25 | No locale or Intl bridge; the page's Emacs runs in the C locale and ignores time zones | minor | confirmed | [elisp-react#37](https://github.com/modeverv/elisp-react/issues/37) |
| R26 | No test kit for applications: no element lookup, fake page or runner on the shipped Emacs | **major** | partly | [elisp-react#38](https://github.com/modeverv/elisp-react/issues/38) |
| R29 | No indentation spec for jsx and react-define-component; no lint step for apps | polish | partly | [elisp-react#41](https://github.com/modeverv/elisp-react/issues/41) |
| R30 | Third-party Lisp must be listed in dependency order; nothing is on load-path | minor | partly | [elisp-react#42](https://github.com/modeverv/elisp-react/issues/42) |

### wasmacs: the eval service

| ID | Gap | Severity | Verdict | Issue |
|---|---|---|---|---|
| X03 | The cached Emacs cannot start offline; one failed build-id request re-downloads everything | minor | confirmed | [wasmacs#10](https://github.com/modeverv/wasmacs/issues/10) |
| X04 | Two eval-service builds on one origin evict each other's cache | minor | confirmed | [wasmacs#11](https://github.com/modeverv/wasmacs/issues/11) |
| X05 | 1 GiB initial memory per tab, untested on real phones; the document's 4 GiB maximum is wrong | **major** | confirmed | [wasmacs#12](https://github.com/modeverv/wasmacs/issues/12) |

### elisp-studio

| ID | Gap | Severity | Verdict | Issue |
|---|---|---|---|---|
| S01 | The preview has no address: hash links load a nested studio and pushState throws | **major** | confirmed | [elisp-studio#1](https://github.com/modeverv/elisp-studio/issues/1) |
| S02 | The preview cannot fetch the project's own files; relative URLs reach the studio's files | **major** | confirmed | [elisp-studio#2](https://github.com/modeverv/elisp-studio/issues/2) |
| S03 | Local mode isolates the preview (COEP), so third-party embeds need credentialless | minor | partly | [elisp-studio#3](https://github.com/modeverv/elisp-studio/issues/3) |
| S04 | A multi-file change loads in directory order, and the first error silently drops the rest | **major** | confirmed | [elisp-studio#4](https://github.com/modeverv/elisp-studio/issues/4) |
| S05 | Removed or renamed definitions stay alive after a hot reload; the next fresh start fails | minor | confirmed | [elisp-studio#5](https://github.com/modeverv/elisp-studio/issues/5) |
| S06 | Changing only helpers or data is reported as applied, but nothing re-renders | minor | confirmed | [elisp-studio#6](https://github.com/modeverv/elisp-studio/issues/6) |
| S07 | Runtime errors have no location, and a failed render is reported as 'not applied' | **major** | confirmed | [elisp-studio#7](https://github.com/modeverv/elisp-studio/issues/7) |
| S08 | No way to evaluate an expression and see its value, or to inspect components and state | minor | confirmed | [elisp-studio#8](https://github.com/modeverv/elisp-studio/issues/8) |
| S09 | Editor support: false Flymake warnings in local mode; M-. misses project helpers and components | minor | partly | [elisp-studio#9](https://github.com/modeverv/elisp-studio/issues/9) |
| S11 | The in-page studio overwrites a project's files when it has no app.el; it cannot open an existing repository | minor | partly | [elisp-studio#10](https://github.com/modeverv/elisp-studio/issues/10) |
| S12 | In the studio server.el cannot load the project's other files or reach sites without CORS | **major** | confirmed | [elisp-studio#11](https://github.com/modeverv/elisp-studio/issues/11) |
| S13 | Projects opened on the same port share localStorage and server data | minor | confirmed | [elisp-studio#12](https://github.com/modeverv/elisp-studio/issues/12) |
| S14 | The native server's headers are fixed: server.el cannot set Cache-Control or Referrer-Policy | minor | confirmed | [elisp-studio#13](https://github.com/modeverv/elisp-studio/issues/13) |
| S15 | The native server cannot answer a frontend on another site (no CORS) | minor | partly | [elisp-studio#14](https://github.com/modeverv/elisp-studio/issues/14) |
| S16 | The template has no .gitignore, CI or tests, while the tools write .data/ into the project | minor | confirmed | [elisp-studio#15](https://github.com/modeverv/elisp-studio/issues/15) |

## Corrections made while checking

Some first reports were wrong or overstated. The issues give the details; the main corrections:

- **Modal dialogs work** ([R27](https://github.com/modeverv/elisp-react/issues/39), refuted). A `<dialog>` opened by a button with `command="show-modal"` is a real modal: the page behind is inert, Tab stays inside, Escape closes it and Lisp hears `:on-close`, and focus returns to the button. Nothing documents this, and Parens rebuilt it in page JavaScript.
- **Page JavaScript can be reached** ([R01](https://github.com/modeverv/elisp-react/issues/13), partly). On a published page, a script that wraps `window.fetch` gives Lisp request and reply, and a custom element carries strings both ways. Neither works in the studio's preview.
- **Global state can reach `:pure` children** ([R07](https://github.com/modeverv/elisp-react/issues/19), partly), as a prop, through `:should-update`, or by defining the component again.
- **package.el works in the page** ([R30](https://github.com/modeverv/elisp-react/issues/42), partly) for local files; it cannot download.
- **A strict Content-Security-Policy is possible** ([X02](https://github.com/modeverv/elisp-react/issues/44), partly) when the policy is on the page only and wasmacs is on the same origin; only inline styles must be allowed.
- **Re-rendering the whole application on every reply was Parens's own choice** ([R24](https://github.com/modeverv/elisp-react/issues/36), partly), not elisp-react's.
- **There is an unsafe way to set `innerHTML`** ([R15](https://github.com/modeverv/elisp-react/issues/27)): the internal `react--emit` reaches the host's property operation, and a script in the HTML ran. It is not a substitute for a sanitized API.

Four documents say the opposite of what the code does:

- elisp-react README.md:106 says nil children are dropped; a list that starts with nil renders a `<nil>` element ([R13](https://github.com/modeverv/elisp-react/issues/25)).
- elisp-studio README.md:68 says a change that fails is not applied; after a failed render the new definitions are installed ([S07](https://github.com/modeverv/elisp-studio/issues/7)).
- elisp-studio README.md:32 says a project that exists is never replaced; one without `app.el` is ([S11](https://github.com/modeverv/elisp-studio/issues/10)).
- wasmacs doc/eval-service.md says Emacs's memory can grow to 4 GiB; the binary's maximum is 2 GiB ([X05](https://github.com/modeverv/wasmacs/issues/12)).

## What Parens wrote around the gaps

| In Parens | Because of |
|---|---|
| The port: a hidden `<input>` for messages from the page, a `<data>` element per command to it ([lisp/parens-port.el](../lisp/parens-port.el), `index.html`) | [R01](https://github.com/modeverv/elisp-react/issues/13) [R02](https://github.com/modeverv/elisp-react/issues/14) [R03](https://github.com/modeverv/elisp-react/issues/15) [R06](https://github.com/modeverv/elisp-react/issues/18) |
| Hash routes parsed in Lisp; clicks intercepted in the studio's preview; the route kept in localStorage | [R02](https://github.com/modeverv/elisp-react/issues/14) [S01](https://github.com/modeverv/elisp-studio/issues/1) |
| The port's script inline in `index.html` | [S02](https://github.com/modeverv/elisp-studio/issues/2) |
| Icons as CSS masks with `data:` URLs | [R11](https://github.com/modeverv/elisp-react/issues/23) |
| `parens-class`, string `:class` values | [R16](https://github.com/modeverv/elisp-react/issues/28) |
| A store of its own, a global App instance, `:lang` passed to every card | [R07](https://github.com/modeverv/elisp-react/issues/19) |
| Function symbols instead of lambdas as props of `:pure` cards | [R14](https://github.com/modeverv/elisp-react/issues/26) |
| `parens-async`, `parens-all`, staleness checks after every await | [R10](https://github.com/modeverv/elisp-react/issues/22) [N06](https://github.com/modeverv/elisp-react/issues/12) |
| A modal's backdrop as a sibling of the dialog, then a focus trap in the port | [R04](https://github.com/modeverv/elisp-react/issues/16) [R27](https://github.com/modeverv/elisp-react/issues/39) |
| `decode-coding-string` after `json-serialize`; a query-string parser of its own | [N05](https://github.com/modeverv/elisp-react/issues/11) |
| Files ordered by dependency in `index.html` | [R30](https://github.com/modeverv/elisp-react/issues/42) |
| The channel list copied into `server.el` | [S12](https://github.com/modeverv/elisp-studio/issues/11) |
| `<meta name="referrer">` and an iframe `referrerpolicy` so that YouTube plays from the native server | [S14](https://github.com/modeverv/elisp-studio/issues/13) |
| Library entries dropped after 30 days | [X06](https://github.com/modeverv/elisp-react/issues/45) |
| A generation counter so that answers for a superseded source are dropped | [N06](https://github.com/modeverv/elisp-react/issues/12) |
| A fake page for ERT, using seven of react.el's internals | [R26](https://github.com/modeverv/elisp-react/issues/38) |
