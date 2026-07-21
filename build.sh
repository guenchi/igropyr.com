#!/bin/sh
# Build igropyr.com from its Scheme source with the Goeteia compiler.
#   site.ss -> (run) -> index.html    the static page + its inline CSS
# Run from the site root.
set -e
cd "$(dirname "$0")"
node rt/compile.mjs goeteia.wasm site.ss /tmp/igcom-site.wasm
node rt/run.mjs /tmp/igcom-site.wasm
echo "built index.html ($(wc -c < index.html | tr -d ' ') bytes)"
