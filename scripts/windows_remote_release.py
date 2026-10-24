"""Build the same commit on GitHub's Windows runner and download its bundle."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time
import uuid
import zipfile


WORKFLOW = "ai-link-windows.yml"
ROOT = Path(__file__).resolve().parents[1]


def command(*args):
    try:
        return subprocess.check_output(args, cwd=ROOT, text=True,
                                       stderr=subprocess.PIPE).strip()
    except subprocess.CalledProcessError as error:
        if args[0] != "gh":
            raise
        detail = (error.stderr or "").strip()
        if "HTTP 403" in detail or "Resource not accessible" in detail:
            raise RuntimeError(
                "GitHub Actions 权限不足：请确认当前令牌已选择此仓库，且 Actions 权限为 Read and write。"
                "GH_TOKEN / GITHUB_TOKEN 会覆盖 gh 登录凭据；请更新实际生效的令牌后重试。"
            ) from error
        raise RuntimeError(f"GitHub CLI 执行失败：{detail or error}") from error


def preflight():
    if command("git", "status", "--porcelain", "--untracked-files=normal"):
        raise RuntimeError("GitHub Windows 构建需要干净的工作区；请先提交并推送本次改动。")
    branch = command("git", "branch", "--show-current")
    if not branch:
        raise RuntimeError("请在已推送的分支上执行 GitHub Windows 构建。")
    sha = command("git", "rev-parse", "HEAD")
    remote_ref = command("git", "ls-remote", "--exit-code", "origin", f"refs/heads/{branch}")
    remote_sha = remote_ref.split()[0]
    if sha != remote_sha:
        raise RuntimeError("当前分支与 GitHub 提交不一致，请先推送再构建。")
    # Git verifies source access; Actions access must not require Contents API permissions.
    state = command("gh", "api", f"repos/{{owner}}/{{repo}}/actions/workflows/{WORKFLOW}",
                    "--jq", ".state")
    if state != "active":
        raise RuntimeError("Windows 工作流未启用，请在 GitHub Actions 中启用后重试。")
    return branch, sha


def wait_for_run(run_id, timeout=3600):
    # gh run watch does not support fine-grained PATs; the Actions API does.
    deadline = time.monotonic() + timeout
    previous = None
    while time.monotonic() < deadline:
        run = json.loads(command("gh", "api",
                                 f"repos/{{owner}}/{{repo}}/actions/runs/{run_id}"))
        status = run["status"]
        if status != previous:
            print(f"Windows 构建状态：{status}", flush=True)
            previous = status
        if status == "completed":
            if run["conclusion"] != "success":
                raise RuntimeError(f"Windows 构建未成功：{run['conclusion']}，请查看任务日志。")
            return
        time.sleep(10)
    raise RuntimeError("等待 Windows 构建超时，请查看 GitHub Actions 任务；本次未下载产物。")


def download_bundle(run_id, request_id, output, expected):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        command("gh", "run", "download", str(run_id), "--name",
                f"ai-link-windows-{request_id}", "--dir", temporary)
        staging = Path(temporary)
        actual = json.loads((staging / "build-info.json").read_text(encoding="utf-8-sig"))
        if actual != expected:
            raise RuntimeError("Windows 产物的提交或版本不一致，已停止归档。")
        installer_name = f"AI-Link-Setup-{expected['version']}+{expected['build_number']}.exe"
        installer = staging / installer_name
        if not installer.is_file():
            raise RuntimeError("Windows 产物缺少带版本号的安装程序。")
        with installer.open('rb') as stream:
            if stream.read(2) != b'MZ':
                raise RuntimeError("Windows 安装程序格式无效。")
        archive = staging / "windows.zip"
        with zipfile.ZipFile(archive) as bundle:
            required = {"AI-Link/mulit_ai_flutter.exe", "AI-Link/flutter_windows.dll",
                        "AI-Link/data/icudtl.dat"}
            if not required.issubset(bundle.namelist()):
                raise RuntimeError("Windows 产物缺少应用程序或运行时文件。")
            if bundle.testzip() is not None:
                raise RuntimeError("Windows ZIP 校验失败。")
        name = f"AI-Link-{expected['version']}+{expected['build_number']}-windows.zip"
        (output / name).write_bytes(archive.read_bytes())
        (output / installer_name).write_bytes(installer.read_bytes())
        (output / "build-info.json").write_text(json.dumps(actual, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build-number")
    args = parser.parse_args()
    branch, sha = preflight()
    if args.check:
        print("Windows GitHub Actions 构建环境检查通过。")
        return
    if not (args.output and args.version and args.build_number):
        parser.error("--output、--version、--build-number 必须同时指定")
    flutter = json.loads(command("flutter", "--version", "--machine"))["frameworkVersion"]
    expected = dict(source_sha=sha, version=args.version, build_number=args.build_number,
                    flutter_version=flutter)
    request_id = uuid.uuid4().hex
    fields = [item for key, value in {**expected, "request_id": request_id}.items()
              for item in ("-f", f"{key}={value}")]
    command("gh", "workflow", "run", WORKFLOW, "--ref", branch, *fields)
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        runs = json.loads(command("gh", "run", "list", "--workflow", WORKFLOW,
                                  "--event", "workflow_dispatch", "--limit", "100",
                                  "--json", "databaseId,displayTitle,url"))
        run = next((run for run in runs
                    if run["displayTitle"] == f"AI Link Windows {request_id}"), None)
        if run:
            break
        time.sleep(5)
    else:
        raise RuntimeError(f"未能定位 Windows 构建任务，请在 GitHub Actions 查看 {request_id}。")
    print(f"Windows 构建：{run['url']}", flush=True)
    wait_for_run(run["databaseId"])
    download_bundle(run["databaseId"], request_id, args.output, expected)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
