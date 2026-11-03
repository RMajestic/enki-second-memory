"""Synthetic receipt inputs ONLY. No provider call or private recording is used."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

spec = importlib.util.spec_from_file_location("recorded_memory", Path(__file__).with_name("recorded_memory.py"))
adapter = importlib.util.module_from_spec(spec); spec.loader.exec_module(adapter)


class RecordedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(); cls.root = Path(cls.temp.name).resolve()
        cls.image = adapter.ROOT/"Backend/SecondMemory/fixtures/synthetic-table.jpg"
        cls.binary = adapter.compile_bridge(cls.root) if sys.platform == "darwin" else None

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def receipt(self, objects=True):
        scene = {"scene_description":"SYNTHETIC REGRESSION ONLY", "objects":[], "uncertainties":["SYNTHETIC TEST, not Meta evidence"]}
        if objects: scene["objects"]=[{"label":"keys", "attributes":[], "location_in_scene":"SYNTHETIC fixture table", "confidence":None}]
        raw = {"id":"SYNTHETIC-NOT-PROVIDER", "model":"muse-spark-1.3", "usage":{"prompt_tokens":0,"completion_tokens":0},
               "choices":[{"finish_reason":"stop","message":{"content":json.dumps(scene)}}]}
        digest = hashlib.sha256(json.dumps(raw,sort_keys=True).encode()).hexdigest()
        result = dict(scene,observation_id=str(uuid.uuid4()),timestamp="2026-11-03T12:00:00Z",model_id="muse-spark-1.3",
                      source="meta-model-api",meta_request_id=raw["id"],response_sha256=digest,
                      usage={"prompt_tokens":0,"completion_tokens":0,"estimated_usd":0})
        path = self.root/(str(uuid.uuid4())+".json")
        path.write_text(json.dumps({"kind":"recorded-meta-call","endpoint":"https://api.meta.ai/v1/chat/completions",
                                   "raw_provider_response":raw,"response_sha256":digest,"result":result}))
        return path

    def test_no_save_without_both_consents(self):
        for a,b in [(False,False),(True,False),(False,True)]:
            with self.assertRaises(ValueError): adapter.prepare(self.receipt(),self.image,self.root/str(uuid.uuid4()),a,b)

    def test_unknown_image_rejected(self):
        image = self.root/"invalid-image";image.write_bytes(b"SYNTHETIC INVALID")
        with self.assertRaises(ValueError): adapter.prepare(self.receipt(),image,self.root/str(uuid.uuid4()),True,True)

    def test_changed_receipt_rejected(self):
        receipt=self.receipt();d=json.loads(receipt.read_text());d["raw_provider_response"]["id"]="changed";receipt.write_text(json.dumps(d))
        with self.assertRaises(Exception): adapter.prepare(receipt,self.image,self.root/str(uuid.uuid4()),True,True)

    def test_existing_store_not_overwritten(self):
        with self.assertRaises(ValueError): adapter.prepare(self.receipt(),self.image,self.root,True,True)

    def test_native_save_reopen_query_from_synthetic_recording(self):
        if not self.binary: self.skipTest("Native evaluation requires macOS")
        store=self.root/str(uuid.uuid4()); result=adapter.prepare(self.receipt(),self.image,store,True,True)
        with tempfile.TemporaryDirectory(dir=self.root) as temp: out=adapter.invoke(self.binary,result,self.image,store,temp)
        self.assertEqual(out.returncode,0);answer=json.loads(out.stdout)
        self.assertTrue(answer["found"]);self.assertTrue(answer["evidence_matches_supplied_fixture"])
        self.assertEqual(answer["provider_request_id"],"SYNTHETIC-NOT-PROVIDER")
        self.assertEqual(answer["mode"],"OFFLINE-RECORDED-RESULT-NOT-LIVE-INFERENCE")

    def test_no_keys_means_no_fabricated_location(self):
        if not self.binary: self.skipTest("Native evaluation requires macOS")
        store=self.root/str(uuid.uuid4());result=adapter.prepare(self.receipt(False),self.image,store,True,True)
        with tempfile.TemporaryDirectory(dir=self.root) as temp:out=adapter.invoke(self.binary,result,self.image,store,temp)
        self.assertEqual(out.returncode,0);answer=json.loads(out.stdout)
        self.assertFalse(answer["found"]);self.assertNotIn("locations",answer)


if __name__ == "__main__": unittest.main()
