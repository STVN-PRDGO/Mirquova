#!/usr/bin/env bash
# Unsigned device app or ARM64 simulator preview. IPA export requires signing.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source scripts/Use-Toolchains.sh
[[ "$(uname -s)" == Darwin ]] || { echo 'iOS builds require macOS and full Xcode.' >&2; exit 1; }
xcrun --sdk iphoneos --show-sdk-path >/dev/null
# Keep Rust's linker target aligned with Runner.xcodeproj. Rust defaults to
# iOS 10, but AWS-LC's Apple object files reference symbols exposed from iOS 13.
export IPHONEOS_DEPLOYMENT_TARGET=15.0
mode="${1:-device}"
case "$mode" in
  device|ipa) rust_target=aarch64-apple-ios ;;
  simulator) rust_target=aarch64-apple-ios-sim ;;
  *) echo 'Usage: bash scripts/Build-iOS.sh [device|simulator|ipa]' >&2; exit 1 ;;
esac
if [[ "$mode" == ipa && -z "${MIRQUOVA_IOS_EXPORT_OPTIONS:-}" ]]; then
  echo 'Set MIRQUOVA_IOS_EXPORT_OPTIONS to your signing export-options plist; configure your team in Xcode first.' >&2
  exit 1
fi
cargo build -p mirquova-core --lib --release --locked --target "$rust_target"
cd apps/mirquova_flutter
flutter --suppress-analytics --no-version-check pub get --enforce-lockfile
case "$mode" in
  device) flutter --suppress-analytics --no-version-check build ios --release --no-codesign --no-pub ;;
  simulator) flutter --suppress-analytics --no-version-check build ios --simulator --debug --no-pub ;;
  ipa) flutter --suppress-analytics --no-version-check build ipa --release --no-pub --export-options-plist="$MIRQUOVA_IOS_EXPORT_OPTIONS" ;;
esac
case "$mode" in
  device) app_binary=build/ios/iphoneos/Runner.app/Runner ;;
  simulator) app_binary=build/ios/iphonesimulator/Runner.app/Runner ;;
  ipa) app_binary=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Runner ;;
esac
python3 - "$app_binary" <<'PY'
import subprocess
import sys

symbols = subprocess.check_output(['xcrun', 'nm', '-gU', sys.argv[1]], text=True)
exports = {line.split()[-1] for line in symbols.splitlines() if line.split()}
for name in ['mq_abi_version', 'mq_discovery_start', 'mq_discovery_stop',
             'mq_discovery_snapshot', 'mq_string_free', 'mq_presence_start',
             'mq_presence_stop', 'mq_pairing_identity_create',
             'mq_pairing_identity_free', 'mq_pairing_identity_validate',
             'mq_pairing_host_start', 'mq_pairing_join',
             'mq_pairing_approve', 'mq_pairing_reject',
             'mq_pairing_snapshot', 'mq_pairing_stop']:
    if '_' + name not in exports:
        raise SystemExit('Missing iOS native ABI export: ' + name)
print('PASS all sixteen Rust discovery and pairing ABI exports are linked into the iOS app.')
PY
