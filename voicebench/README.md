# voicebench

The dev bench for wordbridge's optional local neural voice (REQUIREMENTS.md
§4.5). Type anything, pick a voice and a delivery, hear it synthesised from
scratch, see what it cost.

**Separate app, separate bundle id** — `org.wordbridge.voicebench`. It never
touches `org.wordbridge.wordbridge`, and it must not be made to: installing
over the real app replaces the thing somebody speaks with.

## Run it

```sh
./run-bench.sh          # build, install, copy the model, launch
```

Needs an Apple ID at Xcode → Settings → Accounts. Without one Xcode cannot mint
a profile for a bundle id it has not seen, and the build fails with
`No Accounts: Add a new account in Accounts settings`. `./set-team.sh <project>`
stamps the team into a fresh Flutter project.

The model is not in the repo. Fetch it once:

```sh
curl -L -o kokoro.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2
tar xjf kokoro.tar.bz2     # -> kokoro-en-v0_19/  (360 MB)
```

## What the controls are

| Control | What it actually does |
|---|---|
| Voice | Style dims `0:128` — timbre, who it sounds like. Changing it reloads the model. |
| Borrow delivery from | Style dims `128:256` — prosody, how it is said. Free to change. |
| Preset | Sets the two sliders. Nothing more; none of them are emotions. |
| Speed / Gain | Engine speed, and gain applied to our own buffer — gain above 1.0 is louder than the platform can go. |
| Timeout budget | `base + perWord × words`. Exceed it and the platform voice speaks instead. |
| Measure | Sweeps 1–24 words, median of 3, writes `sweep.csv`. |

There are deliberately no emotion presets. Measured: Kokoro's prosody space is
effectively one axis and that axis is pitch, so `sad` and `stern` would be the
speed and pitch sliders wearing names they have not earned.
