#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./release-macos.sh"
  echo "Checks, builds, and packages a local macOS Release app and DMG."
  echo "Developer ID signing and notarization are separate distribution steps."
  exit 0
fi
if [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS and full Xcode are required." >&2
  exit 1
fi

flutter pub get
flutter analyze --no-pub
flutter test --no-pub
mac_version=$(awk '/^version:/{print $2}' pubspec.yaml)
mac_stamp=$(date +%Y%m%d-%H%M%S)
mac_output="$PWD/release-artifacts/macos/$mac_version-$mac_stamp"
python3 scripts/apple_release.py --platform macos --output "$mac_output" \
  --version "${mac_version%%+*}" --build-number "${mac_version##*+}"
echo "macOS artifacts: $mac_output"
echo "Local build only; Developer ID signing and notarization were not performed."
