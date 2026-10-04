#!/usr/bin/env bash
set -euo pipefail

device="emulator-${EMULATOR_PORT:-5554}"
sdk="$(adb -s "$device" shell getprop ro.build.version.sdk | tr -d '\r')"
if [[ "$sdk" != 36 ]]; then
  echo "Expected API 36 at $device; found API $sdk" >&2
  exit 1
fi
mkdir -p .buildlog
adb -s "$device" shell getprop ro.build.version.release > .buildlog/ci-device.log
printf 'device=%s api=%s\n' "$device" "$sdk" >> .buildlog/ci-device.log
for test in pdf tools updates; do
  flutter test "integration_test/${test}_test.dart" -d "$device" --reporter expanded \
    2>&1 | tee ".buildlog/ci-${test}.log"
done
