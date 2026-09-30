#!/usr/bin/env python3
"""Upload the phone and Wear OS bundles in one Google Play edit."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


PACKAGE_NAME = "com.maxhall.ailink"
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
CHUNK_SIZE = 10 * 1024 * 1024


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    print(f"PLAY_UPLOAD_STATUS=FAIL|{message}", file=sys.stderr)
    return 1


def release_notes(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("版本更新日志必须是语言代码到文本的 JSON 对象")
    notes = []
    for language, value in data.items():
        if not isinstance(language, str) or not isinstance(value, str):
            raise ValueError("版本更新日志的语言代码和内容必须是字符串")
        if value.strip():
            notes.append({"language": language, "text": value.strip()})
    return notes


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_tracks(service, edit_id: str, track: str) -> bool:
    available_tracks = {
        item["track"]
        for item in service.edits()
        .tracks()
        .list(packageName=PACKAGE_NAME, editId=edit_id)
        .execute(num_retries=3)
        .get("tracks", [])
    }
    wear_track = f"wear:{track}"
    if track not in available_tracks:
        raise RuntimeError(f"Play Console 尚未提供手机 {track} 轨道。")
    if wear_track in available_tracks:
        return False
    if track == "alpha":
        service.edits().tracks().create(
            packageName=PACKAGE_NAME,
            editId=edit_id,
            body={"track": wear_track, "type": "CLOSED_TESTING", "formFactor": "WEAR"},
        ).execute(num_retries=3)
        return True
    raise RuntimeError(
        f"Play Console 尚未提供 Wear OS {wear_track} 轨道。"
        "请先在‘测试和发布 → 高级设置 → 设备类型’中添加 Wear OS，"
        "并建立对应测试轨道。"
    )


def upload_to_edit(
    service,
    phone: Path,
    wear: Path,
    phone_code: int,
    wear_code: int,
    track: str,
    notes: list[dict[str, str]],
    media_file_upload,
) -> tuple[str, dict[str, int]]:
    """Commit both form factors together; discard the edit on any failure."""
    edit_id = service.edits().insert(body={}, packageName=PACKAGE_NAME).execute(
        num_retries=3
    )["id"]
    codes: dict[str, int] = {}
    try:
        if require_tracks(service, edit_id, track):
            print(f"已在本次编辑会话创建 Wear OS {track} 封闭测试轨道", flush=True)

        for label, path, expected in (
            ("phone", phone, phone_code),
            ("wear", wear, wear_code),
        ):
            bundle = service.edits().bundles().upload(
                packageName=PACKAGE_NAME,
                editId=edit_id,
                media_body=media_file_upload(
                    str(path),
                    mimetype="application/octet-stream",
                    resumable=True,
                    chunksize=CHUNK_SIZE,
                ),
            ).execute(num_retries=3)
            actual = int(bundle["versionCode"])
            if actual != expected:
                raise ValueError(
                    f"{label} AAB versionCode 不符：期望 {expected}，Play 返回 {actual}"
                )
            remote_hash = bundle.get("sha256", "")
            if remote_hash and remote_hash.lower() != sha256(path):
                raise ValueError(f"{label} AAB 上传后的 SHA-256 与本地文件不一致")
            codes[label] = actual
            print(f"已上传 {label} AAB：versionCode={actual}", flush=True)

        for destination, code in ((track, phone_code), (f"wear:{track}", wear_code)):
            release = {"status": "completed", "versionCodes": [str(code)]}
            if notes:
                release["releaseNotes"] = notes
            service.edits().tracks().update(
                packageName=PACKAGE_NAME,
                editId=edit_id,
                track=destination,
                body={"track": destination, "releases": [release]},
            ).execute(num_retries=3)
            print(f"已分配轨道 {destination}：versionCode={code}", flush=True)

        service.edits().validate(packageName=PACKAGE_NAME, editId=edit_id).execute(
            num_retries=3
        )
        service.edits().commit(packageName=PACKAGE_NAME, editId=edit_id).execute(
            num_retries=3
        )
        return edit_id, codes
    except Exception:
        try:
            service.edits().delete(packageName=PACKAGE_NAME, editId=edit_id).execute(
                num_retries=1
            )
        except Exception:
            pass
        raise


def service_from_key(json_key: Path, timeout: int):
    try:
        import httplib2
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
        from google_auth_httplib2 import AuthorizedHttp
    except ImportError as exc:
        raise RuntimeError(
            "缺少 Google Play API 依赖，请安装 scripts/requirements.txt"
        ) from exc

    credentials = service_account.Credentials.from_service_account_file(
        str(json_key), scopes=SCOPES
    )
    http = httplib2.Http(timeout=timeout)
    # HTTP 308 is the resumable-upload continuation response, not a redirect.
    http.redirect_codes = http.redirect_codes - {308}
    return build(
        "androidpublisher",
        "v3",
        http=AuthorizedHttp(credentials, http=http),
        cache_discovery=False,
    )


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--json-key",
        type=Path,
        default=Path(
            os.environ.get(
                "PLAY_SERVICE_ACCOUNT_JSON",
                root / "localConfig" / "google-play-service-account.json",
            )
        ),
    )
    parser.add_argument("--phone-aab", type=Path)
    parser.add_argument("--wear-aab", type=Path)
    parser.add_argument("--phone-version-code", type=int)
    parser.add_argument("--wear-version-code", type=int)
    parser.add_argument(
        "--track", default="internal", choices=("internal", "alpha", "beta", "production")
    )
    parser.add_argument(
        "--release-notes",
        type=Path,
        default=root / "doc" / "google_play" / "release_notes.json",
    )
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--check-tracks", action="store_true")
    args = parser.parse_args(argv)

    if not args.json_key.is_file():
        return fail(f"服务账号密钥不存在：{args.json_key}")
    if args.timeout <= 0:
        return fail("--timeout 必须大于 0")
    if args.check_tracks:
        try:
            service = service_from_key(args.json_key, args.timeout)
            edit_id = service.edits().insert(body={}, packageName=PACKAGE_NAME).execute(
                num_retries=3
            )["id"]
            try:
                created = require_tracks(service, edit_id, args.track)
            finally:
                service.edits().delete(
                    packageName=PACKAGE_NAME, editId=edit_id
                ).execute(num_retries=1)
        except Exception as exc:
            return fail(str(exc))
        suffix = "（上传时创建）" if created else ""
        print(f"Play 轨道预检通过：{args.track} / wear:{args.track}{suffix}")
        return 0

    if any(
        value is None
        for value in (
            args.phone_aab,
            args.wear_aab,
            args.phone_version_code,
            args.wear_version_code,
        )
    ):
        return fail("上传需要同时指定两个 AAB 和各自的 versionCode")
    for label, path in (("手机", args.phone_aab), ("手表", args.wear_aab)):
        if not path.is_file():
            return fail(f"{label} AAB 不存在：{path}")
        if path.suffix.lower() != ".aab":
            return fail(f"{label}产物必须是 AAB：{path}")
    if not 0 < args.phone_version_code < args.wear_version_code <= 2_100_000_000:
        return fail("手机和手表 versionCode 不合法或不符合递增关系")
    try:
        notes = release_notes(args.release_notes)
        service = service_from_key(args.json_key, args.timeout)
        from googleapiclient.http import MediaFileUpload

        edit_id, codes = upload_to_edit(
            service,
            args.phone_aab,
            args.wear_aab,
            args.phone_version_code,
            args.wear_version_code,
            args.track,
            notes,
            MediaFileUpload,
        )
    except Exception as exc:
        try:
            from googleapiclient.errors import HttpError
        except ImportError:
            HttpError = ()
        if isinstance(exc, HttpError):
            message = f"Google Play API 错误（HTTP {exc.resp.status}）"
            try:
                detail = json.loads(exc.content.decode("utf-8", errors="replace"))
                message += f"：{str(detail.get('error', {}).get('message', ''))[:500]}"
            except (ValueError, AttributeError):
                pass
        else:
            message = str(exc)
        return fail(message)

    print("两个 AAB 已在同一编辑会话提交；Play 审核和上架状态以 Console 为准。")
    print(
        f"PLAY_UPLOAD_STATUS=COMMITTED|{PACKAGE_NAME}|{args.track}|"
        f"{codes['phone']}|{codes['wear']}|{edit_id}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
