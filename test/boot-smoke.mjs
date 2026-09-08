// The page's whole browser story, driven without a browser:
//   1. the sources boot.js names actually compile, in that order, the
//      way the browser will concatenate them (an (import ...) is a
//      no-op once every (library ...) is spliced in)
//   2. no WebGL2 -> the compiler is never even fetched
//   3. the happy road reaches compile and run
// Run: node test/boot-smoke.mjs   (from the site root)   exit 0 = pass.
// Copyright (c) 2026 guenchi. Apache License 2.0; see LICENSE.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const bootSrc = fs.readFileSync(path.join(root, 'boot.js'), 'utf8');

// the source list is the page's contract with the compiler -- read it
// out of boot.js rather than restating it here
const SOURCES = [...bootSrc.matchAll(/'([\w/.-]+\.ss)'/g)].map(m => m[1]);
assert.ok(SOURCES.length >= 5, 'boot.js should name its sources');

// 1. concatenated in that order, they compile to a wasm module
{
    const text = SOURCES.map(p => fs.readFileSync(path.join(root, p), 'latin1'))
        .join('\n');
    const input = Buffer.from(text, 'latin1');
    const out = [];
    let pos = 0;
    const stub = new Proxy({}, { get: () => () => 0 });
    const { instance } = await WebAssembly.instantiate(
        fs.readFileSync(path.join(root, 'goeteia.wasm')),
        { io: { write_byte: b => out.push(b),
                read_byte: () => (pos < input.length ? input[pos++] : -1),
                path_byte: () => {}, open_read: () => -1, open_write: () => -1,
                fread: () => -1, fwrite: () => {}, fclose: () => {} },
          js: stub });
    instance.exports.main();
    assert.ok(out.length > 0,
        'the source list produced no module -- a missing or misordered library');
    assert.deepEqual([out[0], out[1], out[2], out[3]], [0, 0x61, 0x73, 0x6d],
        `not a wasm module: ${Buffer.from(out).toString('latin1').slice(0, 120)}`);
    console.log(`  ✓ ${SOURCES.length} sources compile in order (${out.length}B wasm)`);
}

// 2 & 3. the gate: drive boot.js against a mock page, counting what it
// reaches for.  It imports rt/web.mjs, so intercept at the fetch level.
async function drive({ webgl2 }) {
    const fetched = [];
    const saved = {};
    const globals = {
        document: {
            getElementById: id => id === 'bg'
                ? { getContext: t => (t === 'webgl2' && webgl2) ? {} : null }
                : null,
        },
        fetch: async (u) => {
            fetched.push(u);
            throw new Error('offline (test)');       // stop before compiling
        },
    };
    for (const [k, v] of Object.entries(globals)) {
        saved[k] = Object.getOwnPropertyDescriptor(globalThis, k);
        Object.defineProperty(globalThis, k,
            { value: v, configurable: true, writable: true });
    }
    try {
        // a fresh module instance each time: the IIFE runs on import
        await import(`../boot.js?case=${webgl2 ? 'gl' : 'nogl'}`);
        await new Promise(r => setTimeout(r, 0));    // let the IIFE settle
    } finally {
        for (const k of Object.keys(globals)) {
            if (saved[k]) Object.defineProperty(globalThis, k, saved[k]);
            else delete globalThis[k];
        }
    }
    return fetched;
}

{
    const fetched = await drive({ webgl2: false });
    assert.equal(fetched.length, 0,
        'no WebGL2: nothing should be fetched, not even the compiler');
    console.log('  ✓ no WebGL2 -> not a byte fetched');
}
{
    const fetched = await drive({ webgl2: true });
    assert.ok(fetched.length > 0, 'WebGL2 present: the sources should be fetched');
    assert.ok(fetched.some(u => String(u).endsWith('bg.ss')),
        'the animation source should be among them');
    console.log(`  ✓ WebGL2 -> reaches for ${fetched.length} sources`);
}

console.log('PASS: the page compiles its background in the browser, and gates it');
