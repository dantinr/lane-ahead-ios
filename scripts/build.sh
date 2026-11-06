#!/bin/bash
set -euo pipefail
TASK_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_PROJECT_ROOT"
MODE="${1:-simulator}"
if [ "$MODE" = "test" ]; then
    swift test
    exit 0
fi
python3 scripts/setup-sdk.py
python3 scripts/prepare-config.py
python3 scripts/generate-project.py
if [ "$MODE" = "device" ]; then
    TASK_TEAM="${DEVELOPMENT_TEAM:-}"
    if [ -z "$TASK_TEAM" ] && [ -f .local/team-id ]; then TASK_TEAM="$(cat .local/team-id)"; fi
    if [[ ! "$TASK_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
        echo 'Set DEVELOPMENT_TEAM or save your Team ID in .local/team-id.' >&2
        exit 1
    fi
    TASK_DESTINATION="generic/platform=iOS"
    if [ -n "${IOS_DEVICE_ID:-}" ]; then TASK_DESTINATION="id=$IOS_DEVICE_ID"; fi
    xcodebuild -project LaneAhead.xcodeproj -scheme LaneAhead -configuration Debug \
        -destination "$TASK_DESTINATION" -derivedDataPath build/device \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration "DEVELOPMENT_TEAM=$TASK_TEAM" build
elif [ "$MODE" = "simulator" ]; then
    xcodebuild -project LaneAhead.xcodeproj -scheme LaneAhead -configuration Debug \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build
else
    echo 'Usage: bash scripts/build.sh [simulator|device|test]' >&2
    exit 1
fi
