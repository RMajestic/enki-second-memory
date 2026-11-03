"""Characterize existing HTTP failure handling. Offline, no keys or network.

HTTP handling is tested with synthetic failures, never a provider request.
"""
import io
import base64
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from meta_visual import Engine, Failure, MODEL, RESERVE_USD, meta_transport, jpeg_valid
from test_meta_visual import observation, reply


class ReadinessTests(unittest.TestCase):
    def check_http(self, status, expected):
        error = HTTPError('https://api.meta.ai/v1/chat/completions', status,
                          'synthetic failure', {}, io.BytesIO(b'{"error":{"code":"synthetic"}}'))
        with patch('meta_visual.urllib.request.build_opener') as builder:
            builder.return_value.open.side_effect = error
            with self.assertRaises(Failure) as caught:
                meta_transport('chat/completions', 'TEST-ONLY-NOT-A-KEY', {})
            self.assertEqual(caught.exception.code, expected)
            self.assertEqual(caught.exception.status, 502)
            self.assertEqual(builder.return_value.open.call_count, 1)

    def test_401_is_unauthorized_no_retry(self): self.check_http(401, 'provider_unauthorized')
    def test_403_is_unauthorized_no_retry(self): self.check_http(403, 'provider_unauthorized')
    def test_402_billing_explicit_no_retry(self): self.check_http(402, 'provider_billing')
    def test_429_rate_limit_no_retry(self): self.check_http(429, 'provider_rate_limit')
    def test_404_model_no_retry(self): self.check_http(404, 'model_unavailable')
    def test_503_server_error_no_retry(self): self.check_http(503, 'provider_error')

    def test_upstream_failure_keeps_reservation_and_attempt_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            def transport(path, key, body=None):
                calls.append(path)
                if path == 'models': return {'data': [{'id': MODEL}]}
                raise Failure('provider_error', 502)
            engine = Engine(Path(directory)/'ledger.sqlite', 'TEST-DEVICE-'*4,
                            key='TEST-ONLY-NOT-A-KEY', enabled=True, credits_verified=True,
                            budget=RESERVE_USD, max_requests=1, transport=transport)
            with self.assertRaises(Failure): engine.analyze(observation())
            with engine.db() as db:
                self.assertEqual(db.execute('SELECT reserve,status FROM requests').fetchone(),
                                 (RESERVE_USD, 'failed_or_cancelled'))
            with self.assertRaises(Failure) as caught: engine.analyze(observation())
            self.assertEqual(caught.exception.code, 'budget_exceeded')
            self.assertEqual(calls, ['models', 'chat/completions'])

    def test_real_decodable_fixture_container_is_accepted(self):
        data = (Path(__file__).parent/'fixtures/synthetic-table.jpg').read_bytes()
        jpeg_valid(data)
        self.assertLessEqual(len(data), 1_000_000)
        self.assertNotIn(b'Exif', data)

    def test_fixture_uses_documented_image_and_schema_contract_offline(self):
        data = (Path(__file__).parent/'fixtures/synthetic-table.jpg').read_bytes()
        calls = []
        def transport(path, key, body=None):
            if path == 'models': return {'data': [{'id': MODEL}]}
            calls.append(body)
            return reply()  # Explicitly synthetic; not saved as real evidence.
        with tempfile.TemporaryDirectory() as directory:
            engine = Engine(Path(directory)/'ledger.sqlite', 'TEST-DEVICE-'*4,
                            key='TEST-ONLY-NOT-A-KEY', enabled=True, credits_verified=True,
                            budget=RESERVE_USD, max_requests=1, transport=transport)
            request = observation()
            request['image_base64'] = base64.b64encode(data).decode()
            engine.analyze(request)
        self.assertEqual(len(calls), 1)
        body = calls[0]
        image = body['messages'][1]['content'][1]
        self.assertEqual(image['type'], 'image_url')
        self.assertEqual(image['image_url']['url'], 'data:image/jpeg;base64,' + request['image_base64'])
        self.assertEqual(body['model'], MODEL)
        self.assertFalse(body['store'])
        self.assertTrue(body['response_format']['json_schema']['strict'])
        self.assertEqual(body['response_format']['json_schema']['schema']['properties']['objects']
                         ['items']['properties']['confidence'], {'type': 'null'})


if __name__ == '__main__': unittest.main()
