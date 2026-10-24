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
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def preflight():
    if command("git", "status", "--porcelain", "--untracked-files=normal"):
        raise RuntimeError("桌面联合构建需要干净的工作区；请先提交并推送本次改动。")
    branch = command("git", "branch", "--show-current")
    if not branch:
        raise RuntimeError("请在已推送的分支上执行桌面联合构建。")
    sha = command("git", "rev-parse", "HEAD")
    remote_sha = command("gh", "api", f"repos/{{owner}}/{{repo}}/git/ref/heads/{branch}",
                         "--jq", ".object.sha")
    if sha != remote_sha:
        raise RuntimeError("当前分支与 GitHub 提交不一致，请先推送再构建。")
    command("gh", "workflow", "view", WORKFLOW, "--ref", branch, "--yaml")
    return branch, sha


def download_bundle(run_id, request_id, output, expected):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        command("gh", "run", "download", str(run_id), "--name",
                f"ai-link-windows-{request_id}", "--dir", temporary)
        staging = Path(temporary)
        actual = json.loads((staging / "build-info.json").read_text(encoding="utf-8-sig"))
        if actual != expected:
            raise RuntimeError("Windows 产物的提交或版本不一致，已停止归档。")
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
    subprocess.run(["gh", "run", "watch", str(run["databaseId"]), "--exit-status"],
                   cwd=ROOT, check=True, timeout=3600)
    download_bundle(run["databaseId"], request_id, args.output, expected)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
