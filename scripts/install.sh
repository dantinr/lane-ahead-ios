#!/bin/bash
set -euo pipefail
TASK_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_PROJECT_ROOT"
if [ "$#" -ne 1 ]; then
    echo 'Usage: bash scripts/install.sh DEVICE_ID (see xcrun devicectl list devices)' >&2
    exit 1
fi
TASK_INFO="$(mktemp "${TMPDIR:-/tmp}/lane-ahead-device.XXXXXX")"
trap 'rm -f "$TASK_INFO"' EXIT
xcrun devicectl device info details --device "$1" --json-output "$TASK_INFO" --timeout 20 >/dev/null
TASK_UDID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["hardwareProperties"]["udid"])' "$TASK_INFO")"
IOS_DEVICE_ID="$TASK_UDID" bash scripts/build.sh device
xcrun devicectl device install app --device "$1" "$TASK_PROJECT_ROOT/build/device/Build/Products/Debug-iphoneos/LaneAhead.app" --timeout 60
xcrun devicectl device process launch --device "$1" com.laneahead.ios --timeout 30
