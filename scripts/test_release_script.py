import os
import subprocess
import tempfile
import unittest
from pathlib import Path


RELEASE_SCRIPT = Path(__file__).resolve().parents[1] / "release.sh"


class ReleaseScriptTest(unittest.TestCase):
    def test_bash_syntax(self):
        subprocess.run(["/bin/bash", "-n", str(RELEASE_SCRIPT)], check=True)

    def run_upload_step(self, succeeds):
        # Execute the real post-build branch without building or contacting Play.
        source = RELEASE_SCRIPT.read_text()
        upload_step = source[source.index('if (( push_release )); then\n  echo "上传手机到'):]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            uploader = output / "fake-uploader"
            uploader.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$@"\n'
                + ('echo "PLAY_UPLOAD_STATUS=COMMITTED|edit-test"\n' if succeeds else 'exit 1\n')
            )
            uploader.chmod(0o700)
            env = os.environ.copy()
            env.update(
                push_release="1",
                play_track="internal",
                output=directory,
                python_bin=str(uploader),
                json_key=str(output / "fake-account.json"),
                phone=str(output / "phone.aab"),
                wear=str(output / "wear.aab"),
                code="1",
                watch_code="1000001",
            )
            result = subprocess.run(
                ["/bin/bash", "-Eeuo", "pipefail", "-c", upload_step],
                env=env, capture_output=True, text=True, errors="replace",
            )
            info = output / "release-info.txt"
            return result, info.read_text() if info.exists() else ""

    def test_upload_branch_reaches_uploader_and_records_success(self):
        result, info = self.run_upload_step(succeeds=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("上传手机到 internal，Wear OS 到 wear:internal", result.stdout)
        self.assertIn("--track\ninternal\n", result.stdout)
        self.assertIn("--wear-version-code\n1000001\n", result.stdout)
        self.assertEqual(info, "playStatus=COMMITTED|edit-test\n")

    def test_upload_failure_is_recorded(self):
        result, info = self.run_upload_step(succeeds=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Google Play 上传未完成", result.stderr)
        self.assertEqual(info, "playStatus=FAILED\n")


if __name__ == "__main__":
    unittest.main()
