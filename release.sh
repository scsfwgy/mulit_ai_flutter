#!/usr/bin/env bash
# Build signed phone and Wear OS app bundles locally. This script never uploads.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./release.sh (builds signed phone and Wear OS AABs; no upload)"
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo "Unknown arguments. Run ./release.sh --help" >&2
  exit 2
fi

python3 - <<'PY'
from pathlib import Path

root = Path.cwd()
config = root / 'android/key.properties'
if not config.is_file():
    raise SystemExit('Missing android/key.properties. See android/key.properties.example.')
values = {}
for line in config.read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        values[key.strip()] = value.strip()
required = ('storeFile', 'storePassword', 'keyAlias', 'keyPassword')
if any(not values.get(key) or values[key].startswith('REPLACE_') for key in required):
    raise SystemExit('Release signing configuration is incomplete.')
store = root / 'android' / values['storeFile']
if not store.is_file():
    raise SystemExit('The release keystore file does not exist.')
PY

version="$(sed -n 's/^version: //p' pubspec.yaml | head -1)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "pubspec.yaml version must use x.y.z+buildNumber" >&2
  exit 2
fi
name="${version%%+*}"
code="${version##*+}"
watch_code="$((1000000 + code))"

flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
(cd android && ./gradlew :wear:bundleRelease "-PwatchVersionCode=$watch_code" "-PwatchVersionName=$name")

output="$repo_root/release-artifacts/$version"
mkdir -p "$output"
cp build/app/outputs/bundle/release/app-release.aab "$output/AI-Link-phone-$version.aab"
cp build/wear/outputs/bundle/release/wear-release.aab "$output/AI-Link-wear-$version.aab"
(cd "$output" && shasum -a 256 ./*.aab > SHA256SUMS)
echo "Signed bundles saved to $output"
echo "Phone versionCode=$code; Wear versionCode=$watch_code; package=com.maxhall.ailink"
