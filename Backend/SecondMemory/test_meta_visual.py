"""Synthetic transport ONLY. No credentials, inference, sockets or private images."""
import base64
import copy
import datetime as dt
import json
from pathlib import Path
import tempfile
import threading
import unittest
import uuid
from meta_visual import Engine, Failure, MODEL, RESERVE_USD, handler, scene_valid, strict_json
from receipt import replay


def observation():
    # Synthetic JPEG container with SOF dimensions; NOT a decodable image/inference fixture.
    image = b'\xff\xd8\xff\xc0\x00\x0b\x08\x00\x10\x00\x10\x01\x01\x11\x00\xff\xd9'
    return {"observation_id": str(uuid.uuid4()), "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
            "context": "Synthetic test only", "remote_consent": True, "image_base64": base64.b64encode(image).decode()}


def reply():
    return {"id": "synthetic-provider-test-id", "model": MODEL, "usage": {"prompt_tokens": 100, "completion_tokens": 40},
            "choices": [{"finish_reason": "stop", "message": {"content": json.dumps({"scene_description": "SYNTHETIC TEST RESPONSE", "objects": [], "uncertainties": ["Not a real inference"]})}}]}


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.calls = []
        self.response = reply()
        self.models = [MODEL]
        def transport(path, key, body=None):
            self.calls.append((path, body))
            return {"data": [{"id": x} for x in self.models]} if path == "models" else copy.deepcopy(self.response)
        self.transport = transport
        self.engine = Engine(Path(self.tmp.name)/'ledger.sqlite', 'test-device-authorization-'*2, key='TEST-ONLY-NOT-A-KEY',
                             enabled=True, credits_verified=True, budget=RESERVE_USD*5, transport=transport)

    def fails(self, code, action):
        with self.assertRaises(Failure) as error:
            action()
        self.assertEqual(error.exception.code, code)

    def test_missing_consent_no_transport(self):
        r = observation(); r['remote_consent'] = False
        self.fails('consent_required', lambda: self.engine.analyze(r)); self.assertEqual(self.calls, [])

    def test_invalid_image(self):
        r = observation(); r['image_base64'] = base64.b64encode(b'not an image').decode()
        self.fails('invalid_image', lambda: self.engine.analyze(r)); self.assertEqual(self.calls, [])

    def test_remote_disabled_default(self):
        self.engine.enabled = False
        self.fails('remote_disabled', lambda: self.engine.analyze(observation())); self.assertEqual(self.calls, [])

    def test_unverified_credits_blocks(self):
        self.engine.credits_verified = False
        self.fails('remote_disabled', lambda: self.engine.analyze(observation()))

    def test_device_unauthorized(self):
        self.fails('unauthorized', lambda: self.engine.authenticate('Bearer wrong'))

    def test_zero_budget_no_network(self):
        self.engine.budget = 0
        self.fails('budget_exceeded', lambda: self.engine.analyze(observation())); self.assertEqual(self.calls, [])

    def test_cap_survives_restart(self):
        self.engine.max_requests = 1
        self.engine.analyze(observation())
        self.engine = Engine(self.engine.ledger, self.engine.token, key='test', enabled=True, credits_verified=True,
                             budget=RESERVE_USD*5, max_requests=1, transport=self.transport)
        self.fails('budget_exceeded', lambda: self.engine.analyze(observation()))

    def test_no_objects_is_valid_synthetic(self):
        result = self.engine.analyze(observation())
        self.assertEqual(result['objects'], []); self.assertEqual(result['model_id'], MODEL)
        self.assertEqual(result['meta_request_id'], 'synthetic-provider-test-id')
        self.assertEqual(len(result['response_sha256']), 64)
        self.assertGreater(result['usage']['estimated_usd'], 0)

    def test_request_is_one_image_standard_not_stored(self):
        self.engine.analyze(observation()); body = self.calls[-1][1]
        self.assertEqual(body['model'], MODEL); self.assertFalse(body['store']); self.assertFalse(body['stream'])
        self.assertEqual(len(body['messages'][1]['content']), 2)
        self.assertEqual(body['max_completion_tokens'], 2048)

    def test_model_unavailable(self):
        self.models = []
        self.fails('model_unavailable', lambda: self.engine.analyze(observation()))

    def test_model_mismatch(self):
        self.response['model'] = 'some-other-model'
        self.fails('model_mismatch', lambda: self.engine.analyze(observation()))

    def test_malformed_response(self):
        self.response['choices'][0]['message']['content'] = '{broken'
        self.fails('invalid_provider_response', lambda: self.engine.analyze(observation()))

    def test_uncalibrated_confidence_rejected(self):
        self.fails('uncalibrated_confidence', lambda: scene_valid({'scene_description':'test','objects':[{'label':'test','attributes':[], 'location_in_scene':'test','confidence':0.99}], 'uncertainties':[]}))

    def test_missing_fields_rejected(self):
        self.fails('invalid_schema', lambda: scene_valid({'scene_description': 'test'}))

    def test_unknown_fields_rejected(self):
        self.fails('invalid_schema', lambda: scene_valid({'scene_description': 'test','objects':[], 'uncertainties':[], 'injected':True}))

    def test_truncated_output_rejected(self):
        self.response['choices'][0]['finish_reason'] = 'length'
        self.fails('incomplete_response', lambda: self.engine.analyze(observation()))

    def test_unknown_usage_rejected(self):
        self.response['usage']['prompt_tokens'] = -1
        self.fails('invalid_usage', lambda: self.engine.analyze(observation()))

    def test_duplicate_no_second_inference(self):
        r = observation(); self.engine.analyze(r); count = len(self.calls)
        self.fails('duplicate_request', lambda: self.engine.analyze(r)); self.assertEqual(len(self.calls), count)

    def test_timeout_keeps_reservation_no_retry(self):
        self.engine.max_requests = 1
        def unavailable(*args): raise Failure('provider_unavailable',502)
        self.engine.transport = unavailable
        self.fails('provider_unavailable', lambda: self.engine.analyze(observation()))
        self.fails('budget_exceeded', lambda: self.engine.analyze(observation()))

    def test_cancel_and_single_inflight(self):
        entered, release = threading.Event(), threading.Event()
        def delayed(path, key, body=None):
            if path == 'models':return {'data':[{'id':MODEL}]}
            entered.set(); release.wait(3); return reply()
        self.engine.transport = delayed; r = observation(); outcomes=[]
        def run():
            try: self.engine.analyze(r)
            except Failure as error:outcomes.append(error.code)
        worker=threading.Thread(target=run);worker.start();self.assertTrue(entered.wait(2))
        try:
            self.fails('busy', lambda:self.engine.analyze(observation()))
            self.assertTrue(self.engine.cancel(r['observation_id'])['cancelled'])
        finally:release.set();worker.join(3)
        self.assertEqual(outcomes,['cancelled']);self.assertFalse(worker.is_alive())

    def test_second_process_cannot_send_parallel(self):
        with self.engine.db() as db:db.execute("INSERT INTO requests VALUES (?,?,?,NULL,NULL,NULL,NULL)",(str(uuid.uuid4()),RESERVE_USD,'reserved'))
        self.fails('busy', lambda:self.engine.analyze(observation()));self.assertEqual(self.calls,[])

    def test_ledger_has_no_image_description_or_credential(self):
        self.engine.analyze(observation())
        raw=Path(self.engine.ledger).read_bytes()
        self.assertNotIn(b'SYNTHETIC TEST RESPONSE',raw);self.assertNotIn(b'TEST-ONLY-NOT-A-KEY',raw);self.assertNotIn(b'image_base64',raw)

    def test_stale_timestamp(self):
        r=observation();r['timestamp']='2020-01-01T00:00:00Z'
        self.fails('stale_observation',lambda:self.engine.analyze(r));self.assertEqual(self.calls,[])

    def test_no_public_simulator_mode(self):
        self.assertFalse(hasattr(self.engine,'simulate'))

    def test_offline_replay_rejects_synthetic_as_authentic(self):
        path=Path(self.tmp.name)/'synthetic.json';path.write_text(json.dumps({'kind':'synthetic-test'}))
        self.fails('not_a_real_recording',lambda:replay(path))

    def test_no_live_key_or_account_access_is_claimed(self):
        result=self.engine.status()
        self.assertTrue(result['model_verified'])  # Only this injected test catalog.
        self.assertFalse('credits_verified' in result)  # No invented account balance/expiry.

    def test_invalid_budget_configuration(self):
        self.fails('invalid_config',lambda:Engine(Path(self.tmp.name)/'invalid.sqlite','test'*10,budget=float('nan')))

    def test_duplicate_json_keys_rejected(self):
        self.fails('duplicate_json_key',lambda:strict_json('{"remote_consent":false,"remote_consent":true}'))


if __name__ == '__main__':
    unittest.main()
