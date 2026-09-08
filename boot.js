// The page's background is not a shipped binary: Goeteia (goeteia.wasm)
// compiles bg.ss and its libraries in your browser, and the fresh module
// runs against a real WebGL2 bridge. The honeycomb fire, the ice and the
// GOETEIA particles are literally compiled here, on load.
//
// The cycle itself -- fetch the sources, feed them to the compiler,
// instantiate what comes out against the DOM bridge -- lives in
// rt/web.mjs, so this file is only the page's own part: which sources,
// and whether this browser can run the result at all.
// Copyright (c) 2026 guenchi. Apache License 2.0; see LICENSE.
import { compileGoeteiaFrom, runGoeteiaBytes } from './rt/web.mjs';

// dependencies before their dependents (fx needs js, gl, glsl, mat, mesh)
const SOURCES = [
    'src/prelude.ss',
    'lib/web/js.ss',
    'lib/web/dom.ss',
    'lib/gfx/glsl.ss',
    'lib/gfx/gl.ss',
    'lib/gfx/mat.ss',
    'lib/gfx/mesh.ss',
    'lib/gfx/fx.ss',
    'hive-data.ss',
    'bg.ss',
];

(async () => {
    const canvas = document.getElementById('bg');
    if (!canvas) return;
    // WebGL2 is required (transform feedback, HDR float targets); without
    // it the page stays plain rather than showing an empty canvas
    try {
        if (!canvas.getContext('webgl2')) return;
    } catch { return; }

    try {
        await runGoeteiaBytes(await compileGoeteiaFrom(SOURCES));
    } catch (e) {
        // offline, a compile error, or an engine that cannot run the
        // module: the page reads the same, just without the animation
        console.warn('[igropyr] background off:', e && e.message);
    }
})();
