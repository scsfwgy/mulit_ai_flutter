#!/usr/bin/env bash
# 无参数构建所有支持平台的正式包；显式开关才发布 Android 到官网或 Google Play。
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

profile="release"
platform=""
ios_export_options="${IOS_EXPORT_OPTIONS_PLIST:-}"
push_release=0
push_website=0
play_track="internal"
wear_track=""
json_key="${PLAY_SERVICE_ACCOUNT_JSON:-$repo_root/localConfig/google-play-service-account.json}"

usage() {
  echo "用法：./release.sh [--platform all|android|ios|macos] [--test] [--push-release|--push-website] [--ios-export-options 路径] [--play-track internal|alpha|beta|production] [--wear-track wear:轨道名] [--json-key 路径]"
  echo "  （无参数）        构建 Android/Wear OS APK/AAB、iOS/Apple Watch IPA 与归档、macOS APP/DMG/ZIP；仅本地归档"
  echo "  --platform      只构建所选平台；all 包含所有支持平台，Apple 平台需 Mac/Xcode；本机无 iOS 分发证书时自动跳过 iOS"
  echo "  --ios-export-options  iOS 本地 IPA 导出 plist；也可设 IOS_EXPORT_OPTIONS_PLIST"
  echo "  --test          构建本地测试签名的手机和 Wear OS APK；不上传"
  echo "  --push-release  默认只构建 Android；APK 同步官网，同时上传两个 AAB 到 Google Play"
  echo "  --push-website  默认只构建 Android；APK 同步 AI Link 官网；不上传 Google Play"
  echo "  --play-track    手机轨道；Wear OS 自动使用 wear:<轨道>"
  echo "  --wear-track    指定已有手表轨道，可与手机轨道名称不同"
  echo "  --json-key      服务账号 JSON 路径；也可设 PLAY_SERVICE_ACCOUNT_JSON"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      [[ $# -ge 2 ]] || { echo "--platform 缺少平台" >&2; exit 2; }
      platform="$2"; shift 2 ;;
    --ios-export-options)
      [[ $# -ge 2 ]] || { echo "--ios-export-options 缺少路径" >&2; exit 2; }
      ios_export_options="$2"; shift 2 ;;
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
# Preserve Android-only test/upload commands while making local Release default all.
if [[ -z "$platform" ]]; then
  platform="all"
  if [[ "$profile" == "test" ]] || (( push_release || push_website )); then platform="android"; fi
fi
build_android=0
build_ios=0
build_macos=0
case "$platform" in
  all) build_android=1; build_ios=1; build_macos=1 ;;
  android) build_android=1 ;;
  ios) build_ios=1 ;;
  macos) build_macos=1 ;;
  *) echo "不支持的平台：$platform" >&2; exit 2 ;;
esac
if [[ "$profile" == "test" && "$platform" != "android" ]]; then
  echo "--test 仅支持 Android 手机与 Wear OS；Apple 调试请使用 install-dev.sh。" >&2
  exit 2
fi
if (( (push_release || push_website) && ! build_android )); then
  echo "官网/Google Play 上传需要 --platform android 或 all。" >&2
  exit 2
fi

ios_signing_available() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  grep -E '"(Apple|iPhone|iOS) Distribution' <<< "$identities" >/dev/null
}

ios_skip_reason=""
if (( build_ios || build_macos )); then
  [[ "$(uname -s)" == "Darwin" ]] || { echo "Apple 正式包需要 Mac 和完整 Xcode；仅构建 Android 可用 --platform android。" >&2; exit 2; }
  xcrun --sdk macosx --show-sdk-path >/dev/null
  if (( build_ios )); then
    xcrun --sdk iphoneos --show-sdk-path >/dev/null
    xcrun --sdk watchos --show-sdk-path >/dev/null
    if [[ -n "$ios_export_options" && ! -f "$ios_export_options" ]]; then
      echo "iOS 导出配置不存在：$ios_export_options" >&2
      exit 2
    fi
  fi
fi
# 无参数默认全平台，但本机可能只有开发证书；此时跳过 iOS，只把明确点了 iOS 的情况当错误。
if (( build_ios )) && ! ios_signing_available; then
  if (( ! build_android && ! build_macos )); then
    echo "没有 iOS Distribution 证书和 App Store 描述文件，无法导出正式 IPA。" >&2
    exit 2
  fi
  ios_skip_reason="本机没有 iOS Distribution 证书和 App Store 描述文件"
  build_ios=0
  echo "跳过 iOS：${ios_skip_reason}。"
fi
export AI_LINK_SIGNING_PROFILE="$profile"

if (( build_android )); then

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
fi

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
{
  echo "profile=$profile"
  echo "platform=$platform"
  echo "versionName=$name"
  echo "appleVersion=$base_name"
  echo "appleBuildNumber=$code"
  echo "gitHead=$git_hash"
  echo "buildStatus=BUILDING"
} > "$output/release-info.txt"
artifacts=()

# 各步骤只更新状态变量，收尾统一汇总，避免结果散落在构建日志里。
android_status="未构建"
macos_status="未构建"
ios_status="未构建"
website_status="未执行"
play_status="未执行"
failure_reason=""
failed_command=""
summary_printed=0

print_summary() {
  local item
  if (( summary_printed )); then return 0; fi
  summary_printed=1
  echo
  echo "================= 本次发布汇总 ================="
  echo "版本：$version    提交：$git_hash"
  echo "归档目录：$output"
  echo
  echo "构建结果"
  echo "  Android 手机 / Wear OS：$android_status"
  echo "  macOS：$macos_status"
  echo "  iOS / Apple Watch：$ios_status"
  if [[ -n "$ios_skip_reason" ]]; then echo "  跳过原因：$ios_skip_reason"; fi
  echo
  if [[ -n "${artifacts[0]:-}" ]]; then
    echo "本地产物"
    for item in "${artifacts[@]}"; do echo "  $output/$item"; done
  else
    echo "本地产物：无"
  fi
  echo
  echo "上传结果"
  echo "  官网：$website_status"
  echo "  Google Play：$play_status"
  if [[ -n "$failure_reason" ]]; then
    echo
    echo "失败原因：$failure_reason"
    if [[ -n "$failed_command" ]]; then echo "失败命令：$failed_command"; fi
    echo "详细状态：$output/release-info.txt"
  fi
  echo "================================================"
}

fail() {
  failure_reason="$1"
  echo "$1" >&2
  print_summary
  exit 1
}

build_failed() {
  local name
  set +e
  for name in android_status macos_status ios_status; do
    [[ "${!name}" == "构建中" ]] && printf -v "$name" '%s' "失败"
  done
  failure_reason="构建命令执行失败"
  failed_command="$1"
  echo "buildStatus=FAILED" >> "$output/release-info.txt"
  echo "构建或上传失败，已生成的本地产物保留在：$output" >&2
  print_summary
  exit 1
}
trap 'build_failed "$BASH_COMMAND"' ERR

echo "本次构建平台：${platform}；本地归档：$output"

echo "分析与测试 Flutter 项目..."
flutter pub get
flutter analyze
flutter test

archive_build() {
  local format="$1" module mapping
  if [[ "$phone_cert" != "$wear_cert" || "$phone_cert" != "$expected_cert" ]]; then
    fail "手机和手表 $format 签名与已记录的 $profile 证书不一致；已停止。"
  fi
  # 每种格式构建后立即保存，避免后续构建覆盖对应的 R8 映射。
  for module in app wear; do
    mapping="$repo_root/build/$module/outputs/mapping/release/mapping.txt"
    [[ -s "$mapping" ]] || fail "缺少 $module R8 mapping.txt"
    mkdir -p "$output/$format/$module-r8"
    cp "$repo_root/build/$module/outputs/mapping/release/"*.txt "$output/$format/$module-r8/"
  done
  compgen -G "$output/$format/dart-symbols/*.symbols" >/dev/null || fail "缺少 $format Dart 调试符号"
}

if (( build_android )); then
android_status="构建中"
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
artifacts+=("$(basename "$phone_apk")" "$(basename "$wear_apk")")
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
{
  echo "androidStatus=COMPLETE"
  echo "phoneVersionCode=$code"
  echo "wearVersionCode=$watch_code"
  echo "certificateSHA256=$phone_cert"
  echo "phone=$phone"
  echo "wear=$wear"
  echo "phoneApk=$phone_apk"
  echo "wearApk=$wear_apk"
  echo "playTrack=$play_track"
  echo "wearTrack=$wear_track"
} >> "$output/release-info.txt"
echo "Android 签名证书 SHA-256：$phone_cert"
android_status="成功"
if [[ "$profile" == "test" ]]; then android_status="成功（测试签名）"; fi
fi

if (( build_macos )); then
  macos_status="构建中"
  echo "构建 macOS Release APP/DMG/ZIP..."
  python3 scripts/apple_release.py --platform macos --output "$output/macos" \
    --version "$base_name" --build-number "$code"
  artifacts+=("macos/AI-Link-$base_name+$code.dmg" "macos/AI-Link-$base_name+$code.zip")
  echo "macosStatus=COMPLETE" >> "$output/release-info.txt"
  macos_status="成功"
fi
if (( build_ios )); then
  ios_status="构建中"
  echo "构建 iOS 与配套 Apple Watch 正式签名 IPA/xcarchive..."
  ios_command=(python3 scripts/apple_release.py --platform ios --output "$output/ios" \
    --version "$base_name" --build-number "$code")
  if [[ -n "$ios_export_options" ]]; then ios_command+=(--export-options-plist "$ios_export_options"); fi
  "${ios_command[@]}"
  artifacts+=("ios/AI-Link-$base_name+$code.ipa")
  echo "iosWatchStatus=COMPLETE" >> "$output/release-info.txt"
  ios_status="成功"
elif [[ -n "$ios_skip_reason" ]]; then
  echo "iosWatchStatus=SKIPPED" >> "$output/release-info.txt"
  echo "iosSkipReason=$ios_skip_reason" >> "$output/release-info.txt"
  ios_status="跳过"
fi
(cd "$output" && shasum -a 256 "${artifacts[@]}" > SHA256SUMS)
echo "buildStatus=COMPLETE" >> "$output/release-info.txt"

if (( push_website )); then
  echo "上传手机与 Wear OS APK 到 OSS 并同步 AI Link 官网..."
  if ! "$python_bin" scripts/website_release.py \
    --phone-apk "$phone_apk" --wear-apk "$wear_apk" \
    --version "$name" --version-code "$code" --wear-version-code "$watch_code" \
    --manifest-out "$output/website-release.json"; then
    echo "websiteStatus=FAILED" >> "$output/release-info.txt"
    website_status="失败"
    fail "官网下载同步未完成；Google Play 未上传。"
  fi
  echo "websiteStatus=CONFIRMED" >> "$output/release-info.txt"
  website_status="成功"
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
    play_status="失败"
    fail "Google Play 上传未完成，详情见 $upload_log"
  fi
  status_line="$(sed -n 's/^PLAY_UPLOAD_STATUS=//p' "$upload_log" | tail -1)"
  if [[ "$status_line" != COMMITTED\|* ]]; then
    echo "playStatus=UNKNOWN" >> "$output/release-info.txt"
    play_status="状态未知"
    fail "Play API 未返回确认状态，请到 Console 核对。"
  fi
  echo "playStatus=$status_line" >> "$output/release-info.txt"
  play_status="成功"
  echo "手机和 Wear OS 版本已提交；审核及上线状态以 Play Console 为准。"
else
  echo "playStatus=NOT_UPLOADED" >> "$output/release-info.txt"
fi

print_summary
