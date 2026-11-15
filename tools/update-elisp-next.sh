#!/usr/bin/env bash
# Put a release of elisp-next (https://github.com/modeverv/elisp-next) into
# vendor/elisp-next/: its lisp/, bin/ and LICENSE.  The page loads the
# framework from there, and so does server.el.
#
#   tools/update-elisp-next.sh [TAG]     a release (default: the one in vendor/elisp-next/VERSION)
#   tools/update-elisp-next.sh --local   a checkout next to this one (../elisp-next), for its development
#
# Afterwards write the routes again (vendor/elisp-next/bin/nextel-routes) and run the tests.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
target=vendor/elisp-next
tag="${1:-$(head -1 "${target}/VERSION" 2>/dev/null || echo v0.1.0)}"
fresh="$(mktemp -d)"
trap 'rm -rf "${fresh}"' EXIT
if [ "${tag}" = "--local" ]; then
  cp -R ../elisp-next/lisp ../elisp-next/bin ../elisp-next/LICENSE "${fresh}/"
  printf 'local %s\n%s\n' "$(git -C ../elisp-next rev-parse --short HEAD)" "../elisp-next" > "${fresh}/VERSION"
else
  curl -fsSL "https://github.com/modeverv/elisp-next/archive/refs/tags/${tag}.tar.gz" \
    | tar -xz --strip-components=1 -C "${fresh}" "elisp-next-${tag#v}/lisp" "elisp-next-${tag#v}/bin" "elisp-next-${tag#v}/LICENSE"
  printf '%s\nhttps://github.com/modeverv/elisp-next/releases/tag/%s\n' "${tag}" "${tag}" > "${fresh}/VERSION"
fi
rm -rf "${target}"
mkdir -p "$(dirname "${target}")"
mv "${fresh}" "${target}"
chmod 755 "${target}" "${target}/bin/nextel-routes"
trap - EXIT
echo "vendor/elisp-next: $(head -1 "${target}/VERSION")"
