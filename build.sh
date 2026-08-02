#!/bin/sh
# Build igropyr.com from its Scheme source with the Goeteia compiler.
#   site.ss -> (run) -> index.html    the static page + its inline CSS
# The background is NOT built here: bg.ss ships as source and boot.js has
# the browser compile it on load, which is the point of the page.  The
# test checks that source list still compiles, in that order.
# Run from the site root.
set -e
cd "$(dirname "$0")"
node rt/compile.mjs goeteia.wasm site.ss /tmp/igcom-site.wasm
node rt/run.mjs /tmp/igcom-site.wasm
echo "built index.html ($(wc -c < index.html | tr -d ' ') bytes)"

# verify: the sources the browser will concatenate still compile, and
# the gate reaches for them only when the engine can run the result
node test/boot-smoke.mjs
