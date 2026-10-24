import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import windows_remote_release as remote


class WindowsRemoteReleaseTest(unittest.TestCase):
    def test_dirty_worktree_is_rejected_before_contacting_github(self):
        with patch.object(remote, "command", return_value=" M lib/main.dart") as command:
            with self.assertRaisesRegex(RuntimeError, "干净"):
                remote.preflight()
            self.assertEqual(command.call_count, 1)

    def test_unpushed_commit_is_rejected(self):
        with patch.object(remote, "command", side_effect=["", "main", "local", "remote"]):
            with self.assertRaisesRegex(RuntimeError, "推送"):
                remote.preflight()

    def test_preflight_checks_workflow_on_matching_remote_branch(self):
        with patch.object(remote, "command", side_effect=["", "main", "sha", "sha", "yaml"]) as command:
            self.assertEqual(remote.preflight(), ("main", "sha"))
            self.assertEqual(command.call_args.args,
                             ("gh", "workflow", "view", remote.WORKFLOW, "--ref", "main", "--yaml"))

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
                patch.object(remote.subprocess, "run") as watch, \
                patch.object(remote, "download_bundle") as download:
            request.return_value.hex = "request"
            remote.main()
            dispatch = command.call_args_list[1].args
            self.assertEqual(dispatch[:6], ("gh", "workflow", "run", remote.WORKFLOW, "--ref", "main"))
            for field in ("source_sha=sha", "version=1.1.3", "build_number=42", "request_id=request"):
                self.assertIn(field, dispatch)
            self.assertEqual(watch.call_args.args[0], ["gh", "run", "watch", "123", "--exit-status"])
            download.assert_called_once_with(123, "request", Path("out"), expected)

    def test_failed_workflow_is_not_downloaded(self):
        run = dict(databaseId=123, displayTitle="AI Link Windows request", url="https://example.com/run")
        with patch("sys.argv", ["windows_remote_release.py", "--output", "out",
                                "--version", "1.1.3", "--build-number", "42"]), \
                patch.object(remote, "preflight", return_value=("main", "sha")), \
                patch.object(remote.uuid, "uuid4") as request, \
                patch.object(remote, "command", side_effect=[
                    '{"frameworkVersion":"3.47.4"}', "", json.dumps([run])]), \
                patch.object(remote.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "gh")), \
                patch.object(remote, "download_bundle") as download:
            request.return_value.hex = "request"
            with self.assertRaises(subprocess.CalledProcessError):
                remote.main()
            download.assert_not_called()


if __name__ == "__main__":
    unittest.main()
