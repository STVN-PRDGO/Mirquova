#!/usr/bin/env bash
# Debug-signed ARM64 phone APK; no production signing credentials are used.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source scripts/Use-Toolchains.sh
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an installed Android NDK}"
cargo ndk -t arm64-v8a --platform 24 \
  -o apps/mirquova_flutter/android/app/src/main/jniLibs \
  build -p mirquova-core --lib --release --locked
cd apps/mirquova_flutter
flutter --suppress-analytics --no-version-check pub get --enforce-lockfile
flutter --suppress-analytics --no-version-check build apk --debug --target-platform android-arm64 --no-pub
