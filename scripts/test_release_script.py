import os
import subprocess
import tempfile
import unittest
from pathlib import Path


RELEASE_SCRIPT = Path(__file__).resolve().parents[1] / "release.sh"


class ReleaseScriptTest(unittest.TestCase):
    def test_bash_syntax(self):
        subprocess.run(["/bin/bash", "-n", str(RELEASE_SCRIPT)], check=True)

    def test_detected_play_proxy_does_not_leak_into_flutter(self):
        source = RELEASE_SCRIPT.read_text()
        preflight = source[source.index('play_env=(env)'):source.index('normalize_fingerprint()')]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / "scripts" / ".venv"
            runtime.mkdir(parents=True)
            python = runtime / "bin" / "python"
            python.parent.mkdir()
            python.write_text(
                '#!/bin/sh\n'
                'case "$*" in\n'
                '  *--check-tracks*) printf "play=%s|%s\\n" "$http_proxy" "$https_proxy" ;;\n'
                'esac\n'
            )
            python.chmod(0o700)
            scutil = root / "scutil"
            scutil.write_text(
                '#!/bin/sh\n'
                'echo "HTTPProxy : 127.0.0.1"\n'
                'echo "HTTPPort : 7897"\n'
            )
            scutil.chmod(0o700)
            key = root / "fake-account.json"
            key.touch()
            env = {
                k: v for k, v in os.environ.items()
                if k.lower() not in {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}
            }
            env.update(
                PATH=f'{root}:{env["PATH"]}',
                repo_root=directory,
                json_key=str(key),
                push_release="1",
                play_track="internal",
            )
            result = subprocess.run(
                ["/bin/bash", "-Eeuo", "pipefail", "-c", preflight +
                 '\nprintf "flutter=%s|%s\\n" "${http_proxy-}" "${https_proxy-}"\n'],
                env=env, cwd=root, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("play=http://127.0.0.1:7897|http://127.0.0.1:7897", result.stdout)
            self.assertIn("flutter=|", result.stdout)

    def run_upload_step(self, succeeds):
        # Execute the real post-build branch without building or contacting Play.
        source = RELEASE_SCRIPT.read_text()
        upload_step = source[source.index('if (( push_release )); then\n  echo "上传手机到'):]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            uploader = output / "fake-uploader"
            uploader.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$@"\n'
                'printf "proxy=%s|%s\\n" "$http_proxy" "$https_proxy"\n'
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
                ["/bin/bash", "-Eeuo", "pipefail", "-c",
                 'play_env=(env http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897)\n' + upload_step],
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
        self.assertIn("proxy=http://127.0.0.1:7897|http://127.0.0.1:7897", result.stdout)
        self.assertEqual(info, "playStatus=COMMITTED|edit-test\n")

    def test_upload_failure_is_recorded(self):
        result, info = self.run_upload_step(succeeds=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Google Play 上传未完成", result.stderr)
        self.assertEqual(info, "playStatus=FAILED\n")


if __name__ == "__main__":
    unittest.main()
