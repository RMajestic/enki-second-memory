# HTTPS operations — preparation mode only

This package does not provision a public backend. The owner has separately
approved and verified a temporary Cloudflare HTTPS tunnel in preparation-only
mode, with Meta disabled. Its device credential and URL are not part of this
public-candidate package. A judge uses their own approved destination. Do not disable ATS/TLS checks,
install a self-signed root on the iPhone, or expose the experimental Python server
publicly. Any public deployment/tunnel needs explicit owner approval first.

## Existing local tools / offline diagnostic

```sh
python3 -B -m unittest discover -s Backend/SecondMemory -p 'test_operator.py' -v
```

Tests use an ephemeral loopback HTTPS server and temporary localhost certificate.
The certificate is trusted only inside that test client's injected context; no
system/iPhone trust changes occur. They test TLS rejection, hostname rejection,
401 without device authorization, correct authorized cancellation routing and
zero provider calls. They do not prove a trusted deployment is available.

## Foreground start — after approved TLS and device credential setup

Run from the independent package root. Supply the existing dedicated device token
through an approved server-side environment/secret manager, never a command literal,
API key in iOS, screenshot or Git. `ENKI_DEVICE_TOKEN` must not be a Meta API key.
Create a dedicated private state directory (0700) before starting. It is persistent;
never delete or rotate an existing ledger to bypass its request limit.
The paths below are explicit placeholders, not runnable defaults.

```sh
python3 -B Backend/SecondMemory/operate.py serve \
  --state /ABSOLUTE/PRIVATE/APPROVED/STATE \
  --cert /ABSOLUTE/APPROVED/TLS/CERTIFICATE.pem \
  --tls-key /ABSOLUTE/PRIVATE/APPROVED/TLS/KEY.pem \
  --port 8443
```

This operator **always** binds 127.0.0.1, uses TLS >=1.2 and forces Meta key empty,
remote disabled, budget zero and one-request ledger limit even if the shell
inherits enabling variables. No daemon, launch agent, global PATH or trust changes.
No secrets are printed. It cannot enable inference. Stop with **Ctrl-C** in the
same terminal. The ledger is retained; no images are stored by the server.

A real private ingress must use an existing trusted certificate/hostname and
approved network path. The iPhone must be able to reach that exact hostname.
No ingress/public exposure is created by these commands. Do not reuse another
product's deployment or authentication merely because it belongs to the owner.

## Connectivity / TLS / device-authentication probe

After the real destination is approved and reachable, supply its matching device
credential in the same protected environment and run:

```sh
python3 -B Backend/SecondMemory/operate.py probe --url https://OWNER-APPROVED-HOSTNAME:8443
```

The client validates the platform-trusted chain and hostname, refuses redirects,
and uses only `/api/second-memory/cancel` with a fresh unknown UUID: first without
a credential (must return 401), then with it (must return cancelled=false).
It sends no image, does not call Meta or `/status`/`/analyze`, and cannot cancel a
known analysis. It prints only technical booleans and zero image/provider calls.
Failure messages suppress raw network errors, tokens and paths.

## iPhone configuration gate

ENKI currently binds backend URL and device credential together in Keychain.
Do not forward an existing credential to a different host or overwrite a working
shared configuration with a Second-Memory-only backend. Inspect configuration
locally with the owner; keep credentials out of recordings. A configuration change
or dedicated adapter must be reviewed before affecting other ENKI services.
The API key stays exclusively on the server; it is never the device credential.

## Real single-inference activation — not performed

The preparation operator deliberately cannot do this. After specific owner approval,
use the existing `meta_visual.py` entrypoint with the same reviewed TLS/authentication
and durable ledger; never enable analysis just to test connectivity. Configure
`ENKI_REMOTE_ENABLED=1`, explicit account attestation, maximum one **new** approved
attempt, zero retries and at most USD 2 internal budget for that authorization.
Do not reset the earlier consumed CLI authorization/ledger. Reconcile cumulative
request limits/reservations rather than replacing a ledger to obtain extra attempts.
Meta's actual bill is not capped by this internal policy.

There is no automatic Keychain reader in this operator. Credential injection needs
review on the chosen server. After the approved attempt, stop the server or restore
the preparation-only mode. Cancel cannot undo an upstream request already accepted.

## Troubleshooting without content

- TLS failure: stop; check certificate dates, chain, hostname and approved route.
- 401: credential mismatch; do not paste a Meta API key into ENKI.
- 503 remote_disabled from `/status`: expected in preparation-only mode.
- iPhone unavailable: unlock/connect with valid pairing; no uninstall/trust reset.
- Profile expiry: stop installation and obtain separate renewal authorization.
- Preserve technical logs, request UUID/status/token counts only, not images/text.
