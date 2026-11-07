#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK path}"
cd "$ROOT/apps/LombardSetup"
if [ -x ./gradlew ]; then G=./gradlew; else G=gradle; fi
$G --no-daemon :app:assembleDebug
mkdir -p "$ROOT/output"
cp app/build/outputs/apk/debug/app-debug.apk "$ROOT/output/LombardSetup-debug.apk"
echo "Built: $ROOT/output/LombardSetup-debug.apk"
