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


def require_tracks(service, edit_id: str, track: str, wear_track: str | None = None) -> None:
    available_tracks = {
        item["track"]
        for item in service.edits()
        .tracks()
        .list(packageName=PACKAGE_NAME, editId=edit_id)
        .execute(num_retries=3)
        .get("tracks", [])
    }
    wear_track = wear_track or f"wear:{track}"
    if not wear_track.startswith("wear:") or not wear_track[5:].strip():
        raise ValueError("Wear OS 轨道必须使用完整的 wear:<轨道名>")
    if track not in available_tracks:
        raise RuntimeError(f"Play Console 尚未提供手机 {track} 轨道。")
    if wear_track in available_tracks:
        return
    choices = "、".join(sorted(t for t in available_tracks if t.startswith("wear:")))
    raise RuntimeError(
        f"Play Console 尚未提供 Wear OS {wear_track} 轨道。"
        "请在 Console 建立并配置对应轨道，或用 --wear-track 指定已有轨道。"
        f"已有手表轨道：{choices or '无'}。"
        "脚本不再自动创建轨道，以避免新建轨道带版本校验时返回 HTTP 500。"
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
    wear_track: str | None = None,
) -> tuple[str, dict[str, int]]:
    """Commit both form factors together; discard the edit on any failure."""
    edit_id = service.edits().insert(body={}, packageName=PACKAGE_NAME).execute(
        num_retries=3
    )["id"]
    codes: dict[str, int] = {}
    wear_track = wear_track or f"wear:{track}"
    stage = "检查轨道"
    print(f"Play 编辑会话：{edit_id}", flush=True)
    try:
        require_tracks(service, edit_id, track, wear_track)

        for label, path, expected in (
            ("phone", phone, phone_code),
            ("wear", wear, wear_code),
        ):
            stage = f"上传 {label} AAB"
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

        for destination, code in ((track, phone_code), (wear_track, wear_code)):
            stage = f"分配轨道 {destination}"
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

        stage = "校验编辑（edits.validate）"
        print(f"开始{stage}", flush=True)
        service.edits().validate(packageName=PACKAGE_NAME, editId=edit_id).execute(
            num_retries=3
        )
        print("Play 编辑校验通过", flush=True)
        stage = "提交编辑（edits.commit）"
        print(f"开始{stage}", flush=True)
        service.edits().commit(packageName=PACKAGE_NAME, editId=edit_id).execute(
            num_retries=3
        )
        return edit_id, codes
    except Exception:
        print(f"Play 失败阶段：{stage}；editId={edit_id}", file=sys.stderr, flush=True)
        try:
            service.edits().delete(packageName=PACKAGE_NAME, editId=edit_id).execute(
                num_retries=1
            )
            print("已丢弃本次 Play 编辑会话", file=sys.stderr, flush=True)
        except Exception:
            print("丢弃 Play 编辑未获确认，请在 Console 核对状态", file=sys.stderr, flush=True)
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
    parser.add_argument("--wear-track", help="完整的手表轨道名，默认 wear:<手机轨道>")
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
    if args.wear_track is not None and (
        not args.wear_track.startswith("wear:") or not args.wear_track[5:].strip()
    ):
        return fail("--wear-track 必须使用完整的 wear:<轨道名>")
    if args.check_tracks:
        try:
            service = service_from_key(args.json_key, args.timeout)
            edit_id = service.edits().insert(body={}, packageName=PACKAGE_NAME).execute(
                num_retries=3
            )["id"]
            try:
                require_tracks(service, edit_id, args.track, args.wear_track)
            finally:
                service.edits().delete(
                    packageName=PACKAGE_NAME, editId=edit_id
                ).execute(num_retries=1)
        except Exception as exc:
            return fail(str(exc))
        print(f"Play 轨道预检通过：{args.track} / {args.wear_track or f'wear:{args.track}'}")
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
            args.wear_track,
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
