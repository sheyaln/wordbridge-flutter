# Reporting

How a crash, a bug or an idea gets from a tablet to us, and what may travel with
it. See REQUIREMENTS.md §4.52 for why it is shaped this way.

## The rule

**The app never phones home on its own.** Not for a crash, not for a metric, not
on a timer, not on first launch. Every byte that leaves a device leaves because
a person opened a screen, read what was in the report, and pressed send.

There is no background upload, no retry daemon, no queue that drains later. A
report that failed to send stays on screen marked unsent.

## What is in a report

```jsonc
{
  "schema": 1,
  "kind": "crash",              // crash | bug | idea
  "app":    { "version": "0.1.0", "build": "1" },
  "device": { "platform": "ios", "os": "Version 18.5 (Build 22F76)",
              "model": "iPad11,1", "locale": "en_GB" },
  "board":  { "rows": 7, "cols": 12, "level": 2, "engine": "neural" },
  "note":   "free text the reporter typed",
  "detail": "scrubbed exception and stack — crash reports only",
  "voice":  { /* only when voice measurement consent is on; see below */ }
}
```

### What may never be in one

Excluded by construction, not by intention:

| Never sent | Why |
|---|---|
| Profile name, user's name | It is a disabled person's name |
| Any button label or board content | Every word on the board is a word somebody says |
| Any utterance, any usage row | It is a transcript of private speech |
| The device id from §4.49 | It exists to group usage rows on one tablet. Sending it would let two reports be linked to one person |
| Anything from the backups folder | A backup contains all of the above |

`note` and `detail` are the two fields that could carry any of it by accident.
`note` is typed by a person who can see what they are typing. `detail` is
scrubbed.

### Scrubbing

A stack trace is assembled from whatever threw, and this codebase throws messages
that quote board and word names deliberately — `refusalToMoveRow` names the
board, `moveRow` rethrows it, `refusalToPin` names the word. So a trace is never
trusted:

- Anything inside single or double quotes becomes `"…"`.
- Absolute filesystem paths become `<path>`, which also removes the account name
  from a macOS or Linux path.
- The result is capped, and truncation is marked.

Scrubbing runs before the report is **shown**, not only before it is sent, so
what a caregiver reviews is exactly what would leave.

## The intake

```
POST /v1/reports
Content-Type: application/json
Authorization: Bearer <intake token>
```

The token is compiled in with `--dart-define=WORDBRIDGE_INTAKE_TOKEN=…`. It is
extractable from the binary and is not a security control — it is there so that
the endpoint is not trivially discoverable and abusable, and so that the token
can be rotated without a store release breaking older builds if the server keeps
accepting the previous one.

The endpoint URL is compiled in the same way, with
`--dart-define=WORDBRIDGE_INTAKE_URL=…`. **A build with neither is a build with
no reporting**, and the screen says so rather than offering a send button that
cannot work. That is the correct state for a fork, and for anyone building from
source.

### Responses

| Status | Meaning | What the app shows |
|---|---|---|
| `202` | Accepted. Body `{"reference": "…"}` | The reference, so a caregiver can quote it |
| `400` | Schema not understood | "This version cannot send reports. Update the app." |
| `401` | Token rejected | The same message. Nothing about tokens |
| `413` | Too large | "That report is too long to send." |
| `429` | Rate limited | "Too many reports from here just now. Try later." |
| anything else, or no reply | — | "It could not be sent." The report is kept |

The server that implements this is in `intake/` — Go, deployed to Scaleway
Serverless Containers with Object Storage and Transactional Email behind it.
See `intake/README.md` for running and deploying it.

### What the server must do

- Reject bodies over **64 KB**.
- Rate limit by source address.
- Reject an unknown `schema`.
- Store no source address alongside the report body beyond what rate limiting
  needs, and not for longer.
- Return a short human-quotable reference.

### What the server must not do

- Set a cookie, or anything else that would let two reports be tied together.
- Redirect. The client does not follow redirects, on purpose: a redirect is a
  way for an intake to be repointed at somewhere nobody agreed to.

## Voice measurements

Off by default, its own switch, separate from usage tracking (§4.44). The two
are different questions and one answer must not stand for the other.

```jsonc
"voice": {
  "engine": "kokoro",
  "model": "<model id and version>",
  "budget_base_ms": 747,
  "budget_per_word_ms": 262,
  "fallback_count": 3,
  "fallbacks": [ { "reason": "budget", "words": 12 } ],
  "cache_hits": 128,
  "cache_misses": 9,
  "synthesis_ms": [412, 980, 1502]
}
```

**`NeuralSpeechEngine.fallbacks` carries `(at, text, reason)` and `text` is the
sentence the user was trying to say.** The telemetry type therefore cannot hold
it: `voiceMeasurements()` builds a separate record with no field to put it in,
and a test asserts that a fallback whose text is a distinctive string produces a
payload that does not contain that string anywhere.

What this cannot answer is "it pronounced this word wrong". That is accepted. A
mispronunciation is reported as a bug, by a human who typed the word themselves
into a report they read before sending.

## Crashes

`installFallbackBoard()` means a crash does not end the session — the user is
still holding a tablet that still talks, and interrupting them to ask about a
stack trace would be the wrong thing at the wrong moment.

So the sequence is:

1. `FlutterError.onError` and `PlatformDispatcher.instance.onError` write a
   scrubbed record to a file. Fire and forget: a process on its way down is not
   given a network call to finish, and the write cannot be allowed to throw.
2. The board keeps working. `FallbackBoard` shows the detail on screen where the
   error was fatal to a widget.
3. On the **next** launch the caregiver settings screen shows that a report is
   waiting, with its full contents.
4. Nothing is sent until somebody presses send. Discard is offered just as
   plainly.

At most a small number of crash records are kept, oldest dropped first. A tablet
that has crashed two hundred times has a problem that the first few records
already describe.
