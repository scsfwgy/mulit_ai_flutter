#!/usr/bin/env python3
"""Build and install AI Link on selected Android/iOS phones and watches."""

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PHONE_ID = "com.maxhall.ailink.debug"
WATCH_ID = PHONE_ID + ".watchkitapp"


@dataclass(frozen=True)
class Device:
    platform: str
    kind: str
    identifier: str
    name: str

    @property
    def label(self):
        return {
            ("android", "phone"): "Android 手机",
            ("android", "watch"): "Wear OS 手表",
            ("ios", "phone"): "iPhone/iPad",
            ("ios", "watch"): "Apple Watch",
        }[self.platform, self.kind]


def run(command, *, capture=False, env=None):
    return subprocess.run(
        [str(part) for part in command], cwd=ROOT, check=True,
        text=True, stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        stdin=subprocess.DEVNULL, env=env,
    ).stdout


def android_devices():
    devices = []
    for line in run(["adb", "devices"], capture=True).splitlines()[1:]:
        fields = line.split()
        if len(fields) < 2:
            continue
        serial, state = fields[:2]
        if state != "device":
            print(f"跳过 Android 设备 {serial}：{state}（检查连接/USB 调试授权）。", file=sys.stderr)
            continue
        try:
            try:
                feature = run([
                    "adb", "-s", serial, "shell", "pm", "has-feature",
                    "android.hardware.type.watch",
                ], capture=True).strip()
            except subprocess.CalledProcessError as error:
                # Android pm exits with 1 when the feature is absent on a phone.
                if error.returncode != 1 or (error.stdout or "").strip() != "false":
                    raise
                feature = "false"
            if feature not in ("true", "false"):
                raise ValueError("无法识别手机/手表类型")
            name = run(["adb", "-s", serial, "shell", "getprop", "ro.product.model"], capture=True).strip()
            devices.append(Device("android", "watch" if feature == "true" else "phone", serial, name))
        except (subprocess.CalledProcessError, ValueError) as error:
            print(f"跳过 Android 设备 {serial}：{error}", file=sys.stderr)
    return devices


def parse_apple_devices(document):
    """Read both current Device Hub fields and older CoreDevice JSON fields."""
    devices = []
    for item in document["result"]["devices"]:
        props = item.get("properties") or {}
        hardware = props.get("hardware") or item.get("hardwareProperties") or {}
        connection = props.get("connection") or item.get("connectionProperties") or {}
        state = props.get("state") or item.get("deviceProperties") or {}
        if hardware.get("reality") != "physical":
            continue
        if connection.get("state", connection.get("tunnelState")) != "connected":
            continue
        platform = hardware.get("platform")
        if platform not in ("iOS", "watchOS"):
            continue
        identifier = hardware.get("udid") or item["identifier"]
        name = state.get("name") or hardware.get("marketingName") or identifier
        devices.append(Device("ios", "watch" if platform == "watchOS" else "phone", identifier, name))
    return devices


def discover(platform, kind):
    devices = []
    if platform in ("all", "android"):
        if shutil.which("adb"):
            devices.extend(android_devices())
        elif platform == "android":
            raise ValueError("缺少 adb，请先安装 Android SDK Platform Tools。")
        else:
            print("未找到 adb，跳过 Android 设备。", file=sys.stderr)
    if platform in ("all", "ios"):
        if shutil.which("xcrun"):
            try:
                with tempfile.TemporaryDirectory(prefix="ai-link-devices-") as temp:
                    path = Path(temp) / "devices.json"
                    run(["xcrun", "devicectl", "list", "devices", "--json-output", path], capture=True)
                    devices.extend(parse_apple_devices(json.loads(path.read_text())))
            except (subprocess.CalledProcessError, KeyError, ValueError) as error:
                if platform == "ios":
                    raise ValueError("读取 Apple 设备失败，请检查完整 Xcode、devicectl 和 Device Hub 配对。") from error
                print("无法读取 Apple 设备，跳过；请检查 Xcode 和 Device Hub。", file=sys.stderr)
        elif platform == "ios":
            raise ValueError("缺少 xcrun；Apple 设备安装需要 Mac 和完整 Xcode。")
    return sorted(
        (device for device in devices if kind == "all" or device.kind == kind),
        key=lambda device: (device.platform, device.kind, device.identifier),
    )


def select_indices(text, devices):
    if text.strip().lower() == "all":
        return devices
    parts = re.split(r"[\s,，]+", text.strip())
    if not parts or any(not part.isascii() or not part.isdigit() for part in parts):
        raise ValueError("请输入设备序号，例如 1 或 1,3；全部设备请输入 all。")
    selected = []
    for part in parts:
        number = int(part)
        if not 1 <= number <= len(devices):
            raise ValueError(f"设备序号超出范围：{number}")
        device = devices[number - 1]
        if device not in selected:
            selected.append(device)
    return selected


def select_devices(args, devices):
    if args.legacy_serials:
        if len(args.legacy_serials) != 2 or args.device or args.select or args.all:
            raise ValueError("旧用法需提供两个 Android 序列号，且不能与其他设备选择参数混用。")
        selected = []
        for serial, kind in zip(args.legacy_serials, ("phone", "watch")):
            device = next((d for d in devices if d.identifier == serial and d.platform == "android" and d.kind == kind), None)
            if device is None:
                raise ValueError(f"指定 Android {kind} 未连接，或两个序列号的顺序有误：{serial}")
            selected.append(device)
        return selected
    if args.device:
        selected = []
        for identifier in args.device:
            device = next((d for d in devices if d.identifier == identifier), None)
            if device is None:
                raise ValueError(f"设备未连接或不在筛选范围：{identifier}")
            if device not in selected:
                selected.append(device)
        return selected
    if args.all:
        return devices
    if args.select:
        return select_indices(args.select, devices)
    if len(devices) == 1:
        return devices
    while True:
        try:
            answer = input("选择要安装的序号（多个用逗号/空格分隔，all 全选，q 退出）：")
            if answer.strip().lower() == "q":
                raise SystemExit(0)
            return select_indices(answer, devices)
        except ValueError as error:
            print(error, file=sys.stderr)
        except EOFError:
            raise ValueError("未收到设备选择；非交互运行请使用 --select、--device 或 --all。") from None


def development_team(explicit):
    team = explicit or os.environ.get("IOS_DEVELOPMENT_TEAM")
    if not team:
        project = json.loads(run([
            "plutil", "-convert", "json", "-o", "-", ROOT / "ios/Runner.xcodeproj/project.pbxproj",
        ], capture=True))["objects"]
        teams = set()
        for target in project.values():
            if target.get("isa") != "PBXNativeTarget" or target.get("name") not in ("Runner", "AILinkWatch"):
                continue
            configs = project[target["buildConfigurationList"]]["buildConfigurations"]
            for config_id in configs:
                config = project[config_id]
                if config["name"] == "Debug":
                    value = config["buildSettings"].get("DEVELOPMENT_TEAM")
                    if value:
                        teams.add(value)
        if len(teams) > 1:
            raise ValueError("手机与手表签名团队不同，请用 --team 指定同一个 Apple Team ID。")
        team = next(iter(teams), None)
    if not team or not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("请先在 Xcode 配置开发团队，或传 --team <10位TeamID> / IOS_DEVELOPMENT_TEAM。")
    return team


def build(selected, ios_mode, team):
    artifacts = {}
    kinds = {(device.platform, device.kind) for device in selected}
    if ("android", "phone") in kinds:
        run(["flutter", "build", "apk", "--debug"])
        artifacts["android", "phone"] = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
    if ("android", "watch") in kinds:
        run([ROOT / "android/gradlew", "-p", ROOT / "android", ":wear:assembleDebug"])
        artifacts["android", "watch"] = ROOT / "build/wear/outputs/apk/debug/wear-debug.apk"
    if any(platform == "ios" for platform, _ in kinds):
        # Runner prepares Flutter dependencies and embeds the signed watch app.
        # A temporary signing override avoids rewriting the user's Xcode project.
        with tempfile.TemporaryDirectory(prefix="ai-link-signing-") as temp:
            config = Path(temp) / "Signing.xcconfig"
            contents = ""
            inherited = os.environ.get("XCODE_XCCONFIG_FILE")
            if inherited:
                inherited = str(Path(inherited).resolve())
                if '"' in inherited or '\n' in inherited:
                    raise ValueError("XCODE_XCCONFIG_FILE 路径包含不支持的字符。")
                contents = f'#include "{inherited}"\n'
            config.write_text(contents + f"DEVELOPMENT_TEAM = {team}\nCODE_SIGN_STYLE = Automatic\n")
            run(["flutter", "build", "ios", f"--{ios_mode}"], env={
                **os.environ, "XCODE_XCCONFIG_FILE": str(config),
            })
        phone = ROOT / "build/ios/iphoneos/Runner.app"
        watch = phone / "Watch/AILinkWatch.app"
        for path, expected in ((phone, PHONE_ID), (watch, WATCH_ID)):
            with (path / "Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            if info.get("CFBundleIdentifier") != expected:
                raise ValueError(f"安装包标识不是开发版 {expected}，已停止安装：{path}")
            if path == watch and info.get("WKCompanionAppBundleIdentifier") != PHONE_ID:
                raise ValueError("Apple Watch 配套手机标识不匹配，已停止安装。")
        run(["codesign", "--verify", "--deep", "--strict", phone])
        artifacts["ios", "phone"] = phone
        artifacts["ios", "watch"] = watch
    for path in artifacts.values():
        if not path.exists():
            raise ValueError(f"构建后未找到安装包：{path}")
    return artifacts


def main():
    parser = argparse.ArgumentParser(prog="./install-dev.sh", description="构建并覆盖安装 AI Link 开发版；保留现有应用数据。")
    parser.add_argument("--platform", choices=("all", "android", "ios"), default="all", help="筛选平台，默认 all")
    parser.add_argument("--target", choices=("all", "phone", "watch"), default="all", help="筛选手机/手表，默认 all")
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument("--select", metavar="序号", help="设备序号，例如 1,3（与 --list 显示顺序一致）")
    choice.add_argument("--device", action="append", metavar="设备ID", help="指定序列号/UDID，可重复传入")
    choice.add_argument("--all", action="store_true", help="安装到筛选后的全部设备")
    parser.add_argument("--list", action="store_true", help="只列设备，不构建或安装")
    parser.add_argument("--ios-mode", choices=("profile", "debug"), default="profile", help="默认 profile，可从桌面启动；debug 用于断点/热重载")
    parser.add_argument("--team", metavar="AppleTeamID", help="Apple 签名团队；默认读取 Xcode Debug 配置")
    parser.add_argument("legacy_serials", nargs="*", metavar="Android序列号", help="兼容旧用法：手机序列号 手表序列号")
    args = parser.parse_args()
    devices = discover(args.platform, args.target)
    for index, device in enumerate(devices, 1):
        name = " ".join(device.name.split())
        print(f"{index:2}. {device.label:14} {name} [{device.identifier}]", flush=True)
    if not devices:
        raise ValueError("没有可安装的设备。Android 请检查 adb devices；Apple 请在 Device Hub 连接并开启开发者模式（不列出模拟器）。")
    if args.list:
        return
    selected = select_devices(args, devices)
    if not shutil.which("flutter"):
        raise ValueError("缺少 flutter，请将 Flutter SDK 加入 PATH。")
    team = development_team(args.team) if any(d.platform == "ios" for d in selected) else None
    print("\n本次安装：" + "；".join(f"{d.label} {d.name}" for d in selected), flush=True)
    if team:
        print(f"Apple 构建模式：{args.ios_mode}；签名团队：{team}", flush=True)
    artifacts = build(selected, args.ios_mode, team)
    # Build all required artifacts before updating the first selected device.
    installed = []
    for device in sorted(selected, key=lambda d: d.kind == "watch"):
        path = artifacts[device.platform, device.kind]
        print(f"\n安装到 {device.label}：{device.name} [{device.identifier}]", flush=True)
        try:
            if device.platform == "android":
                run(["adb", "-s", device.identifier, "install", "-r", path])
            else:
                run(["xcrun", "devicectl", "device", "install", "app", "--device", device.identifier, path])
        except subprocess.CalledProcessError:
            print(f"安装失败的设备：{device.label} {device.name} [{device.identifier}]", file=sys.stderr)
            if installed:
                print("此前已安装成功：" + "；".join(installed), file=sys.stderr)
            if device.platform == "ios":
                print("请保持设备解锁，检查 Device Hub 连接、开发者模式和开发者证书信任。", file=sys.stderr)
            print(f"恢复连接后可单独重试：./install-dev.sh --device {device.identifier} --ios-mode {args.ios_mode}", file=sys.stderr)
            raise
        installed.append(device.name)
        print(f"安装完成：{device.name}", flush=True)
    print("\n所选设备已全部覆盖安装；未卸载或清空应用数据。")
    if any(d.platform == "ios" and d.kind == "phone" for d in selected) and args.ios_mode == "debug":
        print("iPhone Debug 版需通过 flutter run / Xcode 启动；桌面启动请使用默认 Profile 模式重新安装。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n已取消。", file=sys.stderr)
        sys.exit(130)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"安装未完成：{error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        sys.exit(1)
