#!/usr/bin/env python3
"""把已签名的 iOS IPA 上传到 App Store Connect（TestFlight 与 App Store 共用同一个构建）。

职责边界（刻意只做上传）：

- 构建、版本核对与本地归档由 `release.sh` 调用 `scripts/apple_release.py` 完成，本脚本不重复构建；
- 上传成功后构建出现在 App Store Connect → TestFlight，需要人工附加到某个 App 版本再提交审核；
  自动提审属于另一条链路（App Store Connect API 的 `appStoreVersionSubmissions`），当前不实现，
  避免在付费协议、内购或商店元数据尚未就绪时误提交审核。

一般通过 `./release.sh --push-ios` 间接调用；也可单独使用：

    # 只检查本地配置、私钥与 altool，不联网
    python3 scripts/appstore_upload.py --check
    # 检查本地配置，并向 Apple 校验凭据与 App 记录（联网；release.sh 预检使用）
    python3 scripts/appstore_upload.py --check-online
    # 上传指定 IPA
    python3 scripts/appstore_upload.py --ipa <路径.ipa> --version 1.0.5 --build-number 53

凭据来自 `localConfig/appstore-connect.env`（模板 `scripts/appstore_connect.env.example`），
同名环境变量优先。生成方式：App Store Connect → 用户和访问 → 集成 → App Store Connect API
→ 团队密钥 → 生成密钥（角色至少 App Manager），Issuer ID 显示在同一页面顶部。
私钥 `AuthKey_<KEY_ID>.p8` 只能下载一次，放到 `localConfig/` 下即可；该目录已被 .gitignore 忽略。
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_FILE = ROOT / "localConfig" / "appstore-connect.env"
EXAMPLE_FILE = "scripts/appstore_connect.env.example"
BUNDLE_ID = "com.maxhall.ailink"
WATCH_BUNDLE_ID = "com.maxhall.ailink.watchkitapp"
SETTING_NAMES = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH")
KEY_ID_PATTERN = re.compile(r"[0-9A-Z]{10}")
ISSUER_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")
NUMBER_PATTERN = re.compile(r"[1-9]\d*")
# altool 在成功上传时会打印 RequestUUID 或 Delivery ID，用于在 App Store Connect 中定位构建。
DELIVERY_PATTERN = re.compile(
    r"(?:RequestUUID|Delivery ID)\s*[:=]\s*([0-9a-fA-F][0-9a-fA-F-]{7,})"
)
JWT_PATTERN = re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    print(f"APPSTORE_UPLOAD_STATUS=FAIL|{message}", file=sys.stderr)
    return 1


def settings(env_file: Path = CONFIG_FILE) -> tuple[str, str, Path]:
    """读取 App Store Connect 凭据；文件与环境变量同名时环境变量优先。"""
    values: dict[str, str] = {}
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.strip().partition("=")
            if separator and key in SETTING_NAMES:
                values[key] = value.strip().strip("\"'")
    values.update({name: os.environ[name] for name in SETTING_NAMES if name in os.environ})
    key_id = values.get("ASC_KEY_ID", "")
    issuer = values.get("ASC_ISSUER_ID", "")
    if not KEY_ID_PATTERN.fullmatch(key_id):
        raise ValueError(
            "ASC_KEY_ID 未配置或格式无效（应为 10 位大写字母数字）；"
            f"请复制 {EXAMPLE_FILE} 到 {env_file.relative_to(ROOT)}"
        )
    if not ISSUER_PATTERN.fullmatch(issuer):
        raise ValueError("ASC_ISSUER_ID 未配置或格式无效（应为 8-4-4-4-12 形式的 Issuer ID）")
    key_path = Path(values.get("ASC_KEY_PATH") or f"localConfig/AuthKey_{key_id}.p8")
    if not key_path.is_absolute():
        key_path = ROOT / key_path
    if not key_path.is_file():
        raise ValueError(f"API 私钥不存在：{key_path}；.p8 只能在生成密钥时下载一次")
    if "PRIVATE KEY" not in key_path.read_text(encoding="utf-8", errors="replace"):
        raise ValueError(f"API 私钥格式无效：{key_path}")
    return key_id, issuer, key_path


def find_altool() -> Path:
    found = shutil.which("altool")
    if not found:
        result = subprocess.run(
            ["xcrun", "--find", "altool"], capture_output=True, text=True, check=False
        )
        found = result.stdout.strip() if result.returncode == 0 else ""
    if not found or not Path(found).is_file():
        raise ValueError("未找到 altool；请安装完整 Xcode 并用 xcode-select 指向它")
    return Path(found)


def auth_args(key_id: str, issuer: str, key_path: Path) -> list[str]:
    return ["--api-key", key_id, "--api-issuer", issuer, "--p8-file-path", str(key_path)]


def run_altool(altool: Path, arguments: list[str], echo: bool = True) -> tuple[int, str]:
    """执行 altool 并实时转发输出，同时保留全文供判定使用。"""
    process = subprocess.Popen(
        [str(altool), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        bufsize=1,
    )
    lines: list[str] = []
    assert process.stdout is not None
    for line in process.stdout:
        lines.append(line)
        if echo:
            sys.stdout.write(line)
            sys.stdout.flush()
    return process.wait(), "".join(lines)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check_app_access(token: str) -> None:
    """用正式 API 校验账号与 App，避免把 altool 的遥测错误当作认证结果。"""
    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": "1"})
    request = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v1/apps?{query}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    opener = urllib.request.build_opener(_NoRedirect())
    try:
        with opener.open(request, timeout=30) as response:
            result = json.loads(response.read(1024 * 1024))
    except urllib.error.HTTPError as error:
        try:
            payload = json.loads(error.read(65536))
            codes = {item.get("code") for item in payload.get("errors", []) if isinstance(item, dict)}
        except (ValueError, TypeError, AttributeError):
            codes = set()
        if "FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED" in codes:
            raise ValueError(
                "Apple 账号有尚未接受或已过期的协议；请由账号持有人（Account Holder）"
                "登录 https://developer.apple.com/account/ 和 https://appstoreconnect.apple.com/ "
                "检查并接受最新协议，然后重试。这不是 API Key 格式错误。"
            ) from None
        if error.code == 401:
            raise ValueError("App Store Connect 认证失败（HTTP 401）；请核对 Key ID、Issuer ID 与 .p8 是否配对及密钥是否已撤销") from None
        if error.code == 403:
            raise ValueError("App Store Connect 权限不足（HTTP 403）；请核对 API 密钥角色及该 App 的访问权限") from None
        raise ValueError(f"App Store Connect 预检失败（HTTP {error.code}）；请稍后重试或检查网络") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ValueError("无法连接 App Store Connect API；请检查网络与 HTTP 代理后重试") from None
    except (ValueError, UnicodeError):
        raise ValueError("App Store Connect API 返回格式无效，请稍后重试") from None
    apps = result.get("data") if isinstance(result, dict) else None
    if not isinstance(apps, list):
        raise ValueError("App Store Connect API 未返回有效的 App 列表，请稍后重试")
    if not any(isinstance(app, dict) and isinstance(app.get("attributes"), dict)
               and app["attributes"].get("bundleId") == BUNDLE_ID for app in apps):
        raise ValueError(f"App Store Connect 中未找到可访问的 {BUNDLE_ID}；请确认 App 记录已创建且密钥有访问权限")


def check_ipa(ipa: Path, version: str, number: str) -> None:
    """确认待上传的 IPA 就是本次构建：标识、版本号与内嵌手表应用都必须一致。"""
    if not ipa.is_file() or ipa.suffix.lower() != ".ipa" or ipa.stat().st_size == 0:
        raise ValueError(f"IPA 不存在或不是有效的 .ipa 文件：{ipa}")
    with zipfile.ZipFile(ipa) as package:
        names = package.namelist()
        apps = sorted(
            {name.split("/")[1] for name in names
             if name.startswith("Payload/") and name.split("/")[1].endswith(".app")}
        )
        if len(apps) != 1:
            raise ValueError("IPA 缺少唯一的手机应用")
        for path, identifier, label in (
            (f"Payload/{apps[0]}/Info.plist", BUNDLE_ID, "手机"),
            (f"Payload/{apps[0]}/Watch/AILinkWatch.app/Info.plist", WATCH_BUNDLE_ID, "手表"),
        ):
            if path not in names:
                raise ValueError(f"IPA 缺少{label}应用的 Info.plist：{path}")
            with package.open(path) as stream:
                info = plistlib.load(stream)
            for key, expected in (("CFBundleIdentifier", identifier),
                                  ("CFBundleShortVersionString", version),
                                  ("CFBundleVersion", number)):
                if str(info.get(key)) != expected:
                    raise ValueError(
                        f"IPA 中{label}应用的 {key} 不匹配：要求 {expected}，实际 {info.get(key)}"
                    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--check", action="store_true", help="只检查本地配置、私钥与 altool，不联网")
    parser.add_argument(
        "--check-online",
        action="store_true",
        help="检查本地配置，并向 Apple 校验凭据与 App 记录（联网）",
    )
    parser.add_argument("--ipa", type=Path, help="待上传的 .ipa 路径")
    parser.add_argument("--version", help="CFBundleShortVersionString，例如 1.0.5")
    parser.add_argument("--build-number", help="CFBundleVersion，例如 53")
    args = parser.parse_args(argv)

    if not (args.check or args.check_online) and any(
        value is None for value in (args.ipa, args.version, args.build_number)
    ):
        parser.error("上传需要同时指定 --ipa、--version 与 --build-number")

    try:
        key_id, issuer, key_path = settings()
        altool = find_altool()
        credentials = auth_args(key_id, issuer, key_path)

        if args.check or args.check_online:
            # --generate-jwt 只读取私钥，不联网；输出里含短期 JWT，不转发到日志。
            code, output = run_altool(altool, ["--generate-jwt", *credentials], echo=False)
            if code != 0 or "ERROR: [" in output:
                return fail("App Store Connect 私钥无法生成 JWT；请核对 ASC_KEY_ID 与 .p8 是否配对")
            if not args.check_online:
                print("App Store Connect 本地发布配置检查通过（未联网）")
                return 0
            tokens = set(JWT_PATTERN.findall(output))
            if len(tokens) != 1:
                return fail("无法从 altool 获取唯一的 JWT；请检查 Xcode 版本，认证输出已隐藏")
            check_app_access(tokens.pop())
            print(f"App Store Connect 凭据与 App 访问校验通过；{BUNDLE_ID} 已在账号中")
            return 0

        ipa = args.ipa.resolve()
        if not VERSION_PATTERN.fullmatch(args.version) or not NUMBER_PATTERN.fullmatch(
            args.build_number
        ):
            return fail("版本号必须为 x.y.z，构建号必须为正整数")
        check_ipa(ipa, args.version, args.build_number)
        print(f"上传 IPA 到 App Store Connect：{ipa}")
        code, output = run_altool(
            altool, ["--upload-app", "-f", str(ipa), "-t", "ios", *credentials]
        )
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        return fail(str(error))

    if code != 0:
        return fail("App Store Connect 上传失败；请核对上方 altool 输出")
    if "ERROR: [" in output:
        print("altool 退出码为 0，但输出包含错误行；请在 App Store Connect 核对构建是否已送达。")
        print(
            f"APPSTORE_UPLOAD_STATUS=UNKNOWN|{BUNDLE_ID}|{args.version}|{args.build_number}"
        )
        return 0
    delivery = DELIVERY_PATTERN.search(output)
    suffix = f"|{delivery.group(1)}" if delivery else ""
    print("altool 已确认上传；构建需等待 App Store Connect 处理完成后再附加到版本并提交审核。")
    print(f"APPSTORE_UPLOAD_STATUS=UPLOADED|{BUNDLE_ID}|{args.version}|{args.build_number}{suffix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
