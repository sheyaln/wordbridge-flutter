#!/usr/bin/env bash
#
# Puts the neural voice where the web build can fetch it.
#
# The tablet downloads its own model at runtime, from a fixed GitHub release,
# because there is no server behind wordbridge and there should not be one. A
# browser cannot do the same thing: the release is a `.tar.bz2` and nothing in
# a browser decompresses bzip2, so the archive has to be opened once, here, and
# the files served beside the app.
#
# Whoever hosts the web build hosts these files. That is the same bargain as
# the app itself — a static directory and nothing running.
#
#   tools/fetch_web_voice.sh            unpack into app/web/voice/
#   tools/fetch_web_voice.sh --full     keep every language espeak ships
#
# The English trim is the default and saves 17 MB of dictionaries for languages
# this board does not speak. `--full` is there for anyone taking the same files
# somewhere else.
set -euo pipefail

readonly RELEASE=kokoro-int8-en-v0_19
readonly URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${RELEASE}.tar.bz2"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/app/web/voice/$RELEASE"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

full=0
[[ "${1:-}" == "--full" ]] && full=1

echo "Fetching $RELEASE"
curl -fL --progress-bar -o "$work/pack.tar.bz2" "$URL"

digest="$(shasum -a 256 "$work/pack.tar.bz2" | cut -d' ' -f1)"
echo "sha256 $digest"

echo "Unpacking"
rm -rf "$out"
mkdir -p "$out"

# Only the members that are kept, straight into place. Unpacking the whole
# archive first and deleting the rest afterwards wants 160 MB of disk nobody
# asked for, on top of the 103 MB already sitting beside it.
#
# The five binary tables plus `en_dict` are what the phonemizer actually reads.
# Pointing `dataDir` at a tree missing any of them does not degrade — the wasm
# traps with `null function` — so this is a list of what is needed rather than
# a list of what looked small.
members=(
  "$RELEASE/model.int8.onnx"
  "$RELEASE/voices.bin"
  "$RELEASE/tokens.txt"
  "$RELEASE/LICENSE"
)
if (( full )); then
  members+=("$RELEASE/espeak-ng-data")
else
  members+=(
    "$RELEASE/espeak-ng-data/intonations"
    "$RELEASE/espeak-ng-data/phondata"
    "$RELEASE/espeak-ng-data/phondata-manifest"
    "$RELEASE/espeak-ng-data/phonindex"
    "$RELEASE/espeak-ng-data/phontab"
    "$RELEASE/espeak-ng-data/en_dict"
    # A voice file names the variant it inherits from, so the whole `!v`
    # directory travels with the language.
    "$RELEASE/espeak-ng-data/lang/gmw/en*"
    "$RELEASE/espeak-ng-data/voices/!v/*"
  )
fi

tar -xjf "$work/pack.tar.bz2" -C "$out" --strip-components=1 "${members[@]}"
rm -f "$work/pack.tar.bz2"

for f in model.int8.onnx voices.bin tokens.txt; do
  [[ -s "$out/$f" ]] || { echo "missing $f" >&2; exit 1; }
done
for f in intonations phondata phondata-manifest phonindex phontab en_dict; do
  [[ -s "$out/espeak-ng-data/$f" ]] || {
    echo "missing espeak-ng-data/$f" >&2; exit 1; }
done

# What the worker fetches, and in what order. Written here rather than listed
# in Dart because it is 100-odd files and every one of them is a fact about the
# archive rather than a decision anybody made.
python3 - "$out" "$digest" <<'PY'
import json, os, sys

out, digest = sys.argv[1], sys.argv[2]
files = []
for base, _, names in os.walk(out):
    for name in sorted(names):
        path = os.path.join(base, name)
        rel = os.path.relpath(path, out)
        if rel == 'manifest.json':
            continue
        files.append({'path': rel.replace(os.sep, '/'),
                      'bytes': os.path.getsize(path)})

files.sort(key=lambda f: f['path'])
total = sum(f['bytes'] for f in files)

manifest = {
    'release': os.path.basename(out),
    'archiveSha256': digest,
    'model': 'model.int8.onnx',
    'voices': 'voices.bin',
    'tokens': 'tokens.txt',
    'dataDir': 'espeak-ng-data',
    'totalBytes': total,
    'files': files,
}
with open(os.path.join(out, 'manifest.json'), 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')

print(f'{len(files)} files, {total / 1e6:.1f} MB')
PY

echo "Wrote $out"
