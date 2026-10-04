"""上传 AI Link 正式 APK 到 OSS，再同步 HomeTools 独立发布接口。"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENDPOINT = "https://www.tools24.uk/api/v1/ai-link/release"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def settings(env_file=ROOT / "localConfig/.env.local"):
    values = {}
    names = ("RELEASE_ADMIN_TOKEN", "WEBSITE_RELEASE_URL", "OSS_CONFIG_FILE")
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.strip().partition("=")
            if separator and key in names:
                values[key] = value.strip().strip("\"'")
    values.update({key: os.environ[key] for key in names if key in os.environ})
    endpoint = values.get("WEBSITE_RELEASE_URL", DEFAULT_ENDPOINT)
    parts = urlsplit(endpoint)
    local = parts.scheme == "http" and parts.hostname in {"127.0.0.1", "localhost"}
    if ((parts.scheme != "https" and not local) or not parts.hostname
            or parts.username or parts.password or parts.fragment or parts.query
            or parts.path != "/api/v1/ai-link/release"):
        raise ValueError("官网接口须使用 AI Link 的 HTTPS 发布路径（本地允许 HTTP）")
    token = values.get("RELEASE_ADMIN_TOKEN", "")
    if not token or token.startswith("replace-"):
        raise ValueError("请配置 RELEASE_ADMIN_TOKEN，与 HomeTools 的发布密钥一致")
    config_path = Path(values.get("OSS_CONFIG_FILE", ROOT / "localConfig/oss_config.json"))
    if not config_path.is_absolute():
        config_path = ROOT / config_path
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict) or any(not config.get(k) for k in (
            "access_key_id", "access_key_secret", "bucket", "endpoint")):
        raise ValueError("OSS 配置需包含 access_key_id、access_key_secret、bucket、endpoint")
    endpoint_parts = urlsplit(config["endpoint"])
    if (endpoint_parts.scheme != "https" or not endpoint_parts.hostname
            or endpoint_parts.username or endpoint_parts.password):
        raise ValueError("OSS endpoint 必须使用 HTTPS")
    public_url(config, "check.apk")
    return endpoint, token, config


def public_url(config, key):
    cdn = config.get("cdn_domain", "").strip("/")
    host = cdn or f'{config["bucket"]}.{urlsplit(config["endpoint"]).netloc}'
    url = f"https://{host}/{quote(key, safe='/')}"
    parts = urlsplit(url)
    if (not parts.hostname or parts.username or parts.password or parts.query
            or parts.fragment or parts.path != "/" + quote(key, safe='/')
            or any(c.isspace() for c in url)):
        raise ValueError("OSS 公网域名无效；cdn_domain 只填写域名")
    return url


def publish(endpoint, token, payload):
    opener = build_opener(NoRedirect())
    for method in ("PUT", "GET"):
        headers = {"Accept": "application/json", "Cache-Control": "no-cache"}
        data = None
        if method == "PUT":
            headers.update({"X-Admin-Token": token, "Content-Type": "application/json"})
            data = json.dumps(payload).encode("utf-8")
        with opener.open(Request(endpoint, data=data, headers=headers, method=method), timeout=30) as response:
            result = json.loads(response.read(65536))
        if (not isinstance(result, dict) or result.get("ok") is not True
                or not isinstance(result.get("data"), dict)
                or any(result["data"].get(k) != v for k, v in payload.items())):
            raise ValueError(f"官网 {method} 响应与本次发布不一致")


def upload(config, path, bucket):
    key = "ai-link/release/" + path.name
    digest = hashlib.md5(path.read_bytes()).hexdigest()
    result = bucket.put_object_from_file(key, str(path), headers={
        "x-oss-object-acl": "public-read",
        "Cache-Control": "public, max-age=31536000, immutable",
        "Content-Type": "application/vnd.android.package-archive",
    })
    if result.etag.strip('"').lower() != digest:
        raise ValueError("OSS 上传校验不一致，已停止同步官网")
    return public_url(config, key)


def release(endpoint, token, config, phone, wear, version, code, wear_code):
    if (not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.+-]{0,99}", version)
            or not 0 < code < 1000000 or wear_code != code + 1000000):
        raise ValueError("发布版本号无效，手表版本号须为手机版本号加 1,000,000")
    for path in (phone, wear):
        if (not path.is_file() or path.suffix != ".apk" or path.stat().st_size == 0
                or "-test-" in path.name):
            raise ValueError("仅允许上传非空的正式 APK")
    import oss2
    bucket = oss2.Bucket(oss2.Auth(config["access_key_id"], config["access_key_secret"]),
                         config["endpoint"], config["bucket"])
    phone_url = upload(config, phone, bucket)
    wear_url = upload(config, wear, bucket)
    payload = {"version": version, "versionCode": code, "wearVersionCode": wear_code,
               "downloadUrl": phone_url, "wearDownloadUrl": wear_url}
    publish(endpoint, token, payload)
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只检查本地发布配置")
    parser.add_argument("--phone-apk", type=Path)
    parser.add_argument("--wear-apk", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--version-code", type=int)
    parser.add_argument("--wear-version-code", type=int)
    parser.add_argument("--manifest-out", type=Path)
    args = parser.parse_args()
    if not args.check and any(getattr(args, name) is None for name in (
            "phone_apk", "wear_apk", "version", "version_code", "wear_version_code", "manifest_out")):
        parser.error("发布需要手机/手表 APK、版本名称、两端版本号与 manifest-out")
    try:
        endpoint, token, config = settings()
        if args.check:
            print("AI Link 官网与 OSS 本地发布配置检查通过")
            return
        payload = release(endpoint, token, config, args.phone_apk, args.wear_apk,
                          args.version, args.version_code, args.wear_version_code)
        args.manifest_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    except HTTPError as exc:
        raise SystemExit(f"官网同步失败：HTTP {exc.code}；请核对接口部署、发布密钥和存储配置") from None
    except (URLError, OSError, ValueError):
        raise SystemExit("官网发布失败；请核对本地配置、APK、网络与 OSS 上传校验") from None
    except Exception:
        # OSS SDK 的原始错误可能包含签名请求，不能直接打印。
        raise SystemExit("OSS 上传失败；请检查网络、凭据与存储权限") from None
    print("AI Link 手机与 Wear OS 下载信息已写入官网并回读确认")


if __name__ == "__main__":
    main()
