import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import windows_remote_release as remote


class WindowsRemoteReleaseTest(unittest.TestCase):
    def test_permission_error_explains_effective_token_and_actions_scope(self):
        error = subprocess.CalledProcessError(
            1, "gh", stderr="gh: Resource not accessible by personal access token (HTTP 403)")
        with patch.object(remote.subprocess, "check_output", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, "Actions 权限为 Read and write") as caught:
                remote.command("gh", "api", "endpoint")
            self.assertIn("GH_TOKEN / GITHUB_TOKEN", str(caught.exception))

    def test_dirty_worktree_is_rejected_before_contacting_github(self):
        with patch.object(remote, "command", return_value=" M lib/main.dart") as command:
            with self.assertRaisesRegex(RuntimeError, "干净"):
                remote.preflight()
            self.assertEqual(command.call_count, 1)

    def test_unpushed_commit_is_rejected(self):
        with patch.object(remote, "command", side_effect=["", "main", "local", "remote\trefs/heads/main"]):
            with self.assertRaisesRegex(RuntimeError, "推送"):
                remote.preflight()

    def test_preflight_checks_workflow_on_matching_remote_branch(self):
        with patch.object(remote, "command", side_effect=["", "main", "sha", "sha\trefs/heads/main", "active"]) as command:
            self.assertEqual(remote.preflight(), ("main", "sha"))
            self.assertEqual(command.call_args_list[3].args,
                             ("git", "ls-remote", "--exit-code", "origin", "refs/heads/main"))
            self.assertEqual(command.call_args.args,
                             ("gh", "api", f"repos/{{owner}}/{{repo}}/actions/workflows/{remote.WORKFLOW}",
                              "--jq", ".state"))

    def test_disabled_workflow_is_rejected(self):
        with patch.object(remote, "command", side_effect=["", "main", "sha", "sha\trefs/heads/main", "disabled_manually"]):
            with self.assertRaisesRegex(RuntimeError, "未启用"):
                remote.preflight()

    def test_wait_uses_actions_api_and_only_accepts_success(self):
        for conclusion in ("success", "failure", "cancelled", "timed_out"):
            with self.subTest(conclusion=conclusion), \
                    patch.object(remote, "command", side_effect=[
                        json.dumps(dict(status="queued", conclusion=None)),
                        json.dumps(dict(status="completed", conclusion=conclusion))]) as command, \
                    patch.object(remote.time, "sleep"):
                if conclusion == "success":
                    remote.wait_for_run(123)
                else:
                    with self.assertRaisesRegex(RuntimeError, conclusion):
                        remote.wait_for_run(123)
                self.assertEqual(command.call_args.args,
                                 ("gh", "api", "repos/{owner}/{repo}/actions/runs/123"))

    def test_wait_timeout_does_not_succeed(self):
        with patch.object(remote.time, "monotonic", side_effect=[0, 3601]), \
                patch.object(remote, "command") as command:
            with self.assertRaisesRegex(RuntimeError, "超时"):
                remote.wait_for_run(123)
            command.assert_not_called()

    def test_only_matching_complete_artifact_is_archived(self):
        expected = dict(source_sha="sha", version="1.1.3", build_number="42",
                        flutter_version="3.47.4")
        for valid in (True, False):
            with self.subTest(valid=valid), tempfile.TemporaryDirectory() as directory:
                output = Path(directory)

                def download(*args):
                    staging = Path(args[-1])
                    info = dict(expected, source_sha="sha" if valid else "other")
                    (staging / "build-info.json").write_text(json.dumps(info), encoding="utf-8-sig")
                    with zipfile.ZipFile(staging / "windows.zip", "w") as bundle:
                        bundle.writestr("AI-Link/mulit_ai_flutter.exe", "exe")
                        bundle.writestr("AI-Link/flutter_windows.dll", "dll")
                        bundle.writestr("AI-Link/data/icudtl.dat", "data")

                with patch.object(remote, "command", side_effect=download):
                    if valid:
                        remote.download_bundle(123, "request", output, expected)
                        self.assertTrue((output / "AI-Link-1.1.3+42-windows.zip").is_file())
                        self.assertEqual(json.loads((output / "build-info.json").read_text()), expected)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "不一致"):
                            remote.download_bundle(123, "request", output, expected)
                        self.assertEqual(list(output.iterdir()), [])

    def test_dispatch_tracks_only_its_request_and_downloads_after_success(self):
        unrelated = dict(databaseId=456, displayTitle="AI Link Windows other", url="other")
        matching = dict(databaseId=123, displayTitle="AI Link Windows request", url="matching")
        expected = dict(source_sha="sha", version="1.1.3", build_number="42",
                        flutter_version="3.47.4")
        with patch("sys.argv", ["windows_remote_release.py", "--output", "out",
                                "--version", "1.1.3", "--build-number", "42"]), \
                patch.object(remote, "preflight", return_value=("main", "sha")), \
                patch.object(remote.uuid, "uuid4") as request, \
                patch.object(remote, "command", side_effect=[
                    '{"frameworkVersion":"3.47.4"}', "", json.dumps([unrelated, matching])]) as command, \
                patch.object(remote, "wait_for_run") as watch, \
                patch.object(remote, "download_bundle") as download:
            request.return_value.hex = "request"
            remote.main()
            dispatch = command.call_args_list[1].args
            self.assertEqual(dispatch[:6], ("gh", "workflow", "run", remote.WORKFLOW, "--ref", "main"))
            for field in ("source_sha=sha", "version=1.1.3", "build_number=42", "request_id=request"):
                self.assertIn(field, dispatch)
            watch.assert_called_once_with(123)
            download.assert_called_once_with(123, "request", Path("out"), expected)

    def test_failed_workflow_is_not_downloaded(self):
        run = dict(databaseId=123, displayTitle="AI Link Windows request", url="https://example.com/run")
        with patch("sys.argv", ["windows_remote_release.py", "--output", "out",
                                "--version", "1.1.3", "--build-number", "42"]), \
                patch.object(remote, "preflight", return_value=("main", "sha")), \
                patch.object(remote.uuid, "uuid4") as request, \
                patch.object(remote, "command", side_effect=[
                    '{"frameworkVersion":"3.47.4"}', "", json.dumps([run])]), \
                patch.object(remote, "wait_for_run", side_effect=RuntimeError("Windows 构建未成功")), \
                patch.object(remote, "download_bundle") as download:
            request.return_value.hex = "request"
            with self.assertRaisesRegex(RuntimeError, "未成功"):
                remote.main()
            download.assert_not_called()


if __name__ == "__main__":
    unittest.main()
