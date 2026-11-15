#!/usr/bin/env bash
# Write the routes from pages/ with Emacs (nextel/nextel-build.el), outside
# an Emacs you edit with: for npm, CI and other editors.
#
#   tools/nextel-routes.sh            write nextel/routes.el and index.html's page scripts
#   tools/nextel-routes.sh --check    exit 1 when they are not up to date
#   tools/nextel-routes.sh --watch    write them whenever pages/, api/ or shared/ change
#
# In Emacs (also elisp-studio's): M-x load-file RET nextel/nextel-build.el,
# then M-x nextel-write-routes, or M-x nextel-routes-mode to write them at
# every save.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

emacs_bin="${EMACS:-}"
if [ -z "${emacs_bin}" ]; then
  # An "emacs" on PATH that is a link into a macOS app bundle does not
  # start: take the first candidate that really runs.
  for candidate in "$(command -v emacs || true)" \
                   /Applications/Emacs.app/Contents/MacOS/Emacs \
                   /Applications/Emacs-takaxp/Emacs.app/Contents/MacOS/Emacs; do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ] \
       && "${candidate}" --batch -Q --eval t >/dev/null 2>&1; then
      emacs_bin="${candidate}"
      break
    fi
  done
fi
[ -n "${emacs_bin}" ] || { echo "nextel-routes.sh: no Emacs found; set EMACS=/path/to/emacs" >&2; exit 127; }

case "${1:-}" in
  "") command=nextel-write-routes ;;
  --check) command=nextel-check-routes ;;
  --watch) command=nextel-watch-routes ;;
  *) echo "usage: tools/nextel-routes.sh [--check | --watch]" >&2; exit 2 ;;
esac
exec "${emacs_bin}" --batch -Q -l nextel/nextel-build.el -f "${command}"
