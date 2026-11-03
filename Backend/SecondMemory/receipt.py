"""Explicit future synthetic-image recording and clearly labelled offline replay.

Do not run record before account/credits/data terms and the specific test are approved.
No API key, image bytes or prompt is written to the receipt. Not cryptographic proof of origin.
"""
import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import uuid
from meta_visual import ENDPOINT, MODEL, Engine, Failure, meta_transport, require, scene_valid


def replay(path):
    receipt = json.loads(Path(path).read_text())
    require(receipt.get('kind') == 'recorded-meta-call' and receipt.get('endpoint') == ENDPOINT, 'not_a_real_recording')
    raw = receipt['raw_provider_response']
    require(hashlib.sha256(json.dumps(raw, sort_keys=True).encode()).hexdigest() == receipt['response_sha256'], 'receipt_hash_mismatch')
    require(raw.get('model') == MODEL and raw.get('id') == receipt['result']['meta_request_id'], 'receipt_identity_mismatch')
    scene = scene_valid(json.loads(raw['choices'][0]['message']['content']))
    require(all(receipt['result'].get(key) == value for key, value in scene.items()), 'receipt_result_mismatch')
    require(receipt['result'].get('model_id') == MODEL and receipt['result'].get('source') == 'meta-model-api'
            and receipt['result'].get('response_sha256') == receipt['response_sha256'], 'receipt_identity_mismatch')
    return {'mode': 'offline-recorded-replay-NOT-live-inference', 'result': receipt['result']}


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='mode', required=True)
    off = sub.add_parser('replay'); off.add_argument('--receipt', required=True)
    record = sub.add_parser('record'); record.add_argument('--image', required=True); record.add_argument('--output', required=True)
    record.add_argument('--confirm-authorized-synthetic-image', action='store_true')
    args = parser.parse_args()
    if args.mode == 'replay':
        print(json.dumps(replay(args.receipt), ensure_ascii=False, indent=2)); return
    require(args.confirm_authorized_synthetic_image, 'specific_image_consent_required')
    env = os.environ
    require(env.get('ENKI_REMOTE_ENABLED') == '1' and env.get('META_ACCESS_AND_CREDITS_VERIFIED') == '1', 'remote_disabled')
    output = Path(args.output)
    require(output.is_absolute() and output.parent.is_dir() and output.parent.stat().st_mode & 0o077 == 0, 'private_receipt_directory_required')
    require(not output.exists(), 'receipt_already_exists')
    raw_reply = []
    def capture(path, key, body=None):
        response = meta_transport(path, key, body)
        if path == 'chat/completions': raw_reply.append(response)
        return response
    engine = Engine(env['ENKI_LEDGER_PATH'], env['ENKI_DEVICE_TOKEN'], key=env['META_MODEL_API_KEY'], enabled=True,
                    credits_verified=True, budget=float(env.get('ENKI_BUDGET_USD','0')), max_requests=int(env.get('ENKI_MAX_REQUESTS','5')), transport=capture)
    request = {'observation_id':str(uuid.uuid4()),'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),
               'context':'Explicitly authorized synthetic test only','remote_consent':True,
               'image_base64':base64.b64encode(Path(args.image).read_bytes()).decode()}
    result = engine.analyze(request)
    receipt = {'kind':'recorded-meta-call','endpoint':ENDPOINT,'recorded_at':dt.datetime.now(dt.timezone.utc).isoformat(),
               'response_sha256':result['response_sha256'],'raw_provider_response':raw_reply[0], 'result':result}
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd,'w') as stream:json.dump(receipt,stream,ensure_ascii=False,indent=2)
    print('Recorded one real call into the private receipt. Review before any publication.')


if __name__ == '__main__':
    main()
