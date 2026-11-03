"""Run isolated public-package checks, without a private ENKI checkout or network.

macOS + existing Xcode command-line tools are required for the actual Swift core.
Use --backend-only explicitly on other platforms; that is not a full demo check.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend-only", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    os.chdir(root)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "Backend/SecondMemory",
                    "-p", "test_*.py", "-v"], env=env, check=True)
    if args.backend_only:
        print("BACKEND ONLY: Swift observation, memory and demo NOT TESTED")
        return
    if sys.platform != "darwin":
        raise SystemExit("Full checks need macOS and an existing Swift toolchain; no dependencies installed.")
    with tempfile.TemporaryDirectory(prefix="ENKI-public-checks-") as temp:
        temp = Path(temp).resolve()
        base = ["xcrun", "swiftc", "-D", "DEBUG", "-parse-as-library", "-module-cache-path", str(temp/"cache")]
        def swift(name, sources, arguments=()):
            binary = temp/name
            subprocess.run(base + sources + ["-o", str(binary)], env=env, check=True)
            subprocess.run([str(binary), *arguments], env=env, check=True)
        swift("observation", ["Core/ENKIObservationSession.swift", "Tests/ENKIObservationTests.swift"])
        sources = ["Core/ENKIRemoteVisualContract.swift", "Core/ENKISecondMemoryStore.swift"]
        swift("memory-tests", sources + ["Tests/ENKISecondMemoryStoreTests.swift"])
        swift("memory-demo", sources + ["Tools/MemoryDemo.swift"], ["--new-synthetic-store", str(temp/"demo-store")])
    subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "Tools",
                    "-p", "test_recorded_memory.py", "-v"], env=env, check=True)
    print("PUBLIC PACKAGE CHECKS PASSED — all provider responses synthetic; no Meta calls")


if __name__ == "__main__":
    main()
