"""Local TLS test certificates only: no trust-store changes, Meta calls or images."""
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch

from meta_visual import Failure
from operate import disabled_engine, make_server, probe, token_from_environment, validated_url


class OperatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("openssl"):
            raise unittest.SkipTest("Existing openssl needed; never installed automatically")
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name).resolve()
        cls.cert = cls.root / "test.crt"
        cls.key = cls.root / "test.key"
        config = cls.root / "test.cnf"
        config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n"
                          "[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost\n"
                          "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\n")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-config", str(config), "-keyout", str(cls.key), "-out", str(cls.cert)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        os.chmod(cls.key, 0o600)
        cls.token = "SYNTHETIC-OPERATOR-DEVICE-TOKEN-NOT-A-PROVIDER-KEY"
        cls.engine = disabled_engine(cls.root, cls.token)
        cls.calls = []
        def forbidden(*args, **kwargs):
            cls.calls.append(True)
            raise AssertionError("No provider calls allowed")
        cls.engine.transport = forbidden
        cls.server = make_server(cls.engine, str(cls.cert), str(cls.key), port=0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = "https://localhost:" + str(cls.server.server_address[1])

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join(timeout=3)
        cls.temp.cleanup()

    def test_local_tls_auth_and_no_provider_call(self):
        # Test-only trust for this request. Never installed in Keychain or iOS.
        result = probe(self.url, self.token, ssl.create_default_context(cafile=str(self.cert)))
        self.assertEqual(result["meta_requests"], 0)
        self.assertEqual(self.calls, [])

    def test_untrusted_certificate_rejected(self):
        with self.assertRaises(Exception): probe(self.url, self.token)

    def test_wrong_hostname_rejected(self):
        with self.assertRaises(Exception):
            probe(self.url.replace("localhost", "127.0.0.1"), self.token,
                  ssl.create_default_context(cafile=str(self.cert)))

    def test_wrong_device_token_rejected(self):
        with self.assertRaises(Failure):
            probe(self.url, "WRONG-NOT-VALID-DEVICE-CREDENTIAL", ssl.create_default_context(cafile=str(self.cert)))

    def test_loopback_only(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")

    def test_inherited_enabled_flags_cannot_enable_inference(self):
        with patch.dict(os.environ, {"ENKI_REMOTE_ENABLED": "1", "META_MODEL_API_KEY": "SYNTHETIC",
                                    "ENKI_BUDGET_USD": "999"}):
            engine = disabled_engine(self.root, self.token)
        self.assertFalse(engine.enabled); self.assertEqual(engine.key, ""); self.assertEqual(engine.budget, 0)
        with self.assertRaises(Failure): engine.status()

    def test_reject_http_credentials_paths_and_queries(self):
        for value in ["http://localhost", "https://user:pass@example.invalid", "https://x.invalid/path",
                      "https://x.invalid?key=x", "https://x.invalid/#x"]:
            with self.assertRaises(Failure): validated_url(value)

    def test_provider_key_cannot_be_device_token(self):
        for token in ["", "LLM_" + "x"*40, "sk-" + "x"*40]:
            with patch.dict(os.environ, {"ENKI_DEVICE_TOKEN": token}):
                with self.assertRaises(Failure): token_from_environment()


if __name__ == "__main__":
    unittest.main()
