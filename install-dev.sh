#!/usr/bin/env bash
# Build and install both debug apps without clearing device data.
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

usage() {
  echo "用法：./install-dev.sh [手机序列号 手表序列号]"
  echo "只连接一台手机和一台 Wear OS 手表时，可省略序列号。"
  echo "用 adb devices 查看序列号。"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if [[ $# -ne 0 && $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

for tool in adb flutter; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "缺少命令：$tool" >&2
    exit 1
  fi
done

device_type() {
  local serial="$1" feature
  feature="$(adb -s "$serial" shell pm has-feature android.hardware.type.watch </dev/null | tr -d '\r')"
  case "$feature" in
    true) echo watch ;;
    false) echo phone ;;
    *) echo "无法识别设备类型：$serial ($feature)" >&2; return 1 ;;
  esac
}

phones=()
watches=()
while read -r serial; do
  type="$(device_type "$serial")"
  case "$type" in
    phone) phones+=("$serial") ;;
    watch) watches+=("$serial") ;;
  esac
done < <(adb devices | awk '$2 == "device" {print $1}')

if [[ $# -eq 2 ]]; then
  phone="$1"
  watch="$2"
  if [[ " ${phones[*]} " != *" $phone "* || " ${watches[*]} " != *" $watch "* ]]; then
    echo "指定设备未连接，或手机/手表序列号顺序有误。" >&2
    adb devices
    exit 2
  fi
else
  if [[ ${#phones[@]} -ne 1 || ${#watches[@]} -ne 1 ]]; then
    echo "请连接一台手机和一台 Wear OS 手表，或指定两个序列号。" >&2
    adb devices
    exit 2
  fi
  phone="${phones[0]}"
  watch="${watches[0]}"
fi

echo "手机：${phone}；手表：${watch}"
flutter build apk --debug
(cd android && ./gradlew :wear:assembleDebug)

phone_apk="$repo_root/build/app/outputs/flutter-apk/app-debug.apk"
watch_apk="$repo_root/build/wear/outputs/apk/debug/wear-debug.apk"
[[ -f "$phone_apk" && -f "$watch_apk" ]] || {
  echo "构建完成后未找到手机或手表 APK。" >&2
  exit 1
}

adb -s "$phone" install -r "$phone_apk"
adb -s "$watch" install -r "$watch_apk"
echo "手机和手表调试版安装完成；现有应用数据已保留。"
