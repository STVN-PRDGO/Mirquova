#!/usr/bin/env bash
# Build an Apple Silicon preview on a Mac with matching Flutter/Rust toolchains.
# This script never publishes a release or uses an Apple signing credential.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/Use-Toolchains.sh"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  printf '%s\n' 'This preview requires an Apple Silicon macOS host and Xcode.' >&2
  exit 1
fi

native_core="${MIRQUOVA_CORE_BUNDLE:-$project_root/target/aarch64-apple-darwin/release/libmirquova_core.dylib}"

if [[ "${1:-}" == --embed-for-xcode ]]; then
  if [[ ! -f "$native_core" ]]; then
    printf '%s\n' 'The native core is missing. Build with scripts/Build-macOS.sh first.' >&2
    exit 1
  fi
  if [[ "$(lipo -archs "$native_core")" != arm64 ]]; then
    printf '%s\n' 'The native core must contain the arm64 architecture only.' >&2
    exit 1
  fi
  : "${TARGET_BUILD_DIR:?Xcode target directory is required}"
  : "${FRAMEWORKS_FOLDER_PATH:?Xcode frameworks directory is required}"
  framework_directory="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
  mkdir -p "$framework_directory"
  install -m 755 "$native_core" "$framework_directory/libmirquova_core.dylib"
  install_name_tool -id '@rpath/libmirquova_core.dylib' "$framework_directory/libmirquova_core.dylib"
  codesign --force --sign - "$framework_directory/libmirquova_core.dylib"
  exit 0
fi

iteration=iteration-04
if [[ $# -gt 0 ]]; then
  if [[ $# != 2 || "$1" != --iteration || ! "$2" =~ ^iteration-[0-9]{2}$ ]]; then
    printf '%s\n' 'Usage: bash scripts/Build-macOS.sh [--iteration iteration-NN]' >&2
    exit 1
  fi
  iteration="$2"
fi

destination="$project_root/artifacts/$iteration"
archive_name=Mirquova-preview-macos-arm64.zip
checksum_name=Mirquova-preview-macos-arm64.sha256
archive_path="$destination/$archive_name"
if [[ -e "$archive_path" || -e "$destination/$checksum_name" ]]; then
  printf '%s\n' 'Refusing to overwrite an existing macOS preview archive.' >&2
  exit 1
fi

cd "$project_root"
export MACOSX_DEPLOYMENT_TARGET=12.0
cargo build -p mirquova-core --lib --release --locked --target aarch64-apple-darwin
export MIRQUOVA_CORE_BUNDLE="$project_root/target/aarch64-apple-darwin/release/libmirquova_core.dylib"
python3 - "$MIRQUOVA_CORE_BUNDLE" <<'PY'
import ctypes
import sys

core = ctypes.CDLL(sys.argv[1])
core.mq_abi_version.restype = ctypes.c_uint32
if core.mq_abi_version() != 2:
    raise SystemExit('The macOS core ABI does not match this preview.')
PY

cd "$project_root/apps/mirquova_flutter"
flutter --suppress-analytics --no-version-check pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter --suppress-analytics --no-version-check analyze --no-pub
# macOS is the reference raster host for the exact golden-image comparisons.
# Run the complete suite so new tests are included automatically.
flutter --suppress-analytics --no-version-check test --no-pub \
  "--dart-define=MIRQUOVA_CORE_LIBRARY=$MIRQUOVA_CORE_BUNDLE"
flutter --suppress-analytics --no-version-check build macos --release --no-pub
app_path="$PWD/build/macos/Build/Products/Release/mirquova.app"
if [[ ! -f "$app_path/Contents/Frameworks/libmirquova_core.dylib" ]]; then
  printf '%s\n' 'The macOS app is missing its bundled Rust core.' >&2
  exit 1
fi
if [[ "$(lipo -archs "$app_path/Contents/MacOS/mirquova")" != arm64 ]]; then
  printf '%s\n' 'The macOS app must contain the arm64 architecture only.' >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$app_path"
flutter --suppress-analytics --no-version-check test \
  integration_test/native_app_platform_test.dart -d macos --no-pub
codesign --verify --deep --strict --verbose=2 "$app_path"

mkdir -p "$destination" "$project_root/.toolchains"
staging="$(mktemp -d "$project_root/.toolchains/mac-package.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
package_directory="$staging/Mirquova-macos-arm64"
mkdir -p "$package_directory"
ditto "$app_path" "$package_directory/mirquova.app"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$package_directory/THIRD_PARTY_NOTICES.md"
ditto "$project_root/third_party" "$package_directory/third_party"
version_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
printf 'Mirquova %s+%s Apple Silicon development preview\n\n' "$version_name" "$build_number" > "$package_directory/README.txt"
cat >> "$package_directory/README.txt" <<'TXT'
Requires an Apple Silicon Mac running macOS 12 or later.
Extract the ZIP, then move mirquova.app to Applications and open it.
Keep the complete .app bundle together.

This preview is signed ad hoc and has not been notarized by Apple.
If macOS says Apple could not verify mirquova, click Done, then go to
System Settings > Privacy & Security and click Open Anyway for mirquova.
Confirm Open when prompted. This approves this app individually.

For this trusted preview only, an alternative after moving the app to
Applications is to run these two commands in Terminal:
  xattr -dr com.apple.quarantine /Applications/mirquova.app
  open /Applications/mirquova.app
This removes download quarantine from this app; it does not notarize it.
It does not disable Gatekeeper for other apps. ZIP, DMG and PKG downloads
all remain subject to macOS security checks. Developer ID signing and
Apple notarization are required to resolve this for future downloads.

Physical Mac installation, local-network permission behavior and two-device
discovery remain unverified. Intel Macs are not supported by this package.

Nearby discovery candidates are unverified. Pairing, transfer, casting,
playback and online subtitles are not implemented.
Settings > System updates offers an optional GitHub release check.
Checks and direct package downloads require consent in Settings; no GitHub page is needed.
Open downloaded update opens the local archive. Close Mirquova before replacing the app bundle.

Source, build instructions and platform status:
https://github.com/STVN-PRDGO/Mirquova

Third-party notices accompany this preview. No Apple affiliation, store
release, project code license or production signing is implied.
TXT
ditto -c -k --sequesterRsrc --keepParent "$package_directory" "$archive_path"
cd "$destination"
shasum -a 256 "$archive_name" > "$checksum_name"
printf 'Created %s\n' "$archive_path"
printf 'Created %s\n' "$destination/$checksum_name"
