// Compile the background animation in the browser: Goeteia (goeteia.wasm)
// compiles bg.ss + its libraries client-side, then the fresh module runs
// against a real WebGL2 bridge. No precompiled binary is shipped — the
// honeycomb fire, the ice, and the GOETEIA particles are literally
// compiled by Goeteia in your browser.
import { makeJsBridge, jsBridgeStubs } from './rt/jsbridge.mjs';

// prelude + the libraries bg.ss imports, then bg.ss itself; dependencies
// come before their dependents (fx needs js, gl, glsl, mat).
const SOURCES = [
    'src/prelude.ss',
    'lib/web/js.ss',
    'lib/web/dom.ss',
    'lib/gfx/glsl.ss',
    'lib/gfx/gl.ss',
    'lib/gfx/mat.ss',
    'lib/gfx/fx.ss',
    'hive-data.ss',
    'bg.ss',
];

const enc = new TextEncoder();
const stubs = {
    path_byte: () => {}, open_read: () => -1, open_write: () => -1,
    fread: () => -1, fwrite: () => {}, fclose: () => {},
};

(async () => {
    const canvas = document.getElementById('bg');
    if (!canvas) return;                              // no canvas, nothing to do

    // WebGL2 is required (transform feedback, HDR float targets)
    try {
        const probe = canvas.getContext('webgl2');
        if (!probe) return;                           // no WebGL2: leave the page plain
    } catch { return; }

    let wasmBuf, texts;
    try {
        [wasmBuf, ...texts] = await Promise.all([
            fetch('goeteia.wasm').then(r => r.arrayBuffer()),
            ...SOURCES.map(p => fetch(p).then(r => r.text())),
        ]);
    } catch { return; }                               // offline: skip the animation

    // ---- compile: feed the source to goeteia.wasm, collect its output ----
    const input = enc.encode(texts.join('\n'));
    const out = [];
    let pos = 0;
    const { instance: compiler } = await WebAssembly.instantiate(wasmBuf, {
        io: {
            write_byte: b => out.push(b),
            read_byte: () => (pos < input.length ? input[pos++] : -1),
            ...stubs,
        },
        js: jsBridgeStubs,                            // the compiler never calls JS
    });
    compiler.exports.main();
    if (out.length === 0) return;                     // compile error
    const bgWasm = new Uint8Array(out);

    // ---- instantiate the fresh module against the DOM/WebGL bridge ----
    let ex;
    const io = { write_byte: () => {}, read_byte: () => -1, ...stubs };
    let instance;
    try {
        ({ instance } = await WebAssembly.instantiate(bgWasm, {
            io, js: makeJsBridge(() => ex),
        }));
    } catch {
        // engine advertised WebAssembly.Suspending but rejected the import
        const js = makeJsBridge(() => ex);
        js.await = p => p;
        ({ instance } = await WebAssembly.instantiate(bgWasm, { io, js }));
    }
    ex = instance.exports;
    // expose the staging memory so (gfx gl) can build typed-array views
    if (ex.memory) globalThis.__goeteia_mem = ex.memory;
    ex.main();
})();
