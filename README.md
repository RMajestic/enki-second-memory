# ENKI Second Memory

**Release candidate, 3 November 2026. Not published; MIT licensed independent package.**

ENKI's native iOS host, authentication, Ray-Ban camera integration, audiovisual
library and voice tools existed before this hackathon. The new work is Second
Memory: a bounded authorized observation policy, opt-in single-image Meta analysis,
explicitly saved visual evidence and a deterministic last-key-sighting query.
This independent package contains the new core and backend; it does not require
access to ENKI's private repository, Apple signing identities or personal data.

## What is actually demonstrated?

| Evidence | Status |
| --- | --- |
| Ray-Ban physical observation | Owner previously reported 514 frames / 33 valid samples in 34 seconds; not independently rerun here |
| Meta model use | One prior real Muse Spark 1.3 Standard inference on a procedural synthetic image, through the Mac CLI |
| Independent backend and core | Offline reproducible tests and a synthetic memory demo; not model accuracy evidence |
| iPhone capture → HTTPS → Meta → save → query | Implementation prepared; combined physical validation pending |
| Automatic retained memory / wake word / open conversation | Not implemented; analysis and saving require explicit action |

The project goal is last-observation recall, not surveillance or proof of an
object's current location/ownership. The current saved-memory query supports
keys/keyrings in Spanish or English. It is lexical, not general semantic search.

## Run without keys or private ENKI

Full core/demo: macOS with an **existing** Xcode command-line Swift toolchain,
Python 3.9+ and OpenSSL. No package installation or network access is needed.

```sh
python3 -B run_checks.py
```

This runs the public backend tests, the actual Foundation observation state
machine, the actual local evidence store, and a standalone Swift demo that saves
two explicitly synthetic observations, reopens the store, selects the most recent
capture timestamp, verifies exact image evidence, then deletes each test record.
The recorded-result adapter is also exercised with synthetic receipts, including
missing consent, modified data and an empty/no-key result. Temporary test state
and TLS keys are removed. No system trust store is changed.
The synthetic scene descriptions are **test data**, not Meta-generated answers.

Backend-only checks can run on other supported Python platforms:

```sh
python3 -B run_checks.py --backend-only
```

This explicitly does **not** test the Apple Swift core or the full memory demo.
The TLS test requires existing OpenSSL; absence is reported as a skip, not a pass.

## Architecture / layout

```text
Core/                          new Foundation observation, result and memory contracts
Tests/                         new synthetic policy and storage regressions
Tools/MemoryDemo.swift          synthetic offline harness using the actual core
Tools/recorded_memory.py        offline recorded-result → actual native store/query
Tools/RecordedMemory.swift      public native evaluation adapter
Tools/test_recorded_memory.py   synthetic adapter regressions
Backend/SecondMemory/           bounded Meta adapter, HTTPS preparation operator, tests
  fixtures/                    procedural JPEG + generator + visual-review manifest
contracts/scene.schema.json     strict model-output scene schema
run_checks.py                  isolated, dependency-free check runner
PROVENANCE.md                  pre-event boundary and source treatment
OPERATIONS.md                  HTTPS setup, stop and diagnostics
DEMO_SCRIPT.md + subtitles.en.srt   2:50 evidence-dependent recording plan
FILE_MANIFEST.json             reviewed file hashes; no private Git history
```

Apple frameworks are supplied by the existing OS/toolchain, not redistributed.
No Meta SDK binaries, Xcode project, AppState/private UI, profiles, certificates,
Keychain values, account identifiers or personal captures are included.

## Real Meta route — separate approval needed

The adapter pins `POST https://api.meta.ai/v1/chat/completions` and
`muse-spark-1.3` Standard. One bounded JPEG is submitted as `image_url.url` with
a base64 data URL. The key remains server-side. No Contributor mode, redirects,
automatic retries, streaming video, automatic sample uploads or Files API.
Structured results require objects/scene/uncertainties, null confidence, provider
response identity/hash and usage. Confidence is never invented.

Use your own authorized provider account and current data/billing terms. No
credentials or funded public inference proxy are supplied. The preparation
operator is forced off, budget zero and loopback only. A real run requires a
separately approved trusted HTTPS deployment, device credential and explicit
single-request activation. See [OPERATIONS.md](OPERATIONS.md) and the [backend README](Backend/SecondMemory/README.md).
A local request/ledger limit is not a Meta billing cap. Already transmitted
requests may complete and incur usage after cancellation; reservations persist.

## Prior real Meta verification — non-sensitive summary

The operator previously verified one authorized real request using this package's
procedural JPEG (SHA-256 `2e8bbad6433b5605697269c8bbae0037b721a8d5a76f04565d5237b3eb8708ce`).
The returned model was `muse-spark-1.3`, with a complete validated scene result and
reported usage of 599 input tokens and 1,404 output tokens. The output described
the yellow key-like shape and expressed uncertainty about the blue shape being a
book. This is distinct from the synthetic responses used by automated tests.

That prior result was checked offline for response-hash/identity/scene consistency.
Its private receipt, provider identifier, credentials and account details are not
included. This summary is an operator-verified record, not independently signed
provider evidence. Judges can run their own specifically authorized request using
the documented flow; approved recorded demonstration footage is still pending.
The earlier real call does not establish the pending end-to-end iPhone workflow.
No Meta call is performed by the offline checks.

## Configuration and an authorized Meta result

The offline test command needs no configuration or provider access. For a real
result use your own authorized Meta account and current terms, only after specific
approval for that request. No hosted funded demo is supplied. The server-only
configuration variables and limits are listed in `Backend/SecondMemory/README.md`:
API key, separate device credential, private persistent ledger, explicit enablement,
credit/account attestation, one-request limit and a reviewed internal budget.
Do not put secrets in shell literals, source, iOS, Git or recordings.

With that approved environment already configured, a private directory mode 0700
and no pre-existing output file, the record helper can perform the authorized call:

```sh
python3 Backend/SecondMemory/receipt.py record \
  --image Backend/SecondMemory/fixtures/synthetic-table.jpg \
  --output /ABSOLUTE/PRIVATE/NEW/approved-receipt.json \
  --confirm-authorized-synthetic-image
```

This command **does make a real provider call**; it is not part of `run_checks.py`
and must not be run merely to reproduce offline tests. No retries are automatic.
The procedural fixture contains no private source image. Do not replace it with
personal material for a free-credit or public demonstration test.

## Authentic recorded evidence

`receipt.py replay --receipt /absolute/approved/receipt.json` is an offline replay
of an operator-approved authentic recording. It is never a live call. The earlier
real receipt remains private and is **not** part of this package. No fake receipt
is supplied as genuine provider evidence. Publishing an authentic redacted receipt
or recording needs owner review; missing evidence is a release gate.

```sh
python3 Backend/SecondMemory/receipt.py replay --receipt /absolute/approved/receipt.json
```

Receipt hashes detect accidental changes, not forgery by an author. Verify the
image/output pairing and provider usage independently before claiming accuracy.
The synthetic JPEG in this package is input, not an inference result.

## Saved-result recall without the private iOS host

The public adapter closes the evaluation path: recorded result → strict receipt
checks → actual Swift evidence store → reopen → keys query with timestamp and
image hash. It makes **no API call** and admits only the reviewed procedural JPEG.
Use an authentic, operator-approved receipt from the preceding step or an already
authorized recording; no receipt is bundled by default. Do not infer permission
to publish that receipt or its contents from permission to run it privately.

```sh
python3 -B Tools/recorded_memory.py \
  --receipt /ABSOLUTE/PRIVATE/approved-receipt.json \
  --image Backend/SecondMemory/fixtures/synthetic-table.jpg \
  --new-store /ABSOLUTE/PRIVATE/NEW/test-memory \
  --confirm-save --confirm-image-pair
```

The output is labelled **offline recorded result, not live inference**. The new
store persists locally for inspection and is never an ENKI app container. A missing
key object yields no supported answer; no fake location is inserted. The operator
must check the image/receipt pairing: the earlier receipt format does not bind an
image hash cryptographically, and a receipt hash alone cannot prove authenticity.
The CLI relies on OS permissions and does not claim to implement Face ID.

This replaces the previously missing public bridge. The private iOS SwiftUI/MWDAT
adapters remain optional hardware integration and are not required for this runner.
Those adapters contain new event work too; they are not relabelled as pre-existing.
The public package evaluates the same new core/backend through an independent host,
not a rebuild of the entire private iOS application.

## Privacy and limitations

Physical observation is visible, foreground-only, authorized and bounded to five
minutes and at most one selected sample/second. The observation core contains no
images or network code. iOS adapters are private integration infrastructure.
Remote analysis is separately authorized and manual; it does not inherit camera
consent. Local saving is separately confirmed. The memory store is bounded to
40 records, validates images/results, supports individual confirmed deletion,
and rejects path traversal/symlinks. iOS file protection requires device testing;
the CLI harness does not implement or claim Face ID.

The native memory namespace is excluded from standard backups; use an explicit
verified private backup before app updates. The standalone synthetic runner uses
an isolated temporary store. There is no automatic identification of people or
sensitive content: use only reviewed non-sensitive scenes. `store=false` is not
a zero-retention guarantee by the provider. No funded public inference service is supplied by this package. The owner has
a separately approved temporary connectivity-only HTTPS tunnel; its credential
and URL are not distributed here. Meta remains disabled in that preparation server.

## License / release state

The 28 approved files in this independent package are licensed under [MIT](LICENSE).
Copyright (c) 2026 Richard A Gómez. R Majestic Studio is the project brand,
not an incorporated company. This grant does not cover the original private ENKI
application, third-party services, or trademarks.
No public repository, upload, release or submission has been made.
