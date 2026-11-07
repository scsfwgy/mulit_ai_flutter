#!/usr/bin/env bash
# 无参数构建所有支持平台的正式包，只做本地归档；显式开关才把包发布到官网、Google Play 或 App Store Connect。
#
# 发布开关（可组合；未指定 --platform 时按开关推导需要构建的平台）：
#   --push-website   APK 同步 AI Link 官网（OSS + HomeTools 发布接口）              需要 Android
#   --push-android   官网 + Google Play：APK 到官网，手机与 Wear OS 两个 AAB 到 Play  需要 Android
#   --push-ios       IPA 上传 App Store Connect（TestFlight，不自动提审）            需要 iOS
#   --push-mobile    官网 + Google Play + App Store Connect，同 --push-android --push-ios  需要 Android 与 iOS
#   --push-all       全端：官网（含 Mac/Windows 下载地址）+ Google Play + App Store Connect
#                    需要 Android、iOS、macOS，以及 GitHub Actions 上的 Windows
#
# 常用组合：
#   ./release.sh                             全平台构建并本地归档，不上传
#   ./release.sh --test                      测试签名 APK（仅 Android 手机与 Wear OS）
#   ./release.sh --push-android              Android：官网 + Google Play
#   ./release.sh --push-ios                  iOS：构建并上传 App Store Connect
#   ./release.sh --push-mobile               Android 与 iOS 一起发布（不含 macOS）
#   ./release.sh --push-all                  全端构建并上传；Mac/Windows 安装包生成官网下载地址
#   ./release.sh --platform macos            只构建 macOS
#   ./release.sh --platform desktop          本机 macOS + GitHub Actions Windows，统一归档
#   ./release.sh --platform windows          只在 Windows 主机上构建 Windows 安装程序和 ZIP
#   ./release.sh --github-windows            只通过 GitHub Actions 构建 Windows 并下载安装程序和 ZIP
#   ./release.sh --build-all                 Android/Wear OS、iOS/Apple Watch、macOS + GitHub Windows
#
# 凭据都放在已被 .gitignore 忽略的 localConfig/ 下，脚本只读取、不写入：
#   Android 签名   android/key.properties（正式）与 android/key.test.properties（--test）
#   Google Play    localConfig/google-play-service-account.json，可用 PLAY_SERVICE_ACCOUNT_JSON 覆盖
#   官网与 OSS     localConfig/.env.local，模板 scripts/website_release.env.example
#   App Store      localConfig/appstore-connect.env，模板 scripts/appstore_connect.env.example
#
# 上传结果同时写入归档目录的 release-info.txt，结束时统一打印汇总。
set -Eeuo pipefail
release_started_at=$SECONDS

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

profile="release"
platform=""
requested_build=""
ios_export_options="${IOS_EXPORT_OPTIONS_PLIST:-}"
push_android=0
push_website=0
push_ios=0
push_desktop=0
play_track="internal"
wear_track=""
json_key="${PLAY_SERVICE_ACCOUNT_JSON:-$repo_root/localConfig/google-play-service-account.json}"

usage() {
  echo "用法：./release.sh [--platform all|mobile|android|ios|macos|windows|desktop | --github-windows | --build-all] [--test] [--push-android|--push-website|--push-ios|--push-mobile|--push-all] [--ios-export-options 路径] [--play-track internal|alpha|beta|production] [--wear-track wear:轨道名] [--json-key 路径]"
  echo "  （无参数）        构建 Android/Wear OS APK/AAB、iOS/Apple Watch IPA 与归档、macOS APP/DMG/ZIP；仅本地归档"
  echo "  --platform      只构建所选平台；all 为 Android、iOS 与 macOS，mobile 为 Android + iOS（不含 macOS）；Apple 平台需 Mac/Xcode，本机无 iOS 分发证书时自动跳过 iOS"
  echo "                  windows 不包含在 all 里，且只能在 Windows 主机上构建"
  echo "                  desktop 为本机 macOS + GitHub Actions Windows；需要 gh 登录及已提交、推送的干净工作区"
  echo "                  不指定时按发布开关推导：--push-android/--push-website 取 Android，--push-ios 取 iOS，--push-mobile 或两者同时给出则取 mobile，--push-all 取全端（含远程 Windows）"
  echo "  --github-windows  仅通过 GitHub Actions 构建 Windows 并下载带版本号的 Setup.exe 和 ZIP；需要已推送的干净分支与 Actions 读写权限"
  echo "  --build-all       构建 Android/Wear OS、iOS/Apple Watch、macOS 和 GitHub Windows；需 Mac、Android/Apple 签名及 Actions 权限，缺少 iOS 分发签名时报错"
  echo "                    这两个参数互斥，且均不能与 --platform 或 --test 同用；默认仅本地归档，不上传商店"
  echo "  --ios-export-options  iOS 本地 IPA 导出 plist；也可设 IOS_EXPORT_OPTIONS_PLIST"
  echo "  --test          构建本地测试签名的手机和 Wear OS APK；不上传"
  echo "  --push-android  默认只构建 Android；APK 同步官网，同时上传两个 AAB 到 Google Play"
  echo "  --push-website  默认只构建 Android；APK 同步 AI Link 官网；不上传 Google Play"
  echo "  --push-ios      默认只构建 iOS；把正式签名 IPA 上传到 App Store Connect（TestFlight）；不自动提交审核"
  echo "                  凭据见 localConfig/appstore-connect.env，模板 scripts/appstore_connect.env.example"
  echo "  --push-mobile   同 --push-android --push-ios：同步官网，并上传 Google Play 与 App Store Connect；不构建 macOS"
  echo "  --push-all      构建 Android、iOS、macOS 和 GitHub Windows；APK、Mac DMG 与 Windows 安装包同步官网并生成下载地址，同时上传 Google Play 与 App Store Connect"
  echo "  --play-track    手机轨道；Wear OS 自动使用 wear:<轨道>"
  echo "  --wear-track    指定已有手表轨道，可与手机轨道名称不同"
  echo "  --json-key      服务账号 JSON 路径；也可设 PLAY_SERVICE_ACCOUNT_JSON"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      [[ $# -ge 2 ]] || { echo "--platform 缺少平台" >&2; exit 2; }
      platform="$2"; shift 2 ;;
    --github-windows|--build-all)
      [[ -z "$requested_build" || "$requested_build" == "$1" ]] || {
        echo "--github-windows 与 --build-all 不能同时使用。" >&2; exit 2;
      }
      requested_build="$1"; shift ;;
    --ios-export-options)
      [[ $# -ge 2 ]] || { echo "--ios-export-options 缺少路径" >&2; exit 2; }
      ios_export_options="$2"; shift 2 ;;
    --test) profile="test"; shift ;;
    --push-android) push_android=1; push_website=1; shift ;;
    --push-website) push_website=1; shift ;;
    --push-ios) push_ios=1; shift ;;
    --push-mobile) push_android=1; push_website=1; push_ios=1; shift ;;
    --push-all) push_android=1; push_website=1; push_ios=1; push_desktop=1; shift ;;
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

if [[ -n "$requested_build" ]]; then
  [[ -z "$platform" ]] || { echo "$requested_build 不能与 --platform 同时使用。" >&2; exit 2; }
  case "$requested_build" in
    --github-windows) platform="windows-github" ;;
    --build-all) platform="all-github" ;;
  esac
fi

case "$play_track" in
  internal|alpha|beta|production) ;;
  *) echo "不支持的 Play 轨道：$play_track" >&2; exit 2 ;;
esac
wear_track="${wear_track:-wear:$play_track}"
if [[ "$wear_track" != wear:* || -z "${wear_track#wear:}" || "${wear_track#wear:}" != *[![:space:]]* ]]; then
  echo "--wear-track 必须使用完整的 wear:<轨道名>" >&2
  exit 2
fi
if (( push_android || push_website || push_ios || push_desktop )) && [[ "$profile" == "test" ]]; then
  echo "测试签名的调试包不可发布到官网、Google Play、App Store Connect 或全端下载；请去掉 --test。" >&2
  exit 2
fi
# 未指定 --platform 时按发布开关推导要构建的平台：官网/Google Play 需要 Android，App Store Connect 需要 iOS。
# 两者同时发布只构建 Android 与 iOS，不额外构建 macOS；macOS 请显式用 --platform macos|all。
# --push-all 还要本机 macOS 与 GitHub Actions Windows，用来生成电脑端下载地址。
if [[ -z "$platform" ]]; then
  if (( push_desktop )); then
    platform="all-github"
  elif (( push_ios )) && (( push_android || push_website )); then
    platform="mobile"
  elif (( push_ios )); then
    platform="ios"
  elif (( push_android || push_website )); then
    platform="android"
  else
    platform="all"
  fi
  if [[ "$profile" == "test" ]]; then platform="android"; fi
fi
build_android=0
build_ios=0
build_macos=0
build_windows=0
build_windows_remote=0
case "$platform" in
  all) build_android=1; build_ios=1; build_macos=1 ;;
  mobile) build_android=1; build_ios=1 ;;
  android) build_android=1 ;;
  ios) build_ios=1 ;;
  macos) build_macos=1 ;;
  windows) build_windows=1 ;;
  desktop) build_macos=1; build_windows_remote=1 ;;
  windows-github) build_windows_remote=1 ;;
  all-github) build_android=1; build_ios=1; build_macos=1; build_windows_remote=1 ;;
  *) echo "不支持的平台：$platform" >&2; exit 2 ;;
esac
if (( build_windows )); then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) echo "Windows 安装包只能在 Windows 上构建。" >&2; exit 2 ;;
  esac
fi
if [[ "$profile" == "test" && "$platform" != "android" ]]; then
  echo "--test 仅支持 Android 手机与 Wear OS；Apple 调试请使用 install-dev.sh。" >&2
  exit 2
fi
if (( push_desktop && ! (build_android && build_ios && build_macos && (build_windows || build_windows_remote)) )); then
  echo "--push-all 需要同时构建 Android、iOS、macOS 和 Windows：请单独使用 ./release.sh --push-all，或与 --build-all 一起使用。" >&2
  exit 2
fi
if (( (push_android || push_website) && ! build_android )); then
  echo "官网/Google Play 上传需要构建 Android：请用 --platform android|mobile|all。" >&2
  exit 2
fi
if (( push_ios && ! build_ios )); then
  echo "App Store Connect 上传需要构建 iOS：请用 --platform ios|mobile|all。" >&2
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
  if (( ! build_android && ! build_macos )) || [[ "$platform" == "all-github" ]]; then
    echo "没有 iOS Distribution 证书和 App Store 描述文件，无法导出正式 IPA。" >&2
    exit 2
  fi
  ios_skip_reason="本机没有 iOS Distribution 证书和 App Store 描述文件"
  build_ios=0
  echo "跳过 iOS：${ios_skip_reason}。"
fi
if (( push_ios )) && (( ! build_ios )); then
  echo "iOS 未构建，无法上传 App Store Connect：${ios_skip_reason:-iOS 未参与本次构建}。" >&2
  exit 2
fi
export AI_LINK_SIGNING_PROFILE="$profile"

# 在本机耗时构建前确认远程可构建相同提交；不自动提交或推送代码。
if (( build_windows_remote )); then
  python3 scripts/windows_remote_release.py --check
fi

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

# Keep the proxy scoped to publishing commands so local Flutter HTTP tests
# continue to connect directly to their loopback servers.
publish_env=(env)
python_bin="$repo_root/scripts/.venv/bin/python"
asc_config="$repo_root/localConfig/appstore-connect.env"
ensure_python_runtime() {
  if [[ ! -x "$python_bin" ]]; then
    python3 -m venv "$repo_root/scripts/.venv"
  fi
}
ensure_publish_dependencies() {
  ensure_python_runtime
  if ! "$python_bin" -c 'import oss2, googleapiclient, google.oauth2, google_auth_httplib2, httplib2' >/dev/null 2>&1; then
    "${publish_env[@]}" "$python_bin" -m pip install -r "$repo_root/scripts/requirements.txt"
  fi
  "$python_bin" scripts/website_release.py --check
}
# Google Play 与 App Store Connect 都在境外，共用同一份 HTTP 代理设置。
if (( push_android || push_ios )); then
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
    publish_env+=("http_proxy=$proxy" "https_proxy=$proxy")
    echo "已为发布接口配置 HTTP 代理。"
  fi
fi
if (( push_android )); then
  [[ -f "$json_key" ]] || { echo "服务账号密钥不存在：$json_key" >&2; exit 2; }
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "警告：工作区有未提交文件，本次上传产物可能无法由 HEAD 精确复现。" >&2
  fi
  ensure_publish_dependencies
  "${publish_env[@]}" "$python_bin" scripts/play_upload.py \
    --json-key "$json_key" --track "$play_track" --wear-track "$wear_track" --check-tracks
fi
if (( push_website && ! push_android )); then ensure_publish_dependencies; fi
# 先校验 App Store Connect 凭据与 App 记录，避免 iOS 构建完成后才发现凭据或 Issuer ID 有误。
if (( push_ios )); then
  [[ -f "$asc_config" ]] || {
    echo "App Store Connect 凭据不存在：${asc_config}；模板见 scripts/appstore_connect.env.example" >&2
    exit 2
  }
  ensure_python_runtime
  "${publish_env[@]}" "$python_bin" scripts/appstore_upload.py --check-online
fi

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
if (( push_android || push_website )); then history="release-publish-history"; fi
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
windows_status="未构建"
macos_dmg=""
windows_exe=""
website_status="未执行"
play_status="未执行"
appstore_status="未执行"
failure_reason=""
failed_command=""
summary_printed=0

print_summary() {
  local item elapsed_seconds
  if (( summary_printed )); then return 0; fi
  summary_printed=1
  elapsed_seconds=$((SECONDS - release_started_at))
  echo "elapsedSeconds=$elapsed_seconds" >> "$output/release-info.txt"
  echo
  echo "================= 本次发布汇总 ================="
  echo "版本：$version    提交：$git_hash"
  echo "归档目录：$output"
  printf '总耗时：%02d:%02d:%02d（%s 秒）\n' "$((elapsed_seconds / 3600))" "$((elapsed_seconds / 60 % 60))" "$((elapsed_seconds % 60))" "$elapsed_seconds"
  echo
  echo "构建结果"
  echo "  Android 手机 / Wear OS：$android_status"
  echo "  macOS：$macos_status"
  echo "  Windows：$windows_status"
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
  echo "  App Store Connect：$appstore_status"
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
  for name in android_status macos_status ios_status windows_status; do
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


# 子目录保留原始归档；根目录仅汇集命名统一的最终分发包。
archive_final_package() {
  local source="$1" filename="$2"
  cp "$source" "$output/$filename"
  artifacts+=("$filename")
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
python3 scripts/check_android_page_sizes.py "$phone_apk" "$wear_apk"
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
  python3 scripts/check_android_page_sizes.py "$phone" "$wear"
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
  archive_final_package "$output/macos/AI-Link-$base_name+$code.dmg" "AI-Link-macos-$version.dmg"
  archive_final_package "$output/macos/AI-Link-$base_name+$code.zip" "AI-Link-macos-$version.zip"
  macos_dmg="$output/AI-Link-macos-$version.dmg"
  echo "macosStatus=COMPLETE" >> "$output/release-info.txt"
  macos_status="成功"
fi
if (( build_windows )); then
  windows_status="构建中"
  echo "构建 Windows Release..."
  flutter build windows --release --build-name="$base_name" --build-number="$code"
  windows_bundle="$output/windows"
  mkdir -p "$windows_bundle"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/package_windows.ps1 \
    -Version "$base_name" -BuildNumber "$code" -OutputDir "$windows_bundle"
  cp -R build/windows/x64/runner/Release "$windows_bundle/AI-Link"
  (
    cd "$windows_bundle"
    archive="AI-Link-$base_name+$code-windows.zip"
    if command -v zip >/dev/null; then
      zip -r "$archive" AI-Link
    else
      powershell.exe -NoProfile -Command "Compress-Archive -Path 'AI-Link' -DestinationPath '$archive' -Force"
    fi
  )
  archive_final_package "$output/windows/AI-Link-$base_name+$code-windows.zip" "AI-Link-windows-$version.zip"
  archive_final_package "$output/windows/AI-Link-Setup-$base_name+$code.exe" "AI-Link-windows-$version.exe"
  windows_exe="$output/AI-Link-windows-$version.exe"
  echo "windowsStatus=COMPLETE" >> "$output/release-info.txt"
  windows_status="成功"
fi
if (( build_windows_remote )); then
  windows_status="构建中"
  echo "通过 GitHub Actions 构建 Windows 并下载归档..."
  python3 scripts/windows_remote_release.py --output "$output/windows" \
    --version "$base_name" --build-number "$code"
  archive_final_package "$output/windows/AI-Link-$base_name+$code-windows.zip" "AI-Link-windows-$version.zip"
  archive_final_package "$output/windows/AI-Link-Setup-$base_name+$code.exe" "AI-Link-windows-$version.exe"
  windows_exe="$output/AI-Link-windows-$version.exe"
  echo "windowsStatus=COMPLETE" >> "$output/release-info.txt"
  windows_status="成功"
fi
if (( build_ios )); then
  ios_status="构建中"
  echo "构建 iOS 与配套 Apple Watch 正式签名 IPA/xcarchive..."
  ios_command=(python3 scripts/apple_release.py --platform ios --output "$output/ios" \
    --version "$base_name" --build-number "$code")
  if [[ -n "$ios_export_options" ]]; then ios_command+=(--export-options-plist "$ios_export_options"); fi
  "${ios_command[@]}"
  archive_final_package "$output/ios/AI-Link-$base_name+$code.ipa" "AI-Link-ios-$version.ipa"
  ios_ipa="$output/AI-Link-ios-$version.ipa"
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
  website_command=("$python_bin" scripts/website_release.py
    --phone-apk "$phone_apk" --wear-apk "$wear_apk"
    --version "$name" --version-code "$code" --wear-version-code "$watch_code"
    --manifest-out "$output/website-release.json")
  if (( push_desktop )); then
    if [[ ! -s "$macos_dmg" || ! -s "$windows_exe" ]]; then
      fail "缺少 macOS DMG 或 Windows 安装包，无法同步官网。"
    fi
    echo "上传手机、Wear OS、macOS 与 Windows 安装包到 OSS 并同步 AI Link 官网..."
    website_command+=(--macos-dmg "$macos_dmg" --windows-exe "$windows_exe")
  else
    echo "上传手机与 Wear OS APK 到 OSS 并同步 AI Link 官网..."
  fi
  if ! "${website_command[@]}"; then
    echo "websiteStatus=FAILED" >> "$output/release-info.txt"
    website_status="失败"
    fail "官网下载同步未完成；Google Play 未上传。"
  fi
  echo "websiteStatus=CONFIRMED" >> "$output/release-info.txt"
  website_status="成功"
else
  echo "websiteStatus=NOT_UPLOADED" >> "$output/release-info.txt"
fi

if (( push_android )); then
  echo "上传手机到 ${play_track}，Wear OS 到 ${wear_track} ..."
  upload_log="$output/play-upload.log"
  if ! "${publish_env[@]}" "$python_bin" -u scripts/play_upload.py \
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

if (( push_ios )); then
  echo "上传 iOS IPA 到 App Store Connect ..."
  upload_log="$output/appstore-upload.log"
  if ! "${publish_env[@]}" "$python_bin" -u scripts/appstore_upload.py \
    --ipa "$ios_ipa" --version "$base_name" --build-number "$code" 2>&1 | tee "$upload_log"; then
    echo "appstoreStatus=FAILED" >> "$output/release-info.txt"
    appstore_status="失败"
    fail "App Store Connect 上传未完成，详情见 $upload_log"
  fi
  status_line="$(sed -n 's/^APPSTORE_UPLOAD_STATUS=//p' "$upload_log" | tail -1)"
  if [[ "$status_line" != UPLOADED\|* ]]; then
    echo "appstoreStatus=UNKNOWN" >> "$output/release-info.txt"
    appstore_status="状态未知"
    fail "App Store Connect 未返回确认状态，请到 App Store Connect 核对。"
  fi
  echo "appstoreStatus=$status_line" >> "$output/release-info.txt"
  appstore_status="成功"
  echo "构建已送达 App Store Connect；等待处理完成后，在后台附加到 App 版本再提交审核。"
else
  echo "appstoreStatus=NOT_UPLOADED" >> "$output/release-info.txt"
fi

print_summary
