#!/usr/bin/env python3
"""Build and locally archive macOS or signed iOS/watchOS Release artifacts."""

import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, **kwargs):
    subprocess.run([str(value) for value in command], cwd=ROOT, check=True, **kwargs)


def check_app(app, identifier, version, number):
    plist = app / ("Contents/Info.plist" if identifier.endswith(".macos") else "Info.plist")
    with plist.open("rb") as stream:
        info = plistlib.load(stream)
    for key, expected in (("CFBundleIdentifier", identifier),
                          ("CFBundleShortVersionString", version), ("CFBundleVersion", number)):
        if str(info.get(key)) != expected:
            raise ValueError(f"{app.name} 的 {key} 不匹配：要求 {expected}")
    run(["codesign", "--verify", "--deep", "--strict", app])
    return info


def check_ios_app(app, version, number):
    check_app(app, "com.maxhall.ailink", version, number)
    watch = app / "Watch/AILinkWatch.app"
    info = check_app(watch, "com.maxhall.ailink.watchkitapp", version, number)
    if info.get("WKCompanionAppBundleIdentifier") != "com.maxhall.ailink":
        raise ValueError("Apple Watch 配套手机标识不匹配。")


def build_ios(output, version, number, export_options=None):
    # Flutter can report success after an IPA export failure. Remove old exports
    # so only the current successful export can satisfy the artifact checks.
    ipa_directory = ROOT / "build/ios/ipa"
    if ipa_directory.exists():
        shutil.rmtree(ipa_directory)
    command = ["flutter", "build", "ipa", "--release", "--no-pub",
               f"--build-name={version}", f"--build-number={number}",
               "--obfuscate", f"--split-debug-info={output / 'dart-symbols'}"]
    if export_options:
        with export_options.open("rb") as stream:
            options = plistlib.load(stream)
        if options.get("destination", "export") != "export":
            raise ValueError("iOS 导出配置必须为 destination=export；发布脚本只做本地归档。")
        if options.get("method") not in ("app-store", "app-store-connect"):
            raise ValueError("正式 IPA 必须使用 app-store-connect 导出方式。")
        command.append(f"--export-options-plist={export_options}")
    else:
        command.append("--export-method=app-store")
    with tempfile.TemporaryDirectory(prefix="ai-link-release-version-") as temp:
        config = Path(temp) / "Version.xcconfig"
        contents = ""
        inherited = os.environ.get("XCODE_XCCONFIG_FILE")
        if inherited:
            inherited = str(Path(inherited).resolve())
            if any(char in inherited for char in ('"', '\n', '\r')):
                raise ValueError("XCODE_XCCONFIG_FILE 路径包含不支持的字符。")
            contents = f'#include "{inherited}"\n'
        # Apply the same version to Runner and the embedded watch target without
        # changing the project or re-enabling the disabled Widgets extension.
        config.write_text(contents + f"MARKETING_VERSION = {version}\nCURRENT_PROJECT_VERSION = {number}\n")
        run(command, env={**os.environ, "XCODE_XCCONFIG_FILE": str(config)})
    ipas = list(ipa_directory.glob("*.ipa"))
    if len(ipas) != 1:
        raise ValueError("未生成正式签名 IPA。请配置 iOS/Apple Watch Release 团队、分发证书和描述文件；仅有 xcarchive 不算正式导出成功。")
    archive = ROOT / "build/ios/archive/Runner.xcarchive"
    check_ios_app(archive / "Products/Applications/Runner.app", version, number)
    with tempfile.TemporaryDirectory(prefix="ai-link-ipa-check-") as temp:
        with zipfile.ZipFile(ipas[0]) as ipa:
            ipa.extractall(temp)
        apps = list((Path(temp) / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("IPA 缺少唯一的手机应用。")
        check_ios_app(apps[0], version, number)
    run(["ditto", archive, output / "AI Link.xcarchive"])
    target = output / f"AI-Link-{version}+{number}.ipa"
    shutil.copy2(ipas[0], target)
    return [target]


def build_macos(output, version, number):
    run(["flutter", "build", "macos", "--release", "--no-pub",
         f"--build-name={version}", f"--build-number={number}"])
    app = ROOT / "build/macos/Build/Products/Release/AI Link.app"
    check_app(app, "com.maxhall.ailink.macos", version, number)
    dmg = output / f"AI-Link-{version}+{number}.dmg"
    archive = output / f"AI-Link-{version}+{number}.zip"
    with tempfile.TemporaryDirectory(prefix="ai-link-macos-release-") as temp:
        staged = Path(temp) / "AI Link.app"
        run(["ditto", app, staged])
        (Path(temp) / "Applications").symlink_to("/Applications")
        run(["hdiutil", "create", "-quiet", "-volname", "AI Link", "-srcfolder", temp,
             "-format", "UDZO", dmg])
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", staged, archive])
        run(["ditto", staged, output / "AI Link.app"])
    return [dmg, archive]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("ios", "macos"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--export-options-plist", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise ValueError("Apple 正式包需要 Mac 和完整 Xcode。")
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or not re.fullmatch(r"[1-9]\d*", args.build_number):
        raise ValueError("Apple 版本必须为 x.y.z，构建号必须为正整数。")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    artifacts = (build_ios(output, args.version, args.build_number,
                           args.export_options_plist.resolve() if args.export_options_plist else None)
                 if args.platform == "ios" else build_macos(output, args.version, args.build_number))
    with (output / "SHA256SUMS.txt").open("w") as stream:
        for artifact in artifacts:
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            stream.write(f"{digest}  {artifact.name}\n")
    print(f"Apple 本地产物：{output}")
    if args.platform == "macos":
        print("macOS Release 已归档；Developer ID 公证与商店上传需另外执行。")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Apple 正式包构建失败：{error}", file=sys.stderr)
        sys.exit(1)
