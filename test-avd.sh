#!/usr/bin/env bash
# Creates an Android 14 AVD (stock, no GSI), installs LombardSetup, launches it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_HOME:?Set ANDROID_HOME}"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
IMG="system-images;android-34;google_apis;x86_64"   # use arm64-v8a on Apple silicon / ARM hosts
AVD=LombardTest
APK="$ROOT/output/LombardSetup-debug.apk"
[ -f "$APK" ] || { echo "Run scripts/build-setup.sh first"; exit 1; }

sdkmanager --install "$IMG" "platform-tools" "emulator"
avdmanager list avd | grep -q "Name: $AVD" || avdmanager create avd -n "$AVD" -k "$IMG" -d pixel_6
emulator -avd "$AVD" -no-snapshot &
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
adb install -r "$APK"
adb shell am start -n com.lombardos.setup/.SetupActivity
echo "Now follow docs/EMULATOR_TEST_PLAN.md (Test 1). Logs: adb logcat -s LombardSetup"
