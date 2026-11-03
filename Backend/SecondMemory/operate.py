"""Preparation-only HTTPS operator. No Meta credential loading or inference mode.

serve stays in the foreground, binds loopback and forces the existing engine off.
probe uses only the cancellation route with a fresh unknown UUID, never /status
or /analyze. Device credentials come from the environment, not command arguments.
"""
import argparse
import json
import os
from pathlib import Path
import ssl
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import ThreadingHTTPServer

from meta_visual import Engine, Failure, NoRedirect, handler, require


def token_from_environment():
    token = os.environ.get("ENKI_DEVICE_TOKEN", "")
    require(32 <= len(token) <= 512 and not any(c.isspace() for c in token)
            and not token.startswith(("LLM_", "sk-")), "device_credential_required")
    return token


def disabled_engine(state, token):
    directory = Path(state)
    require(directory.is_absolute() and directory.is_dir(), "existing_private_state_directory_required")
    require(not any(p.is_symlink() for p in [directory, *directory.parents]), "unsafe_state_directory")
    require(directory.stat().st_mode & 0o077 == 0, "private_state_directory_required")
    # Ignore any inherited Meta key/enabled flag/budget: preparation cannot infer.
    return Engine(directory / "ledger.sqlite", token, key="", enabled=False,
                  credits_verified=False, budget=0, max_requests=1)


def make_server(engine, cert, key, port=8443):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server = ThreadingHTTPServer(("127.0.0.1", port), handler(engine))
    server.daemon_threads = True
    try:
        server.socket = context.wrap_socket(server.socket, server_side=True)
    except Exception:
        server.server_close()
        raise
    return server


def validated_url(value):
    url = urllib.parse.urlsplit(value)
    require(url.scheme == "https" and url.hostname and not url.username and not url.password
            and not url.query and not url.fragment and url.path in ("", "/"), "https_origin_required")
    return value.rstrip("/")


def probe(origin, token, context=None):
    origin = validated_url(origin)
    context = context or ssl.create_default_context()
    # No command-line insecure/alternate-CA flag; custom contexts are test injection only.
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=context))
    body = json.dumps({"observation_id": str(uuid.uuid4())}).encode()

    def call(credential):
        headers = {"Content-Type": "application/json"}
        if credential is not None:
            headers["Authorization"] = "Bearer " + credential
        req = urllib.request.Request(origin + "/api/second-memory/cancel", data=body, headers=headers)
        try:
            with opener.open(req, timeout=8) as response:
                return response.status, json.loads(response.read(4097))
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read(4097))

    code, payload = call(None)
    require(code == 401 and payload == {"error": "unauthorized"}, "unauthenticated_access_not_rejected")
    code, payload = call(token)
    require(code == 200 and payload == {"cancelled": False}, "authenticated_probe_failed")
    return {"tls_chain_and_hostname": "verified-by-client", "unauthenticated": "rejected",
            "device_authentication": "accepted", "meta_requests": 0,
            "images_sent": 0, "probe": "unknown-uuid-cancel-only"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    serve = sub.add_parser("serve")
    serve.add_argument("--state", required=True)
    serve.add_argument("--cert", required=True)
    serve.add_argument("--tls-key", required=True)
    serve.add_argument("--port", type=int, default=8443)
    check = sub.add_parser("probe")
    check.add_argument("--url", required=True)
    args = parser.parse_args()
    try:
        token = token_from_environment()
        if args.action == "probe":
            print(json.dumps(probe(args.url, token), sort_keys=True))
            return
        require(1024 <= args.port <= 65535, "unprivileged_port_required")
        engine = disabled_engine(args.state, token)
        with make_server(engine, args.cert, args.tls_key, args.port) as server:
            print("PREPARATION ONLY: loopback HTTPS; Meta disabled; budget 0; Ctrl-C stops.", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
            print("Stopped. Ledger retained; no image storage.")
    except Failure as error:
        print("Stopped safely: " + error.code)
        raise SystemExit(1)
    except Exception:
        # Never serialize paths, headers, keys or arbitrary network/server errors.
        print("Stopped safely: TLS, connectivity or configuration could not be verified.")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
