#!/usr/bin/env bash
# 默认本地归档正式 APK/AAB；显式开关才发布到官网或 Google Play。
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

profile="release"
push_release=0
push_website=0
play_track="internal"
wear_track=""
json_key="${PLAY_SERVICE_ACCOUNT_JSON:-$repo_root/localConfig/google-play-service-account.json}"

usage() {
  echo "用法：./release.sh [--test] [--push-release|--push-website] [--play-track internal|alpha|beta|production] [--wear-track wear:轨道名] [--json-key 路径]"
  echo "  （无参数）        构建正式签名的手机和 Wear OS APK/AAB；仅本地归档"
  echo "  --test          构建本地测试签名的手机和 Wear OS APK；不上传"
  echo "  --push-release  APK 上传 OSS 并同步官网，同时上传两个 AAB 到 Google Play"
  echo "  --push-website  APK 上传 OSS 并同步 AI Link 官网；不上传 Google Play"
  echo "  --play-track    手机轨道；Wear OS 自动使用 wear:<轨道>"
  echo "  --wear-track    指定已有手表轨道，可与手机轨道名称不同"
  echo "  --json-key      服务账号 JSON 路径；也可设 PLAY_SERVICE_ACCOUNT_JSON"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test) profile="test"; shift ;;
    --push-release) push_release=1; push_website=1; shift ;;
    --push-website) push_website=1; shift ;;
    --play-track)
      [[ $# -ge 2 ]] || { echo "--play-track 缺少轨道" >&2; exit 2; }
      play_track="$2"; shift 2 ;;
    --wear-track)
      [[ $# -ge 2 ]] || { echo "--wear-track 缺少轨道" >&2; exit 2; }
      wear_track="$2"; shift 2 ;;
    --json-key)
      [[ $# -ge 2 ]] || { echo "--json-key 缺少路径" >&2; exit 2; }
      json_key="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$play_track" in
  internal|alpha|beta|production) ;;
  *) echo "不支持的 Play 轨道：$play_track" >&2; exit 2 ;;
esac
wear_track="${wear_track:-wear:$play_track}"
if [[ "$wear_track" != wear:* || -z "${wear_track#wear:}" || "${wear_track#wear:}" != *[![:space:]]* ]]; then
  echo "--wear-track 必须使用完整的 wear:<轨道名>" >&2
  exit 2
fi
if (( push_release || push_website )) && [[ "$profile" == "test" ]]; then
  echo "测试签名 APK 不可发布到官网或 Google Play；请去掉 --test。" >&2
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
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "浅克隆的提交次数不完整，请获取完整历史后再发布。" >&2
  exit 2
fi
base_name="${version%%+*}"
git_hash="$(git rev-parse --short=8 HEAD)"
name="$base_name-$git_hash"
code="$(git rev-list --count HEAD)"
watch_code="$((1000000 + code))"
if [[ ! "$code" =~ ^[1-9][0-9]*$ ]] || (( code >= 1000000 || watch_code > 2100000000 )); then
  echo "versionCode 超出手机与手表的独立编号范围" >&2
  exit 2
fi
version="$name+$code"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "警告：工作区存在未提交修改；版本哈希仅标识 HEAD。" >&2
fi
channel="google_play"
if [[ "$profile" == "test" ]]; then channel="unknown"; fi

# Keep the Play proxy scoped to Python commands so local Flutter HTTP tests
# continue to connect directly to their loopback servers.
play_env=(env)
python_bin="$repo_root/scripts/.venv/bin/python"
ensure_publish_dependencies() {
  if [[ ! -x "$python_bin" ]]; then
    python3 -m venv "$repo_root/scripts/.venv"
  fi
  if ! "$python_bin" -c 'import oss2, googleapiclient, google.oauth2, google_auth_httplib2, httplib2' >/dev/null 2>&1; then
    "${play_env[@]}" "$python_bin" -m pip install -r "$repo_root/scripts/requirements.txt"
  fi
  "$python_bin" scripts/website_release.py --check
}
if (( push_release )); then
  resolve_http_proxy() {
    local configured="${http_proxy:-${HTTP_PROXY:-${https_proxy:-${HTTPS_PROXY:-}}}}" candidate
    if [[ -n "$configured" ]]; then printf '%s' "$configured"; return; fi
    if command -v scutil >/dev/null 2>&1; then
      local cfg host port
      cfg="$(scutil --proxy 2>/dev/null)"
      host="$(awk '/^[[:space:]]*HTTPProxy[[:space:]]*:/{sub(/.*:[[:space:]]*/,""); print; exit}' <<< "$cfg")"
      port="$(awk '/^[[:space:]]*HTTPPort[[:space:]]*:/{sub(/.*:[[:space:]]*/,""); print; exit}' <<< "$cfg")"
      if [[ -n "$host" && -n "$port" ]]; then printf 'http://%s:%s' "$host" "$port"; return; fi
    fi
    for candidate in 7897 7890 1080 8080; do
      if curl -sS --proxy "http://127.0.0.1:$candidate" --connect-timeout 1 --max-time 3 \
        -o /dev/null https://www.googleapis.com 2>/dev/null; then
        printf 'http://127.0.0.1:%s' "$candidate"
        return
      fi
    done
  }
  proxy="$(resolve_http_proxy)"
  if [[ -n "$proxy" ]]; then
    play_env+=("http_proxy=$proxy" "https_proxy=$proxy")
    echo "已为 Google Play API 配置 HTTP 代理。"
  fi
  [[ -f "$json_key" ]] || { echo "服务账号密钥不存在：$json_key" >&2; exit 2; }
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "警告：工作区有未提交文件，本次上传产物可能无法由 HEAD 精确复现。" >&2
  fi
  ensure_publish_dependencies
  "${play_env[@]}" "$python_bin" scripts/play_upload.py \
    --json-key "$json_key" --track "$play_track" --wear-track "$wear_track" --check-tracks
fi
if (( push_website && ! push_release )); then ensure_publish_dependencies; fi

normalize_fingerprint() {
  tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]'
}

find_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return
  fi
  local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  find "$sdk_root/build-tools" -maxdepth 2 -type f -name apksigner 2>/dev/null | sort | tail -1
}

apk_cert_sha256() {
  local signer digest
  signer="$(find_apksigner)"
  [[ -n "$signer" ]] || { echo "未找到 apksigner" >&2; return 1; }
  digest="$("$signer" verify --print-certs "$1" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1)"
  [[ -n "$digest" ]] || { echo "无法读取 APK 签名：$1" >&2; return 1; }
  printf '%s' "$digest" | normalize_fingerprint
}

aab_cert_sha256() {
  local digest
  digest="$(keytool -printcert -jarfile "$1" | sed -n 's/^[[:space:]]*SHA256: //p' | head -1)"
  [[ -n "$digest" ]] || { echo "无法读取 AAB 签名：$1" >&2; return 1; }
  printf '%s' "$digest" | normalize_fingerprint
}

history="release-history"
if (( push_release || push_website )); then history="release-publish-history"; fi
stamp="$(date +%Y%m%d%H%M%S)-$$"
output="$repo_root/release-artifacts/$history/$version/$stamp"
mkdir -p "$output"

echo "分析与测试 Flutter 项目..."
flutter pub get
flutter analyze
flutter test

archive_build() {
  local format="$1" module mapping
  if [[ "$phone_cert" != "$wear_cert" || "$phone_cert" != "$expected_cert" ]]; then
    echo "手机和手表 $format 签名与已记录的 $profile 证书不一致；已停止。" >&2
    exit 1
  fi
  # 每种格式构建后立即保存，避免后续构建覆盖对应的 R8 映射。
  for module in app wear; do
    mapping="$repo_root/build/$module/outputs/mapping/release/mapping.txt"
    [[ -s "$mapping" ]] || { echo "缺少 $module R8 mapping.txt" >&2; exit 1; }
    mkdir -p "$output/$format/$module-r8"
    cp "$repo_root/build/$module/outputs/mapping/release/"*.txt "$output/$format/$module-r8/"
  done
  compgen -G "$output/$format/dart-symbols/*.symbols" >/dev/null || {
    echo "缺少 $format Dart 调试符号" >&2; exit 1;
  }
}

apk_channel="official"
apk_suffix=""
expected_cert="7D40427292830784C3DB74560D3F1368B9A0B8E5DACD6D73FFBBD4A771D211DE"
if [[ "$profile" == "test" ]]; then
  apk_channel="unknown"
  apk_suffix="-test"
  expected_cert="F539897F7B786486EBC44F1383AF434DCE6AE6BB3ED12DCF363F6F4633B8596F"
fi
echo "构建 $profile 签名手机与 Wear OS APK..."
flutter build apk --release --build-name="$name" --build-number="$code" --dart-define="APP_CHANNEL=$apk_channel" --obfuscate --split-debug-info="$output/apk/dart-symbols"
(cd android && ./gradlew :wear:assembleRelease "-PwatchVersionCode=$watch_code" "-PwatchVersionName=$name")
phone_apk="$output/AI-Link-phone$apk_suffix-$version.apk"
wear_apk="$output/AI-Link-wear$apk_suffix-$version.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$phone_apk"
cp build/wear/outputs/apk/release/wear-release.apk "$wear_apk"
phone_cert="$(apk_cert_sha256 "$phone_apk")"
wear_cert="$(apk_cert_sha256 "$wear_apk")"
archive_build apk
phone="$phone_apk"
wear="$wear_apk"
artifacts=("$(basename "$phone_apk")" "$(basename "$wear_apk")")
if [[ "$profile" != "test" ]]; then
  echo "构建正式签名手机与 Wear OS AAB..."
  flutter build appbundle --release --build-name="$name" --build-number="$code" --dart-define="APP_CHANNEL=$channel" --obfuscate --split-debug-info="$output/aab/dart-symbols"
  (cd android && ./gradlew :wear:bundleRelease "-PwatchVersionCode=$watch_code" "-PwatchVersionName=$name")
  phone="$output/AI-Link-phone-$version.aab"
  wear="$output/AI-Link-wear-$version.aab"
  cp build/app/outputs/bundle/release/app-release.aab "$phone"
  cp build/wear/outputs/bundle/release/wear-release.aab "$wear"
  phone_cert="$(aab_cert_sha256 "$phone")"
  wear_cert="$(aab_cert_sha256 "$wear")"
  archive_build aab
  artifacts+=("$(basename "$phone")" "$(basename "$wear")")
fi
(cd "$output" && shasum -a 256 "${artifacts[@]}" > SHA256SUMS)
{
  echo "profile=$profile"
  echo "versionName=$name"
  echo "phoneVersionCode=$code"
  echo "wearVersionCode=$watch_code"
  echo "gitHead=$(git rev-parse --short=8 HEAD)"
  echo "certificateSHA256=$phone_cert"
  echo "phone=$phone"
  echo "wear=$wear"
  echo "phoneApk=$phone_apk"
  echo "wearApk=$wear_apk"
  echo "playTrack=$play_track"
  echo "wearTrack=$wear_track"
} > "$output/release-info.txt"
echo "本地产物：$output"
echo "签名证书 SHA-256：$phone_cert"

if (( push_website )); then
  echo "上传手机与 Wear OS APK 到 OSS 并同步 AI Link 官网..."
  if ! "$python_bin" scripts/website_release.py \
    --phone-apk "$phone_apk" --wear-apk "$wear_apk" \
    --version "$name" --version-code "$code" --wear-version-code "$watch_code" \
    --manifest-out "$output/website-release.json"; then
    echo "websiteStatus=FAILED" >> "$output/release-info.txt"
    echo "官网下载同步未完成；Google Play 未上传。" >&2
    exit 1
  fi
  echo "websiteStatus=CONFIRMED" >> "$output/release-info.txt"
else
  echo "websiteStatus=NOT_UPLOADED" >> "$output/release-info.txt"
fi

if (( push_release )); then
  echo "上传手机到 ${play_track}，Wear OS 到 ${wear_track} ..."
  upload_log="$output/play-upload.log"
  if ! "${play_env[@]}" "$python_bin" -u scripts/play_upload.py \
    --json-key "$json_key" \
    --phone-aab "$phone" --wear-aab "$wear" \
    --phone-version-code "$code" --wear-version-code "$watch_code" \
    --track "$play_track" --wear-track "$wear_track" 2>&1 | tee "$upload_log"; then
    echo "playStatus=FAILED" >> "$output/release-info.txt"
    echo "Google Play 上传未完成，详情见 $upload_log" >&2
    exit 1
  fi
  status_line="$(sed -n 's/^PLAY_UPLOAD_STATUS=//p' "$upload_log" | tail -1)"
  if [[ "$status_line" != COMMITTED\|* ]]; then
    echo "playStatus=UNKNOWN" >> "$output/release-info.txt"
    echo "Play API 未返回确认状态，请到 Console 核对。" >&2
    exit 1
  fi
  echo "playStatus=$status_line" >> "$output/release-info.txt"
  echo "手机和 Wear OS 版本已提交；审核及上线状态以 Play Console 为准。"
else
  echo "playStatus=NOT_UPLOADED" >> "$output/release-info.txt"
fi
