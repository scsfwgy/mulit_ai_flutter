import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


RELEASE_SCRIPT = Path(__file__).resolve().parents[1] / "release.sh"


class ReleaseScriptTest(unittest.TestCase):
    def test_bash_syntax(self):
        subprocess.run(["/bin/bash", "-n", str(RELEASE_SCRIPT)], check=True)

    def test_summary_prints_and_records_total_elapsed_time_once(self):
        source = RELEASE_SCRIPT.read_text()
        summary = source[source.index('print_summary() {'):source.index('\nfail() {')]
        with tempfile.TemporaryDirectory() as directory:
            env = os.environ.copy()
            env.update(output=directory, version="1.1.5+90", git_hash="abcd1234",
                       android_status="成功", macos_status="成功", windows_status="成功",
                       ios_status="成功", ios_skip_reason="", website_status="未执行",
                       play_status="未执行", appstore_status="未执行", failure_reason="")
            result = subprocess.run(
                ["/bin/bash", "-Eeuo", "pipefail", "-c",
                 'summary_printed=0\nartifacts=()\n' + summary +
                 '\nrelease_started_at=$((SECONDS - 3661))\nprint_summary\nprint_summary\n'],
                env=env, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("总耗时：01:01:01（3661 秒）", result.stdout)
            self.assertEqual(result.stdout.count("总耗时："), 1)
            self.assertEqual((Path(directory) / "release-info.txt").read_text(), "elapsedSeconds=3661\n")

    def test_old_android_publish_flag_is_rejected(self):
        result = subprocess.run(["/bin/bash", str(RELEASE_SCRIPT), "--push-release"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("未知参数", result.stderr)

    def test_detected_publish_proxy_does_not_leak_into_flutter(self):
        source = RELEASE_SCRIPT.read_text()
        preflight = source[source.index('publish_env=(env)'):source.index('normalize_fingerprint()')]
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
                push_android="1",
                push_website="1",
                push_ios="0",
                play_track="internal",
                wear_track="wear:internal",
            )
            result = subprocess.run(
                ["/bin/bash", "-Eeuo", "pipefail", "-c", preflight +
                 '\nprintf "flutter=%s|%s\\n" "${http_proxy-}" "${https_proxy-}"\n'],
                env=env, cwd=root, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("play=http://127.0.0.1:7897|http://127.0.0.1:7897", result.stdout)
            self.assertIn("flutter=|", result.stdout)

    def run_upload_step(self, succeeds, wear_track="wear:internal"):
        # Execute the real post-build branch without building or contacting Play.
        source = RELEASE_SCRIPT.read_text()
        upload_step = source[source.index('if (( push_android )); then\n  echo "上传手机到'):]
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
                push_android="1",
                push_ios="0",
                play_track="internal",
                wear_track=wear_track,
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
                 'print_summary() { :; }\n'
                 'fail() { echo "$1" >&2; exit 1; }\n'
                 'publish_env=(env http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897)\n' + upload_step],
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
        self.assertIn("playStatus=COMMITTED|edit-test", info)
        self.assertIn("appstoreStatus=NOT_UPLOADED", info)

    def test_upload_failure_is_recorded(self):
        result, info = self.run_upload_step(succeeds=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Google Play 上传未完成", result.stderr)
        self.assertEqual(info, "playStatus=FAILED\n")

    def test_custom_wear_track_reaches_uploader(self):
        result, info = self.run_upload_step(True, "wear:手表内部测试V2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--wear-track\nwear:手表内部测试V2\n", result.stdout)
        self.assertIn("Wear OS 到 wear:手表内部测试V2", result.stdout)
        self.assertIn("playStatus=COMMITTED", info)

    def test_invalid_wear_track_stops_before_build(self):
        for name in ("alpha", "wear:", "wear:  "):
            result = subprocess.run(["/bin/bash", str(RELEASE_SCRIPT), "--wear-track", name],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("--wear-track 必须", result.stderr)

    def mock_release_root(self, directory, flags, website_failure=False, ios_signing=True,
                          appstore_failure=False, host="Darwin"):
        # Repo skeleton whose external commands are stubs, so release.sh runs its
        # real branch structure without building or touching the network.
        root = Path(directory)
        (root / "release.sh").write_text(RELEASE_SCRIPT.read_text())
        (root / "pubspec.yaml").write_text("version: 1.0.1+2\n")
        (root / "android").mkdir()
        (root / "test.jks").touch()
        for name in ("key.properties", "key.test.properties"):
            (root / "android" / name).write_text(
                "storeFile=../test.jks\nstorePassword=test\nkeyAlias=test\nkeyPassword=test\n")
        (root / "localConfig").mkdir()
        (root / "localConfig/google-play-service-account.json").touch()
        (root / "localConfig/appstore-connect.env").touch()
        runtime = root / "scripts/.venv/bin"
        runtime.mkdir(parents=True)
        commands = root / "commands"
        commands.mkdir()

        def executable(path, body):
            path.write_text("#!/bin/bash\nset -eu\n" + body)
            path.chmod(0o700)

        executable(commands / "uname", f'echo {host}\n')
        executable(commands / "xcrun", 'echo /mock-sdk\n')
        executable(commands / "security", 'echo "${SECURITY_IDENTITIES-}"\n')
        (root / "scripts/apple_release.py").write_text('''import argparse
import os
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--platform')
parser.add_argument('--output', type=Path)
parser.add_argument('--version')
parser.add_argument('--build-number')
args = parser.parse_args()
with open(os.environ['CALLS'], 'a') as stream:
    stream.write(f'apple {args.platform} {args.version}+{args.build_number}\\n')
args.output.mkdir(parents=True, exist_ok=True)
for suffix in (['ipa'] if args.platform == 'ios' else ['dmg', 'zip']):
    (args.output / f'AI-Link-{args.version}+{args.build_number}.{suffix}').write_text('artifact')
''')
        (root / "scripts/windows_remote_release.py").write_text('''import argparse
import os
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
parser.add_argument('--output', type=Path)
parser.add_argument('--version')
parser.add_argument('--build-number')
args = parser.parse_args()
with open(os.environ['CALLS'], 'a') as stream:
    stream.write('windows check\\n' if args.check else f'windows {args.version}+{args.build_number}\\n')
if not args.check:
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / f'AI-Link-{args.version}+{args.build_number}-windows.zip').write_text('artifact')
    (args.output / f'AI-Link-Setup-{args.version}+{args.build_number}.exe').write_bytes(b'MZinstaller')
''')
        certificate = ("F539897F7B786486EBC44F1383AF434DCE6AE6BB3ED12DCF363F6F4633B8596F"
                       if "--test" in flags else
                       "7D40427292830784C3DB74560D3F1368B9A0B8E5DACD6D73FFBBD4A771D211DE")
        executable(commands / "git", '''case "$*" in
          *--is-shallow-repository*) echo false ;;
          *--short*) echo abcd1234 ;;
          *rev-list*) echo 10 ;;
        esac
        ''')
        executable(commands / "scutil", 'echo "HTTPProxy : 127.0.0.1"\necho "HTTPPort : 7897"\n')
        executable(commands / "apksigner", f'echo "Signer #1 certificate SHA-256 digest: {certificate}"\n')
        executable(commands / "keytool", f'echo "SHA256: {certificate}"\n')
        executable(commands / "powershell.exe", '''while [[ $# -gt 0 ]]; do
          case "$1" in
            -Version) version="$2"; shift 2 ;;
            -BuildNumber) number="$2"; shift 2 ;;
            -OutputDir) output_dir="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        mkdir -p "$output_dir"
        echo MZinstaller > "$output_dir/AI-Link-Setup-$version+$number.exe"
        ''')
        executable(commands / "flutter", '''echo "flutter $*" >> "$CALLS"
        if [[ "$1" != build ]]; then exit 0; fi
        if [[ "$2" == windows ]]; then
          mkdir -p build/windows/x64/runner/Release/data
          echo EXE > build/windows/x64/runner/Release/mulit_ai_flutter.exe
          echo DLL > build/windows/x64/runner/Release/flutter_windows.dll
          echo assets > build/windows/x64/runner/Release/data/icudtl.dat
          exit 0
        fi
        for argument in "$@"; do
          if [[ "$argument" == --split-debug-info=* ]]; then
            symbols="${argument#*=}"
            mkdir -p "$symbols"
            echo "$2" > "$symbols/app.android-arm64.symbols"
          fi
        done
        mkdir -p build/app/outputs/flutter-apk build/app/outputs/bundle/release build/app/outputs/mapping/release
        echo APK > build/app/outputs/flutter-apk/app-release.apk
        echo AAB > build/app/outputs/bundle/release/app-release.aab
        echo "$2" > build/app/outputs/mapping/release/mapping.txt
        ''')
        executable(root / "android/gradlew", '''echo "gradle $*" >> "$CALLS"
        mkdir -p ../build/wear/outputs/apk/release ../build/wear/outputs/bundle/release ../build/wear/outputs/mapping/release
        echo APK > ../build/wear/outputs/apk/release/wear-release.apk
        echo AAB > ../build/wear/outputs/bundle/release/wear-release.aab
        echo "$1" > ../build/wear/outputs/mapping/release/mapping.txt
        ''')
        executable(runtime / "python", '''echo "python $*" >> "$CALLS"
        if [[ "$*" == *website_release.py* && "$*" != *--check* ]]; then
          if [[ "$WEBSITE_FAILURE" == 1 ]]; then exit 1; fi
          for ((i=1; i<=$#; i++)); do
            if [[ "${!i}" == --manifest-out ]]; then j=$((i+1)); echo '{}' > "${!j}"; fi
          done
        fi
        if [[ "$*" == *play_upload.py* && "$*" != *--check-tracks* ]]; then
          echo 'PLAY_UPLOAD_STATUS=COMMITTED|test-edit'
        fi
        if [[ "$*" == *appstore_upload.py* && "$*" != *--check* ]]; then
          if [[ "$APPSTORE_FAILURE" == 1 ]]; then exit 1; fi
          echo 'APPSTORE_UPLOAD_STATUS=UPLOADED|com.maxhall.ailink|1.0.1|10|test-delivery'
        fi
        ''')
        env = {k: v for k, v in os.environ.items() if k.lower() not in {"http_proxy", "https_proxy"}}
        env.update(PATH=f'{commands}:{env["PATH"]}', CALLS=str(root / "calls"),
                   WEBSITE_FAILURE=str(int(website_failure)),
                   APPSTORE_FAILURE=str(int(appstore_failure)),
                   SECURITY_IDENTITIES=('  1) ABCD "Apple Distribution: Test (T94W2V3B6M)"'
                                        if ios_signing else ""))
        return root, env

    def test_windows_archive_uses_release_version_and_complete_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--platform", "windows"],
                                               host="MINGW64_NT-10.0")
            result = subprocess.run(["/bin/bash", "release.sh", "--platform", "windows"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            self.assertIn("flutter build windows --release --build-name=1.0.1 --build-number=10\n",
                          calls)
            self.assertNotIn("gradle", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt"))
            self.assertIn("buildStatus=COMPLETE\n", info.read_text())
            archive = info.parent / "windows/AI-Link-1.0.1+10-windows.zip"
            self.assertTrue((info.parent / "windows/AI-Link-Setup-1.0.1+10.exe").is_file())
            self.assertEqual((info.parent / "AI-Link-windows-1.0.1-abcd1234+10.zip").read_bytes(), archive.read_bytes())
            self.assertEqual((info.parent / "AI-Link-windows-1.0.1-abcd1234+10.exe").read_bytes(),
                             (info.parent / "windows/AI-Link-Setup-1.0.1+10.exe").read_bytes())
            with zipfile.ZipFile(archive) as bundle:
                self.assertTrue({"AI-Link/mulit_ai_flutter.exe", "AI-Link/flutter_windows.dll",
                                 "AI-Link/data/icudtl.dat"}.issubset(bundle.namelist()))

    def test_desktop_builds_macos_and_remote_windows_into_one_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--platform", "desktop"])
            result = subprocess.run(["/bin/bash", "release.sh", "--platform", "desktop"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            self.assertLess(calls.index("windows check"), calls.index("flutter pub get"))
            self.assertIn("apple macos 1.0.1+10", calls)
            self.assertIn("windows 1.0.1+10", calls)
            self.assertNotIn("apple ios", calls)
            self.assertNotIn("gradle", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt"))
            self.assertTrue((info.parent / "macos/AI-Link-1.0.1+10.dmg").is_file())
            self.assertTrue((info.parent / "windows/AI-Link-1.0.1+10-windows.zip").is_file())
            self.assertTrue((info.parent / "windows/AI-Link-Setup-1.0.1+10.exe").is_file())
            self.assertEqual(len((info.parent / "SHA256SUMS").read_text().splitlines()), 4)
            for name in ("AI-Link-macos-1.0.1-abcd1234+10.dmg", "AI-Link-macos-1.0.1-abcd1234+10.zip",
                         "AI-Link-windows-1.0.1-abcd1234+10.exe", "AI-Link-windows-1.0.1-abcd1234+10.zip"):
                self.assertTrue((info.parent / name).is_file(), name)
            self.assertIn("Windows：成功", result.stdout)

    def test_github_windows_builds_only_remote_windows(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--github-windows"], host="Linux")
            (root / "commands/xcrun").unlink()
            result = subprocess.run(["/bin/bash", "release.sh", "--github-windows"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            self.assertIn("windows check", calls)
            self.assertIn("windows 1.0.1+10", calls)
            self.assertNotIn("apple ", calls)
            self.assertNotIn("gradle", calls)
            self.assertNotIn("flutter build", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt"))
            self.assertIn("windowsStatus=COMPLETE", info.read_text())
            self.assertTrue((info.parent / "windows/AI-Link-Setup-1.0.1+10.exe").is_file())
            self.assertEqual(len((info.parent / "SHA256SUMS").read_text().splitlines()), 2)
            self.assertTrue((info.parent / "AI-Link-windows-1.0.1-abcd1234+10.exe").is_file())

    def test_build_all_archives_every_platform_without_uploading(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--build-all"])
            result = subprocess.run(["/bin/bash", "release.sh", "--build-all"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            for build in ("flutter build apk", "flutter build appbundle", "gradle :wear:assembleRelease",
                          "gradle :wear:bundleRelease", "apple ios 1.0.1+10", "apple macos 1.0.1+10",
                          "windows 1.0.1+10"):
                self.assertIn(build, calls)
            self.assertNotIn("python ", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt"))
            self.assertTrue((info.parent / "windows/AI-Link-Setup-1.0.1+10.exe").is_file())
            self.assertEqual(len((info.parent / "SHA256SUMS").read_text().splitlines()), 9)
            expected = {
                f"AI-Link-{platform}-1.0.1-abcd1234+10.{extension}"
                for platform, extensions in (("phone", ("apk", "aab")), ("wear", ("apk", "aab")),
                                             ("macos", ("dmg", "zip")), ("windows", ("exe", "zip")),
                                             ("ios", ("ipa",)))
                for extension in extensions
            }
            self.assertEqual({file.name for file in info.parent.iterdir() if file.name.startswith('AI-Link-')}, expected)
            recorded = {line.split(maxsplit=1)[1].strip() for line in (info.parent / "SHA256SUMS").read_text().splitlines()}
            self.assertEqual(recorded, expected)
            self.assertEqual((info.parent / "AI-Link-ios-1.0.1-abcd1234+10.ipa").read_bytes(),
                             (info.parent / "ios/AI-Link-1.0.1+10.ipa").read_bytes())
            for platform in ("macosStatus", "windowsStatus", "iosWatchStatus", "buildStatus"):
                self.assertIn(f"{platform}=COMPLETE", info.read_text())

    def test_build_all_requires_ios_distribution_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--build-all"], ios_signing=False)
            result = subprocess.run(["/bin/bash", "release.sh", "--build-all"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("没有 iOS Distribution", result.stderr)
            self.assertFalse((root / "calls").exists())

    def test_new_build_flags_reject_conflicting_modes(self):
        for flags in (["--github-windows", "--build-all"], ["--build-all", "--github-windows"],
                      ["--github-windows", "--platform", "macos"],
                      ["--platform", "android", "--build-all"],
                      ["--github-windows", "--test"], ["--build-all", "--test"],
                      ["--github-windows", "--push-android"], ["--github-windows", "--push-ios"]):
            with self.subTest(flags=flags):
                result = subprocess.run(["/bin/bash", str(RELEASE_SCRIPT), *flags],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_complete_release_modes_and_website_failure(self):
        for flags, website_failure in (([], False), (["--test"], False),
                (["--push-website"], False), (["--push-android"], False),
                (["--push-android"], True), (["--platform", "android"], False),
                (["--platform", "macos"], False), (["--platform", "ios"], False),
                (["--platform", "all", "--push-website"], False)):
            with self.subTest(flags=flags, website_failure=website_failure), tempfile.TemporaryDirectory() as directory:
                root, env = self.mock_release_root(directory, flags, website_failure)
                result = subprocess.run(["/bin/bash", "release.sh", *flags], cwd=root,
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, int(website_failure), result.stderr)
                self.assertIn("本次发布汇总", result.stdout)
                calls = (root / "calls").read_text()
                infos = list((root / "release-artifacts").rglob("release-info.txt"))
                self.assertEqual(len(infos), 1)
                output = infos[0].parent
                android = flags not in (["--platform", "macos"], ["--platform", "ios"])
                apple = flags in ([], ["--platform", "all", "--push-website"])
                ios_built = apple or flags == ["--platform", "ios"]
                self.assertIn(f"iOS / Apple Watch：{'成功' if ios_built else '未构建'}", result.stdout)
                self.assertEqual(len(list(output.glob("*.apk"))), 2 if android else 0)
                self.assertEqual(len(list(output.glob("*.aab"))),
                                 0 if not android or "--test" in flags else 2)
                if android:
                    self.assertEqual((output / "apk/app-r8/mapping.txt").read_text().strip(), "apk")
                    if flags != ["--test"]:
                        self.assertEqual((output / "aab/app-r8/mapping.txt").read_text().strip(), "appbundle")
                if apple:
                    self.assertIn("apple macos 1.0.1+10", calls)
                    self.assertIn("apple ios 1.0.1+10", calls)
                actual_play = "python -u scripts/play_upload.py" in calls
                self.assertEqual(actual_play, flags == ["--push-android"] and not website_failure)
                if website_failure:
                    self.assertIn("websiteStatus=FAILED", infos[0].read_text())
                    self.assertIn("失败原因：官网下载同步未完成", result.stdout)
                elif "--push-website" in flags or "--push-android" in flags:
                    self.assertIn("websiteStatus=CONFIRMED", infos[0].read_text())
                else:
                    self.assertNotIn("python ", calls)

    def test_push_ios_uploads_ipa_without_android_or_macos(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--push-ios"])
            result = subprocess.run(["/bin/bash", "release.sh", "--push-ios"], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            self.assertIn("apple ios 1.0.1+10", calls)
            self.assertNotIn("apple macos", calls)
            self.assertNotIn("gradle", calls)
            self.assertIn("python scripts/appstore_upload.py --check-online", calls)
            self.assertIn("python -u scripts/appstore_upload.py", calls)
            self.assertIn("App Store Connect：成功", result.stdout)
            info = next((root / "release-artifacts").rglob("release-info.txt"))
            self.assertIn("appstoreStatus=UPLOADED|com.maxhall.ailink|1.0.1|10|test-delivery\n",
                          info.read_text())
            self.assertIn("playStatus=NOT_UPLOADED\n", info.read_text())
            self.assertEqual(len(list(info.parent.glob("*.apk"))), 0)
            self.assertEqual(len(list(info.parent.glob("*.aab"))), 0)

    def test_push_android_with_push_ios_builds_android_and_ios_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--push-android", "--push-ios"])
            result = subprocess.run(["/bin/bash", "release.sh", "--push-android", "--push-ios"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            self.assertIn("apple ios 1.0.1+10", calls)
            self.assertNotIn("apple macos", calls)
            self.assertIn("python -u scripts/play_upload.py", calls)
            self.assertIn("python -u scripts/appstore_upload.py", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt"))
            self.assertIn("websiteStatus=CONFIRMED\n", info.read_text())
            self.assertIn("playStatus=COMMITTED|test-edit\n", info.read_text())
            self.assertIn("appstoreStatus=UPLOADED|", info.read_text())
            self.assertEqual(len(list(info.parent.glob("*.apk"))), 2)
            self.assertEqual(len(list(info.parent.glob("*.aab"))), 2)

    def test_push_mobile_uploads_google_play_and_app_store(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--push-mobile"])
            result = subprocess.run(["/bin/bash", "release.sh", "--push-mobile"], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (root / "calls").read_text()
            self.assertIn("apple ios 1.0.1+10", calls)
            self.assertNotIn("apple macos", calls)
            self.assertIn("python -u scripts/play_upload.py", calls)
            self.assertIn("python -u scripts/appstore_upload.py", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt")).read_text()
            self.assertIn("websiteStatus=CONFIRMED\n", info)
            self.assertIn("playStatus=COMMITTED|test-edit\n", info)
            self.assertIn("appstoreStatus=UPLOADED|", info)

    def test_ios_upload_failure_is_recorded(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--push-ios"], appstore_failure=True)
            result = subprocess.run(["/bin/bash", "release.sh", "--push-ios"], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("App Store Connect 上传未完成", result.stderr)
            self.assertIn("失败原因：App Store Connect 上传未完成", result.stdout)
            info = next((root / "release-artifacts").rglob("release-info.txt")).read_text()
            self.assertIn("appstoreStatus=FAILED\n", info)

    def test_push_ios_requires_ios_platform(self):
        result = subprocess.run(["/bin/bash", str(RELEASE_SCRIPT), "--platform", "android",
                                 "--push-ios"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("App Store Connect 上传需要构建 iOS", result.stderr)

    def test_push_ios_stops_when_ios_is_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--platform", "all", "--push-ios"],
                                               ios_signing=False)
            result = subprocess.run(["/bin/bash", "release.sh", "--platform", "all", "--push-ios"],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("无法上传 App Store Connect", result.stderr)

    def test_ios_is_skipped_when_no_distribution_certificate(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, [], ios_signing=False)
            result = subprocess.run(["/bin/bash", "release.sh"], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("跳过 iOS", result.stdout)
            self.assertIn("iOS / Apple Watch：跳过", result.stdout)
            calls = (root / "calls").read_text()
            self.assertIn("apple macos 1.0.1+10", calls)
            self.assertNotIn("apple ios", calls)
            info = next((root / "release-artifacts").rglob("release-info.txt")).read_text()
            self.assertIn("iosWatchStatus=SKIPPED\n", info)
            self.assertIn("buildStatus=COMPLETE\n", info)

    def test_explicit_ios_without_distribution_certificate_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.mock_release_root(directory, ["--platform", "ios"], ios_signing=False)
            result = subprocess.run(["/bin/bash", "release.sh", "--platform", "ios"], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("没有 iOS Distribution 证书", result.stderr)

    def test_invalid_platform_and_incompatible_modes_stop_before_build(self):
        for flags in (["--platform", "windows"], ["--test", "--platform", "all"],
                      ["--platform", "ios", "--push-android"],
                      ["--platform", "android", "--push-ios"],
                      ["--platform", "macos", "--push-ios"]):
            result = subprocess.run(["/bin/bash", str(RELEASE_SCRIPT), *flags],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)

    def test_test_packages_cannot_be_published(self):
        for flag in ("--push-android", "--push-website", "--push-ios", "--push-mobile"):
            result = subprocess.run(["/bin/bash", str(RELEASE_SCRIPT), "--test", flag],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("不可发布", result.stderr)


if __name__ == "__main__":
    unittest.main()
