#!/usr/bin/env python3
"""Fetch checksum-pinned official AMap SDKs into ignored Vendor/."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
manifest_data = (root / 'scripts/sdk-manifest.json').read_bytes()
manifest = json.loads(manifest_data)
fingerprint = hashlib.sha256(manifest_data).hexdigest()
parser = argparse.ArgumentParser()
parser.add_argument('--cache', type=Path, default=root / '.local/sdk-downloads')
args = parser.parse_args()
vendor = root / 'Vendor'
marker = vendor / '.installed-version'
required = ['AMapNaviKit.framework/AMapNaviKit', 'AMapSearchKit.framework/AMapSearchKit',
    'AMapFoundationKit.framework/AMapFoundationKit', 'AMapNaviPrivacy.bundle/PrivacyInfo.xcprivacy',
    'AMapSearchPrivacy.bundle/PrivacyInfo.xcprivacy', 'AMapFoundationPrivacy.bundle/PrivacyInfo.xcprivacy']
if marker.exists() and marker.read_text() == fingerprint and all((vendor / p).exists() for p in required):
    print('AMap SDKs ready: Navi 11.3.100 / Foundation 1.9.4 (No IDFA) / Search 9.8.1')
    raise SystemExit(0)
vendor.mkdir(exist_ok=True)
args.cache.mkdir(parents=True, exist_ok=True)
for entry in manifest['archives']:
    archive = args.cache / ('lane-ios-' + entry['name'] + '.zip')
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != entry['sha256']:
        print('Downloading official SDK:', entry['name'], flush=True)
        subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--max-time', '180',
            entry['url'], '--output', str(archive)], check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != entry['sha256']:
        raise SystemExit('SDK checksum mismatch; refusing to install ' + entry['name'])
    with zipfile.ZipFile(archive) as package:
        if entry['name'].endswith('-privacy'):
            sdk = {'navi': 'Navi', 'search': 'Search', 'foundation': 'Foundation'}[entry['name'].split('-')[0]]
            bundle = vendor / ('AMap' + sdk + 'Privacy.bundle')
            bundle.mkdir(exist_ok=True)
            item = next(n for n in package.namelist() if n.endswith('.xcprivacy') and not n.startswith('__MACOSX'))
            (bundle / 'PrivacyInfo.xcprivacy').write_bytes(package.read(item))
            (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.laneahead.vendor.' + entry['name'],
                'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '1', 'CFBundleName': bundle.stem}))
        else:
            for item in package.infolist():
                if item.filename.startswith('__MACOSX'): continue
                destination = (vendor / item.filename).resolve()
                if not destination.is_relative_to(vendor.resolve()): raise SystemExit('Unsafe SDK archive entry')
                package.extract(item, vendor)
marker.write_text(fingerprint)
print('AMap SDKs installed; official privacy manifests included.')
