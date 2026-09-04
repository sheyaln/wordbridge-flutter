// Kokoro TTS in a dedicated worker.
//
// The whole sherpa engine lives in here — glue, wasm, MEMFS, the OfflineTts
// handle — because synthesis is a synchronous wasm call that runs for seconds
// and the board must stay responsive across it. Nothing about the engine is
// reachable from the main thread; the only interface is the message protocol
// below.
//
// Classic worker on purpose: `importScripts` is the only way to load the
// Emscripten glue, which is not a module.

'use strict';

const CACHE_NAME = 'wordbridge-voice-v1';
const MEMFS_ROOT = '/voice';

let Module = null;
let tts = null;
let loading = null;
let loadedManifestUrl = null;

// Synthesis is synchronous, so a second request that arrives mid-call would be
// handled after the first returns anyway. The queue exists to keep replies in
// arrival order and to stop a burst from re-entering the wasm.
const queue = [];
let draining = false;

function post(msg, transfer) {
  self.postMessage(msg, transfer || []);
}

function fail(message, id) {
  const msg = { type: 'error', message: String(message) };
  if (id !== undefined && id !== null) msg.id = id;
  post(msg);
}

// ---------------------------------------------------------------- manifest

function dirOf(url) {
  const u = new URL(url, self.location.href);
  u.search = '';
  u.hash = '';
  u.pathname = u.pathname.replace(/[^/]*$/, '');
  return u.toString();
}

async function readManifest(manifestUrl) {
  const res = await fetch(manifestUrl, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`manifest ${manifestUrl} -> HTTP ${res.status}`);
  const m = await res.json();
  if (!Array.isArray(m.files) || !m.model) {
    throw new Error('manifest missing files[] or model');
  }
  const base = dirOf(manifestUrl);
  m._base = base;
  m._urls = m.files.map((f) => ({
    path: f.path,
    bytes: f.bytes,
    url: new URL(f.path, base).toString(),
  }));
  m._total = typeof m.totalBytes === 'number'
      ? m.totalBytes
      : m.files.reduce((a, f) => a + f.bytes, 0);
  return m;
}

// ------------------------------------------------------------------ cache

// Cache API needs a secure context. localhost qualifies, so plain HTTP in
// development is fine; anything else has to be HTTPS or `caches` is undefined.
async function openCache() {
  if (typeof caches === 'undefined') return null;
  try {
    return await caches.open(CACHE_NAME);
  } catch (e) {
    return null;
  }
}

// A cache write that fails is a slower next visit, never a voice that will
// not start. Chromium refuses a streamed body it cannot stage — a machine
// short of disk is the case seen — and it reports that as a network error on
// `put` rather than on the fetch that already succeeded.
async function keep(cache, url, response) {
  if (!cache) return;
  try {
    await cache.put(url, response);
  } catch (e) {
    // Next visit downloads it again.
  }
}

async function cachedBytes(cache, entries) {
  if (!cache) return 0;
  let n = 0;
  for (const e of entries) {
    const hit = await cache.match(e.url);
    if (hit) n += e.bytes;
  }
  return n;
}

// Emits progress no more than every 2 MB or 100 ms, whichever comes first.
function progressEmitter(phase, totalBytes) {
  let sent = 0;
  let lastBytes = 0;
  let lastAt = 0;
  return {
    add(n) {
      sent += n;
      const now = Date.now();
      if (sent - lastBytes >= 2 * 1024 * 1024 || now - lastAt >= 100) {
        lastBytes = sent;
        lastAt = now;
        post({ type: 'progress', phase, bytes: sent, totalBytes });
      }
    },
    done() {
      post({ type: 'progress', phase, bytes: sent, totalBytes });
    },
  };
}

// ------------------------------------------------------------------ memfs

function mkdirTree(path) {
  Module.FS.mkdirTree(path);
}

function ensureParent(path) {
  const cut = path.lastIndexOf('/');
  if (cut > 0) mkdirTree(path.slice(0, cut));
}

/// Writes a response body into MEMFS without ever holding the file whole.
/// The pre-size matters: MEMFS regrows and recopies a file's backing array on
/// every write past capacity, so streaming a 134 MB model in network-sized
/// chunks is quadratic and never finishes without it.
async function streamIntoMemfs(path, body, expectedBytes, onBytes) {
  ensureParent(path);
  const stream = Module.FS.open(path, 'w+');
  try {
    if (expectedBytes > 0) Module.FS.truncate(path, expectedBytes);
    const reader = body.getReader();
    let at = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      Module.FS.write(stream, value, 0, value.length, at);
      at += value.length;
      if (onBytes) onBytes(value.length);
    }
    // A short file would otherwise keep the zero padding the pre-size added.
    if (expectedBytes > 0 && at !== expectedBytes) Module.FS.truncate(path, at);
    return at;
  } finally {
    Module.FS.close(stream);
  }
}

// ------------------------------------------------------------------ engine

async function loadSherpa(sherpaBase) {
  if (Module) return;
  const base = new URL(sherpaBase, self.location.href).toString();

  // The wrappers are written for node and assign to `module.exports`; in worker
  // scope that binding does not exist.
  if (typeof self.module === 'undefined') self.module = {};

  importScripts(new URL('sherpa-onnx-wasm-web.js', base).toString());
  importScripts(new URL('sherpa-onnx-tts.js', base).toString());
  if (typeof SherpaOnnx !== 'function') throw new Error('SherpaOnnx factory missing after importScripts');
  if (typeof createOfflineTts !== 'function') throw new Error('createOfflineTts missing after importScripts');

  const wasmUrl = new URL('sherpa-onnx-wasm-web.wasm', base).toString();
  const cache = await openCache();
  let res = cache ? await cache.match(wasmUrl) : null;
  const fresh = !res;
  if (!res) {
    res = await fetch(wasmUrl);
    if (!res.ok) throw new Error(`wasm -> HTTP ${res.status}`);
  }
  // The factory takes bytes, not a Response — instantiateStreaming is not on
  // offer, so the 14.8 MB binary is buffered once here.
  const wasmBinary = new Uint8Array(await res.arrayBuffer());
  // Cached from the bytes rather than from the response: a body already read
  // cannot be staged again, and Chromium will not take a streamed body of this
  // size on a machine short of disk in any case.
  if (fresh) {
    await keep(cache, wasmUrl, new Response(wasmBinary, {
      headers: { 'content-type': 'application/wasm' },
    }));
  }

  let mod = SherpaOnnx({ wasmBinary });
  while (mod && typeof mod.then === 'function') mod = await mod;
  if (!mod || typeof mod.FS !== 'object') throw new Error('Emscripten Module did not instantiate');
  Module = mod;
}

async function installFiles(manifest) {
  const cache = await openCache();
  const prog = progressEmitter('installing', manifest._total);
  const dl = progressEmitter('downloading', manifest._total);
  let downloaded = 0;

  for (const entry of manifest._urls) {
    const target = `${MEMFS_ROOT}/${entry.path}`;
    let res = cache ? await cache.match(entry.url) : null;
    const fromCache = !!res;
    let banked = null;
    if (!res) {
      res = await fetch(entry.url);
      if (!res.ok) throw new Error(`${entry.path} -> HTTP ${res.status}`);
      // The body can only be read once, so a clone is banked before streaming
      // and filed afterwards. Filing it first would make a refused write —
      // which large bodies draw on a machine short of disk — the reason the
      // voice did not load.
      banked = cache ? res.clone() : null;
    }
    await streamIntoMemfs(target, res.body, entry.bytes, (n) => {
      prog.add(n);
      if (!fromCache) { downloaded += n; dl.add(n); }
    });
    if (banked) await keep(cache, entry.url, banked);
  }
  prog.done();
  // A fully cached load downloaded nothing; a final downloading:0 would read as
  // a stalled transfer to anything driving a progress bar off these.
  if (downloaded > 0) dl.done();
}

async function doLoad(manifestUrl, sherpaBase) {
  const manifest = await readManifest(manifestUrl);
  await loadSherpa(sherpaBase || 'assets/packages/sherpa_onnx_web/assets/');
  await installFiles(manifest);

  const model = `${MEMFS_ROOT}/${manifest.model}`;
  const config = {
    offlineTtsModelConfig: {
      offlineTtsKokoroModelConfig: {
        model,
        voices: `${MEMFS_ROOT}/${manifest.voices}`,
        tokens: `${MEMFS_ROOT}/${manifest.tokens}`,
        dataDir: manifest.dataDir ? `${MEMFS_ROOT}/${manifest.dataDir}` : '',
        lengthScale: 1.0,
        lexicon: '',
        lang: '',
      },
      numThreads: 1,
      debug: false,
      provider: 'cpu',
    },
    ruleFsts: '',
    ruleFars: '',
    maxNumSentences: 1,
  };

  tts = createOfflineTts(Module, config);
  if (!tts) throw new Error('createOfflineTts returned nothing');

  // onnxruntime has parsed the weights into the wasm heap by now, so the MEMFS
  // copy is the largest dead object in the process.
  try {
    Module.FS.unlink(model);
  } catch (e) {
    // Losing the reclaim is survivable; failing the load over it is not.
  }

  loadedManifestUrl = manifestUrl;
}

// --------------------------------------------------------------- synthesis

function drain() {
  if (draining) return;
  draining = true;
  // A macrotask hop per item keeps the worker's own message pump alive between
  // synthesies, so `unload` and further `generate`s are received while a burst
  // is being worked through.
  const step = () => {
    const job = queue.shift();
    if (!job) { draining = false; return; }
    try {
      if (!tts) throw new Error('not loaded');
      const audio = tts.generate({
        text: job.text,
        sid: job.sid | 0,
        speed: typeof job.speed === 'number' ? job.speed : 1.0,
      });
      const samples = audio.samples instanceof Float32Array
          ? audio.samples
          : new Float32Array(audio.samples);
      post({
        type: 'audio',
        id: job.id,
        samples,
        sampleRate: audio.sampleRate,
      }, [samples.buffer]);
    } catch (e) {
      fail(e && e.message || e, job.id);
    }
    setTimeout(step, 0);
  };
  setTimeout(step, 0);
}

// ---------------------------------------------------------------- protocol

self.onmessage = async (ev) => {
  const msg = ev.data || {};
  try {
    switch (msg.type) {
      case 'status': {
        const manifest = await readManifest(msg.manifestUrl);
        const cache = await openCache();
        const have = await cachedBytes(cache, manifest._urls);
        post({
          type: 'status',
          id: msg.id,
          cachedBytes: have,
          totalBytes: manifest._total,
          complete: have >= manifest._total,
        });
        break;
      }

      case 'warm': {
        const manifest = await readManifest(msg.manifestUrl);
        const cache = await openCache();
        if (!cache) throw new Error('Cache API unavailable (insecure context?)');
        const dl = progressEmitter('downloading', manifest._total);
        for (const entry of manifest._urls) {
          if (await cache.match(entry.url)) { dl.add(entry.bytes); continue; }
          const res = await fetch(entry.url);
          if (!res.ok) throw new Error(`${entry.path} -> HTTP ${res.status}`);
          const banked = res.clone();
          // Drain the body so progress tracks bytes actually received.
          const reader = res.body.getReader();
          for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            dl.add(value.length);
          }
          await keep(cache, entry.url, banked);
        }
        dl.done();
        const have = await cachedBytes(cache, manifest._urls);
        post({
          type: 'status',
          id: msg.id,
          cachedBytes: have,
          totalBytes: manifest._total,
          complete: have >= manifest._total,
        });
        break;
      }

      case 'load': {
        if (!(tts && loadedManifestUrl === msg.manifestUrl)) {
          // Concurrent loads share one attempt rather than racing two engines
          // into the same MEMFS tree. Each waiter answers its own caller.
          if (!loading) {
            loading = doLoad(msg.manifestUrl, msg.sherpaBase)
                .finally(() => { loading = null; });
          }
          await loading;
        }
        post({
          type: 'ready',
          id: msg.id,
          sampleRate: tts.sampleRate,
          numSpeakers: tts.numSpeakers,
        });
        break;
      }

      case 'generate': {
        queue.push(msg);
        drain();
        break;
      }

      // No `unload`. Freeing the engine does not give the memory back —
      // Emscripten never shrinks a wasm heap, so the 512 MB stays as long as
      // this worker does. Measured: freeing moved 4 MB, terminating the worker
      // moved 570 MB. So the app terminates it and spawns another when it next
      // needs one, which from a warm cache is under a second.

      case 'evict': {
        if (typeof caches !== 'undefined') await caches.delete(CACHE_NAME);
        post({ type: 'evicted', id: msg.id });
        break;
      }

      default:
        fail(`unknown message type ${msg.type}`, msg.id);
    }
  } catch (e) {
    fail(e && e.message || e, msg.id);
  }
};
