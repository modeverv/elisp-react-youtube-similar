#!/usr/bin/env bash
# The application's Lisp in a native Emacs (no browser): test/parens-test.el.
# react.el comes from $ELISP_REACT, a checkout of elisp-react next to this
# one, or (in CI) a shallow clone of it.
set -euo pipefail
cd "$(dirname "$0")/.."
react="${ELISP_REACT:-../elisp-react}"
if [ ! -f "${react}/lisp/react.el" ]; then
  echo "react.el not found in ${react}; set ELISP_REACT" >&2
  exit 1
fi
emacs="${EMACS:-$("${react}/tools/find-emacs.sh")}"
exec "${emacs}" --batch -Q -L "${react}/lisp" \
  --eval '(setq load-prefer-newer t)' \
  -l react -l test/parens-test.el \
  --eval '(parens-test-load-library)' \
  -f ert-run-tests-batch-and-exit
