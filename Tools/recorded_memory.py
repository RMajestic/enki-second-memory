"""Offline receipt → actual Swift evidence store → key query. Never calls Meta.

Only the reviewed procedural fixture is admitted by this evaluation adapter.
No private receipt is discovered/opened automatically; operator supplies its path.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"Backend/SecondMemory"))
from receipt import replay


def prepare(receipt, image, store, confirm_save=False, confirm_pair=False):
    if not confirm_save or not confirm_pair:
        raise ValueError("Explicit save and image/receipt pairing confirmations required")
    receipt, image, store = Path(receipt), Path(image), Path(store)
    if receipt.is_symlink() or not receipt.is_file() or receipt.stat().st_size > 512_000:
        raise ValueError("Receipt unavailable or oversized")
    if image.is_symlink() or not image.is_file() or image.stat().st_size > 1_000_000:
        raise ValueError("Fixture unavailable")
    manifest = json.loads((ROOT/"Backend/SecondMemory/fixtures/manifest.json").read_text())
    if hashlib.sha256(image.read_bytes()).hexdigest() != manifest["sha256"]:
        raise ValueError("Only the reviewed procedural fixture is allowed")
    if not store.is_absolute() or store.exists() or not store.parent.is_dir() or any(p.is_symlink() for p in [store, *store.parents]):
        raise ValueError("A new absolute store with an existing safe parent is required")
    # Integrity/identity checks, not signed provenance. Operator confirms the image pair.
    result = replay(receipt)["result"]
    if len(json.dumps(result).encode()) > 128_000:
        raise ValueError("Result oversized")
    return result


def compile_bridge(directory):
    binary = Path(directory)/"recorded-memory"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(Path(directory)/"cache"),
                    str(ROOT/"Core/ENKIRemoteVisualContract.swift"), str(ROOT/"Core/ENKISecondMemoryStore.swift"),
                    str(ROOT/"Tools/RecordedMemory.swift"), "-o", str(binary)], check=True)
    return binary


def invoke(binary, result, image, store, temp):
    normalized = Path(temp)/"checked-result.json"
    fd = os.open(normalized, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd,"w") as stream: json.dump(result, stream)
    return subprocess.run([str(binary), str(normalized), str(image), str(store), "--confirmed-local-save"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--new-store", required=True)
    parser.add_argument("--confirm-save", action="store_true")
    parser.add_argument("--confirm-image-pair", action="store_true")
    args = parser.parse_args()
    try:
        result = prepare(args.receipt, args.image, args.new_store, args.confirm_save, args.confirm_image_pair)
        if sys.platform != "darwin": raise ValueError("Existing macOS Swift toolchain required")
        with tempfile.TemporaryDirectory(prefix="ENKI-recorded-evaluation-") as temp:
            outcome = invoke(compile_bridge(temp), result, args.image, args.new_store, temp)
        if outcome.returncode: raise ValueError("Native evidence validation failed")
        print(outcome.stdout.strip())
    except Exception:
        print("Stopped safely: consent, fixture, receipt, platform or local store requires review.")
        raise SystemExit(1)


if __name__ == "__main__": main()
