#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source scripts/Use-Toolchains.sh
[[ "$(uname -s)" == Linux ]] || { echo 'Build Linux on a Linux host.' >&2; exit 1; }
cargo build -p mirquova-core --lib --release --locked
export MIRQUOVA_CORE_BUNDLE="$PWD/target/release/libmirquova_core.so"
cd apps/mirquova_flutter
flutter --suppress-analytics --no-version-check pub get --enforce-lockfile
flutter --suppress-analytics --no-version-check build linux --release --no-pub
for bundle in build/linux/*/release/bundle; do
  cp ../../THIRD_PARTY_NOTICES.md "$bundle/"
  cp -R ../../third_party "$bundle/"
done
# Keep the entire build/linux/<architecture>/release/bundle directory together.
