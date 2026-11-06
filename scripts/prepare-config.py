#!/usr/bin/env python3
"""Generate an ignored resource; never print an API key."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent
source = root / '.local/gaode-ios'
key = source.read_text().strip() if source.exists() else ''
if key and not re.fullmatch(r'[a-fA-F0-9]{32}', key):
    raise SystemExit('Invalid iOS map key: .local/gaode-ios must contain exactly one 32-character key.')
output = root / 'LaneAhead/Resources/MapKeys.plist'
data = plistlib.dumps({'AMapIOSKey': key})
output.parent.mkdir(parents=True, exist_ok=True)
if not output.exists() or output.read_bytes() != data:
    output.write_bytes(data)
