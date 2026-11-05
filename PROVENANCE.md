# Provenance and release boundary

Pre-event reference: `9ee8afcdc2e8adf7c650c83ffbfdfff147546d48`
(author/committer 25 October 2026, 21:41:19 +01:00). Source branch:
`feature/enki-plasma-stellar`. Private-host changes remain separate from the public package history; no fabricated
commit dates or publication history are used. Absence from a baseline and file
modification dates are not independent proof of when authorship began.

## New work included in the independent package

| Public path | Private source / treatment |
| --- | --- |
| Core/ENKIObservationSession.swift | New SecondMemory state machine; copied unchanged from MetaFury/Modules/SecondMemory |
| Core/ENKIRemoteVisualContract.swift | New strict result/consent contract, copied unchanged from that module |
| Core/ENKISecondMemoryStore.swift | New explicit local evidence persistence/query, copied unchanged from that module |
| Tests/ENKIObservationTests.swift | New policy tests, copied unchanged from scripts/ |
| Tests/ENKISecondMemoryStoreTests.swift | New storage/privacy tests, copied unchanged from scripts/ |
| Backend/SecondMemory/meta_visual.py | New 2C standard-library Meta adapter; no private host dependency |
| Backend/SecondMemory/receipt.py | New explicit record/replay helper; real execution not automatic |
| Backend/SecondMemory/operate.py + test_operator.py | New preparation-only HTTPS operator and loopback TLS tests |
| Backend/SecondMemory/test_meta_visual.py + test_readiness.py | Synthetic transport and error-contract checks |
| Backend/SecondMemory/fixtures/* | Original procedural fixture, generator and manifest; no private photos |
| Tools/MemoryDemo.swift + run_checks.py | New standalone synthetic harness; no API/camera use |
| Tools/recorded_memory.py + RecordedMemory.swift + test_recorded_memory.py | New offline evaluation adapter joining an explicitly supplied result to the actual native store/query; tests only use synthetic receipts |
| Documentation/contracts | Prepared original release material and schema; not a submission |

The package manifest contains hashes of each reviewed file. A separate private
allowlist maps exact source and destination names; no wildcard extraction is used.
Native core source files are absent from the pre-event baseline. The public
adapter exposes the same core/backend path independently of private UI. Private camera hooks, SwiftUI views and lifecycle adapters include new event
work intertwined with the pre-existing host. They are explicitly excluded from
this reference package, not described as old work. Judges can run the new public
core/backend path without them; rebuilding the exact native iPhone UI is not a
capability of this package. If the final rules require every native adapter, this
boundary needs organizer confirmation or a further approved extraction.

## Pre-existing and excluded

ENKI's private iOS shell, AppState, authentication/P0, MWDAT camera integration,
Voice, Apple Vision memory, audiovisual library, recorder, AutoVlog and Replay
predate the event. They are not presented as newly built or public dependencies.
The package's memory store is a separate new Second Memory namespace, not the
pre-existing Apple Vision memory. Meta/Apple frameworks and examples are not
copied or redistributed. No pre-existing Git history is included.

No profiles, private keys, credentials, account identifiers, logs, personal media,
app binaries, backups or private real-call receipt may be added to this package.
The reviewed JPEG is a generated public-candidate input, not physical footage.
The first authentic Meta call used that synthetic input; permission to publish its
receipt or provider output is not inferred from permission to run it.

## Release gates

MIT approved and applied to this independent package only, with copyright held by
Richard A Gómez. R Majestic Studio is the project brand, not a legal corporation.
The independent reference package is publicly available at
https://github.com/RMajestic/enki-second-memory. The hackathon entry was submitted
on 5 November 2026. Its reviewed 2:52 video was supplied separately to the judges;
neither the video nor its access link is distributed in this repository.

Completed publication/submission steps do not imply full physical end-to-end
validation. The footage demonstrates real observation and voice transcription;
a completed physical capture → remote analysis → saved evidence → spoken recall
remains unvalidated. The earlier real Meta receipt stays private, and the public
tests still use explicitly synthetic responses. No private iOS adapter, credential,
account record or original ENKI history is added by this documentation update.
