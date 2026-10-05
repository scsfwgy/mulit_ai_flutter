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
flutter build macos --release --no-pub

mac_version=$(awk '/^version:/{print $2}' pubspec.yaml)
mac_stamp=$(date +%Y%m%d-%H%M%S)
mac_output="$PWD/release-artifacts/macos/$mac_version-$mac_stamp"
mac_stage=$(mktemp -d "${TMPDIR:-/tmp}/ai-link-macos.XXXXXX")
trap 'rm -rf "$mac_stage"' EXIT
mkdir -p "$mac_output"
ditto "build/macos/Build/Products/Release/AI Link.app" "$mac_stage/AI Link.app"
ln -s /Applications "$mac_stage/Applications"
hdiutil create -quiet -volname "AI Link" -srcfolder "$mac_stage" \
  -format UDZO "$mac_output/AI-Link-$mac_version.dmg"
ditto -c -k --sequesterRsrc --keepParent "$mac_stage/AI Link.app" \
  "$mac_output/AI-Link-$mac_version.zip"
codesign --verify --deep --strict "$mac_stage/AI Link.app"
shasum -a 256 "$mac_output"/*.dmg "$mac_output"/*.zip > "$mac_output/SHA256SUMS.txt"
echo "macOS artifacts: $mac_output"
echo "Local build only; Developer ID signing and notarization were not performed."
