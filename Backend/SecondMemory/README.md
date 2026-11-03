# ENKI Second Memory 2C — experimental backend

Update, 3 November 2026: one prior real synthetic-image Muse Spark 1.3 CLI
call succeeded. That private receipt is not bundled here; the complete new iPhone
flow remains unvalidated. The preparation-only `operate.py` never loads the Meta
key or permits inference. See the independent package OPERATIONS.md.

Python standard library only, tested here with Python 3.9. No dependencies to install.
No server, credentials, certificate, billing or infrastructure is provisioned automatically.

The iOS adapter reuses ENKI's existing HTTPS backend configuration/device credential.
`ENKI_DEVICE_TOKEN` is a dedicated device authorization, **never the Meta API key**.
No change to the existing backend URL/Keychain record is made by this module.
Deploying at that URL or binding a different development server needs separate approval.

## Operator configuration (not executed in this block)

Supply via the process environment; do not put real values in Git, iOS, command history
or public instructions. No `.env` loader or machine-global configuration changes.

| Variable | Purpose / default |
|---|---|
| `META_MODEL_API_KEY` | Server-only Meta credential; required for real calls |
| `ENKI_DEVICE_TOKEN` | Existing owner/device credential, at least 32 characters |
| `ENKI_REMOTE_ENABLED` | `0` by default; real access requires explicit `1` |
| `META_ACCESS_AND_CREDITS_VERIFIED` | Operator attestation after authenticated verification; default off, not an API proof |
| `ENKI_LEDGER_PATH` | Absolute SQLite path in a private directory (0700), outside the repository |
| `ENKI_BUDGET_USD` | `0` by default; total conservative reservation ceiling |
| `ENKI_MAX_REQUESTS` | `5` default, at most 100, durable across restarts |
| `ENKI_TLS_CERT`, `ENKI_TLS_KEY` | Existing approved HTTPS deployment certificate/key paths |
| `ENKI_BIND`, `ENKI_PORT` | `127.0.0.1`, `8443`; no public binding by default |

Once separately approved/configured: `python3 Backend/SecondMemory/meta_visual.py`.
TLS is mandatory. Do not disable certificate validation, change ATS, generate trust
exceptions or expose this experimental server publicly. One process/owner only;
no multi-tenant authentication, production hardening or hosted availability is claimed.
Use an appropriately bounded HTTPS ingress before any production deployment.

Authenticated routes:

- `GET /api/second-memory/status`: explicitly checks `/v1/models`; no images/inference.
- `POST /api/second-memory/analyze`: one bounded base64 JPEG, timestamp, context,
  observation UUID and explicit `remote_consent=true`; see iOS contract.
- `POST /api/second-memory/cancel`: technical UUID only; best effort. An upstream call
  already accepted cannot be undone, and may incur usage after the client cancels.

## Cost/privacy controls

Only `muse-spark-1.3` Standard, pinned `https://api.meta.ai/v1`, no redirects or retries,
25 s upstream timeout, strict output schema, 2048 output tokens, no Files API, tools,
server-side conversation state, streaming, automatic sample uploads or Contributor mode.
`store=false` does **not** guarantee zero retention by Meta.

The gate reserves about **USD 1.319424 per attempt**, using the full documented
1,048,576-token context at uncached input prices plus the output cap. This deliberately
overestimates a small image; it is neither measured usage nor a provider billing limit.
Do not lower it based on a guessed image token count. Exact preflight token counting
is a possible later optimization after access is verified. Failed/unknown/cancelled
attempts retain their reservation. Reported usage is saved as token counts and a
price-based estimate, never called an invoice. Budget/rate notifications in Meta
are not treated as hard billing caps. No billing settings are changed.

One active call per engine; SQLite also refuses a parallel `reserved` row across
processes. After an abrupt server crash, an unresolved reservation fails closed;
operator reconciliation is required, not an automatic refund/reset. Do not delete
or rotate the ledger to circumvent the budget. Cancellation routing is supported
within the single-process deployment only.

Images remain in request memory, not disk/logs. JPEG container/dimensions are bounded;
full decoding occurs in iOS/provider, not this standard-library server. There is no
automatic face/sensitive-content detector: use only the explicitly authorized synthetic
test scene, inspect the scene yourself, and do not admit third parties/private material.
The ledger contains only request UUID, reservation/status, tokens, estimated cost and
response hash. No text, image, audio, prompt, device identifier or credential.

## Tests / authentic offline evidence

`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Backend/SecondMemory -p 'test_*.py' -v`

Tests inject a synthetic transport. They never call Meta and are not sample inference
evidence. iOS client/model tests likewise use an in-memory URLProtocol.

`receipt.py record --image <authorized-synthetic-JPEG> --output <new-private-absolute-path>
--confirm-authorized-synthetic-image` is a future, separately approved **real** call.
It uses the same durable budget ledger and records the raw provider response without
image bytes, prompts, keys or headers. The earlier separately approved CLI probe ran once; do not rerun it without new authorization. Use a small <=960px
metadata-free test JPEG and review every output before publishing anything.

`python3 Backend/SecondMemory/receipt.py replay --receipt <private-receipt>` performs
no network operation and labels the output as an offline recorded replay. It checks
the provider response hash and identities; hashes detect changes, not authenticity
against a malicious author. A genuine approved capture and API usage record are
needed to establish provenance. An authentic recording remains private pending owner review; no mock recording
is supplied as if real.
