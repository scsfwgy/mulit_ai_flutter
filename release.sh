#!/usr/bin/env bash
# Build signed phone and Wear OS packages locally. This script never uploads.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

profile="release"
case "${1:-}" in
  --help|-h)
    echo "Usage: ./release.sh [--test]"
    echo "  default: sign phone and Wear OS AABs with the formal upload key"
    echo "  --test:  sign installable phone and Wear OS APKs with the separate test key"
    exit 0 ;;
  --test) profile="test"; shift ;;
esac
if [[ $# -ne 0 ]]; then
  echo "Unknown arguments. Run ./release.sh --help" >&2
  exit 2
fi
export AI_LINK_SIGNING_PROFILE="$profile"

python3 - <<'PY'
from pathlib import Path
import os

root = Path.cwd()
profile = os.environ['AI_LINK_SIGNING_PROFILE']
config = root / 'android' / ('key.test.properties' if profile == 'test' else 'key.properties')
if not config.is_file():
    raise SystemExit(f'Missing {config.relative_to(root)}. See its .example file.')
values = {}
for line in config.read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        values[key.strip()] = value.strip()
required = ('storeFile', 'storePassword', 'keyAlias', 'keyPassword')
if any(not values.get(key) or values[key].startswith('REPLACE_') for key in required):
    raise SystemExit(f'{profile} signing configuration is incomplete.')
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
if [[ "$profile" == "test" ]]; then
  flutter build apk --release
  (cd android && ./gradlew :wear:assembleRelease "-PwatchVersionCode=$watch_code" "-PwatchVersionName=$name")
else
  flutter build appbundle --release
  (cd android && ./gradlew :wear:bundleRelease "-PwatchVersionCode=$watch_code" "-PwatchVersionName=$name")
fi

output="$repo_root/release-artifacts/$profile/$version"
mkdir -p "$output"
if [[ "$profile" == "test" ]]; then
  cp build/app/outputs/flutter-apk/app-release.apk "$output/AI-Link-phone-test-$version.apk"
  cp build/wear/outputs/apk/release/wear-release.apk "$output/AI-Link-wear-test-$version.apk"
  (cd "$output" && shasum -a 256 ./*.apk > SHA256SUMS)
else
  cp build/app/outputs/bundle/release/app-release.aab "$output/AI-Link-phone-$version.aab"
  cp build/wear/outputs/bundle/release/wear-release.aab "$output/AI-Link-wear-$version.aab"
  (cd "$output" && shasum -a 256 ./*.aab > SHA256SUMS)
fi
echo "$profile signed packages saved to $output"
echo "Phone versionCode=$code; Wear versionCode=$watch_code; package=com.maxhall.ailink"
