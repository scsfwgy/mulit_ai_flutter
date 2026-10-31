import contextlib
import io
from argparse import Namespace
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import install_dev as installer


class InstallDevTest(unittest.TestCase):
    def setUp(self):
        self.devices = [
            installer.Device("android", "phone", "phone-a", "Phone A"),
            installer.Device("android", "watch", "watch-a", "Watch A"),
            installer.Device("ios", "phone", "iphone-a", "iPhone A"),
            installer.Device("ios", "watch", "apple-watch-a", "Apple Watch A"),
        ]

    def make_mac_app(self, path, identifier=installer.MACOS_ID):
        (path / "Contents").mkdir(parents=True)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))

    def test_mac_discovery_and_phone_filter(self):
        with patch.object(installer.sys, "platform", "darwin"):
            devices = installer.discover("macos", "desktop")
            self.assertEqual(devices, [installer.Device("macos", "desktop", "macos", "本机 Mac")])
            self.assertEqual(installer.discover("macos", "phone"), [])
        with patch.object(installer.sys, "platform", "linux"), self.assertRaisesRegex(ValueError, "只能在 Mac"):
            installer.discover("macos", "all")

    def test_mac_build_once_checks_identity_and_signature(self):
        mac = installer.Device("macos", "desktop", "macos", "Mac")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / "build/macos/Build/Products/Debug/AI Link.app"
            self.make_mac_app(app)
            with patch.object(installer, "ROOT", root), patch.object(installer, "run") as command:
                self.assertEqual(installer.build([mac, mac], "debug", None), {("macos", "desktop"): app})
                self.assertEqual(command.call_args_list[0].args[0], ["flutter", "build", "macos", "--debug"])
                self.assertEqual(command.call_args_list[1].args[0], ["codesign", "--verify", "--deep", "--strict", app])

    def test_mac_install_replaces_bundle_and_keeps_other_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source/AI Link.app"
            directory = root / "Applications"
            target = directory / "AI Link.app"
            self.make_mac_app(source)
            self.make_mac_app(target)
            (source / "new-build").touch()
            (target / "old-build").touch()
            (directory / "unrelated.txt").write_text("keep")
            def command(argv, **kwargs):
                if argv[0] == "ditto":
                    shutil.copytree(argv[1], argv[2])
            with patch.object(installer, "run", side_effect=command):
                self.assertEqual(installer.install_macos(source, directory), target.resolve())
            self.assertTrue((target / "new-build").exists())
            self.assertFalse((target / "old-build").exists())
            self.assertEqual((directory / "unrelated.txt").read_text(), "keep")
            self.assertFalse(list(directory.glob(".ai-link-update-*")))

    def test_mac_install_rejects_foreign_app_and_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "Applications/AI Link.app"
            self.make_mac_app(target, "another.app")
            with patch.object(installer, "run") as command, self.assertRaisesRegex(ValueError, "其他应用"):
                installer.install_macos(root / "source.app", target.parent)
            command.assert_not_called()
            shutil.rmtree(target)
            target.symlink_to(root / "source.app")
            with self.assertRaisesRegex(ValueError, "符号链接"):
                installer.install_macos(root / "source.app", target.parent)

    def test_mac_install_rolls_back_if_replacement_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, target = root / "source.app", root / "Applications/AI Link.app"
            self.make_mac_app(source)
            self.make_mac_app(target)
            (target / "old-build").touch()
            rename = Path.rename
            def command(argv, **kwargs):
                if argv[0] == "ditto": shutil.copytree(argv[1], argv[2])
            def fail_replacement(path, destination):
                if path.name == "AI Link.app" and path.parent.name.startswith(".ai-link-update-"):
                    raise OSError("simulated replacement failure")
                return rename(path, destination)
            with patch.object(installer, "run", side_effect=command), patch.object(Path, "rename", fail_replacement), self.assertRaises(OSError):
                installer.install_macos(source, target.parent)
            self.assertTrue((target / "old-build").exists())

    def test_mac_cli_installs_to_chosen_directory_and_launches_only_when_requested(self):
        mac = installer.Device("macos", "desktop", "macos", "Mac")
        for launch in (False, True):
            argv = ["install-dev.sh", "--platform", "macos", "--device", "macos", "--macos-dir", "/tmp/mac-apps"] + (["--launch"] if launch else [])
            with patch("sys.argv", argv), patch.object(installer, "discover", return_value=[mac]), \
                 patch.object(installer.shutil, "which", return_value="tool"), \
                 patch.object(installer, "build", return_value={("macos", "desktop"): Path("built.app")}) as build, \
                 patch.object(installer, "install_macos", return_value=Path("/tmp/mac-apps/AI Link.app")) as install, \
                 patch.object(installer, "run") as command, contextlib.redirect_stdout(io.StringIO()):
                installer.main()
            build.assert_called_once_with([mac], "release", None)
            install.assert_called_once_with(Path("built.app"), "/tmp/mac-apps")
            if launch:
                command.assert_called_once_with(["open", "-a", Path("/tmp/mac-apps/AI Link.app")])
            else:
                command.assert_not_called()

    def test_multiple_indices_preserve_selection_and_deduplicate(self):
        self.assertEqual(installer.select_indices("4，1 4", self.devices), [self.devices[3], self.devices[0]])
        self.assertEqual(installer.select_indices("all", self.devices), self.devices)
        for invalid in ("", "0", "5", "1,b", "-1", "1;2"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                installer.select_indices(invalid, self.devices)

    def test_current_and_legacy_apple_inventory_excludes_simulators_and_disconnected(self):
        current = {
            "identifier": "core-id",
            "properties": {
                "hardware": {"reality": "physical", "platform": "watchOS", "udid": "watch-udid"},
                "connection": {"state": "connected"}, "state": {"name": "Watch"},
            },
        }
        legacy = {
            "identifier": "legacy-id",
            "hardwareProperties": {"reality": "physical", "platform": "iOS", "udid": "phone-udid"},
            "connectionProperties": {"tunnelState": "connected"}, "deviceProperties": {"name": "Phone"},
        }
        simulator = {**legacy, "hardwareProperties": {"reality": "simulated", "platform": "iOS"}}
        offline = {**legacy, "connectionProperties": {"tunnelState": "disconnected"}}
        result = installer.parse_apple_devices({"result": {"devices": [current, legacy, simulator, offline]}})
        self.assertEqual([(d.identifier, d.kind) for d in result], [("watch-udid", "watch"), ("phone-udid", "phone")])

    def test_android_absent_watch_feature_is_a_phone_even_with_exit_one(self):
        def adb(command, **kwargs):
            if command == ["adb", "devices"]:
                return "List of devices attached\nphone-a\tdevice\nwatch-a\tdevice\nlocked\tunauthorized\n"
            if "has-feature" in command:
                if command[2] == "phone-a":
                    raise subprocess.CalledProcessError(1, command, output="false\r\n")
                return "true\r\n"
            return "Model\r\n"
        with patch.object(installer, "run", side_effect=adb), contextlib.redirect_stderr(io.StringIO()):
            devices = installer.android_devices()
        self.assertEqual([(d.identifier, d.kind) for d in devices], [("phone-a", "phone"), ("watch-a", "watch")])

    def test_legacy_android_serials_still_select_phone_and_watch(self):
        args = Namespace(legacy_serials=["phone-a", "watch-a"], device=None, select=None, all=False)
        self.assertEqual(installer.select_devices(args, self.devices), self.devices[:2])
        args.legacy_serials.reverse()
        with self.assertRaises(ValueError):
            installer.select_devices(args, self.devices)

    def test_wear_only_build_does_not_build_phone(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            apk = root / "build/wear/outputs/apk/release/wear-release.apk"
            apk.parent.mkdir(parents=True)
            apk.touch()
            with patch.object(installer, "ROOT", root), patch.object(installer, "run") as run:
                artifacts = installer.build([self.devices[1]] * 2, "release", None)
            self.assertEqual(artifacts, {("android", "watch"): apk})
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0], [root / "android/gradlew", "-p", root / "android", ":wear:assembleRelease"])
            self.assertEqual(run.call_args.kwargs["env"]["AI_LINK_SIGNING_PROFILE"], "release")

    def test_android_phone_and_watch_use_the_same_explicit_mode_and_signing_profile(self):
        for mode, profile in (("release", "release"), ("debug", "test")):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                phone = root / f"build/app/outputs/flutter-apk/app-{mode}.apk"
                watch = root / f"build/wear/outputs/apk/{mode}/wear-{mode}.apk"
                for artifact in (phone, watch):
                    artifact.parent.mkdir(parents=True)
                    artifact.touch()
                with patch.object(installer, "ROOT", root), \
                     patch.dict(installer.os.environ, {"AI_LINK_SIGNING_PROFILE": "test"}), \
                     patch.object(installer, "run") as command:
                    artifacts = installer.build(self.devices[:2] * 2, mode, None)
                self.assertEqual(artifacts, {("android", "phone"): phone, ("android", "watch"): watch})
                self.assertEqual(command.call_count, 2)
                self.assertEqual(command.call_args_list[0].args[0], ["flutter", "build", "apk", f"--{mode}"])
                self.assertEqual(command.call_args_list[1].args[0], [root / "android/gradlew", "-p", root / "android", f":wear:assemble{mode.capitalize()}"])
                for call in command.call_args_list:
                    self.assertEqual(call.kwargs["env"]["AI_LINK_SIGNING_PROFILE"], profile)

    def test_android_cli_defaults_to_release_and_debug_is_opt_in(self):
        for flags, mode in (([], "release"), (["--mode", "debug"], "debug")):
            with self.subTest(mode=mode), \
                 patch("sys.argv", ["install-dev.sh", "--device", "phone-a"] + flags), \
                 patch.object(installer, "discover", return_value=self.devices), \
                 patch.object(installer.shutil, "which", return_value="tool"), \
                 patch.object(installer, "build", return_value={("android", "phone"): Path("phone.apk")}) as build, \
                 patch.object(installer, "run") as command, contextlib.redirect_stdout(io.StringIO()):
                installer.main()
            build.assert_called_once_with([self.devices[0]], mode, None)
            command.assert_called_once_with(["adb", "-s", "phone-a", "install", "-r", Path("phone.apk")])

    def test_one_mode_builds_all_selected_platforms_consistently(self):
        mac = installer.Device("macos", "desktop", "macos", "Mac")
        for mode in ("release", "debug"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                phone = root / f"build/app/outputs/flutter-apk/app-{mode}.apk"
                watch = root / f"build/wear/outputs/apk/{mode}/wear-{mode}.apk"
                for artifact in (phone, watch):
                    artifact.parent.mkdir(parents=True)
                    artifact.touch()
                self.make_mac_app(root / "build/macos/Build/Products" / mode.capitalize() / "AI Link.app")
                self.make_apple_artifacts(root, phone_id=installer.apple_bundle_ids(mode)[0])
                with patch.object(installer, "ROOT", root), patch.object(installer, "run") as command:
                    artifacts = installer.build(self.devices + [mac], mode, "ABCDE12345")
                self.assertEqual(len(artifacts), 5)
                builds = [call.args[0] for call in command.call_args_list
                          if call.args[0][:2] == ["flutter", "build"]]
                self.assertEqual(builds, [["flutter", "build", platform, f"--{mode}"]
                                          for platform in ("apk", "ios", "macos")])

    def make_apple_artifacts(self, root, companion=None, phone_id=installer.PHONE_ID):
        phone = root / "build/ios/iphoneos/Runner.app"
        watch = phone / "Watch/AILinkWatch.app"
        widget = watch / "PlugIns/AILinkWatchWidgets.appex"
        share = phone / "PlugIns/AILinkShare.appex"
        watch_id = phone_id + ".watchkitapp"
        companion = phone_id if companion is None else companion
        for path, identifier in ((phone, phone_id), (watch, watch_id),
                                 (widget, watch_id + ".widgets"),
                                 (share, phone_id + ".share")):
            path.mkdir(parents=True, exist_ok=True)
            info = {"CFBundleIdentifier": identifier}
            if path == watch:
                info["WKCompanionAppBundleIdentifier"] = companion
            (path / "Info.plist").write_bytes(plistlib.dumps(info))

    def test_multiple_apple_devices_build_once_and_use_temporary_team_override(self):
        configs = []
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def command(argv, **kwargs):
                if argv[0] == "flutter":
                    self.assertEqual(argv, ["flutter", "build", "ios", "--debug"])
                    config = Path(kwargs["env"]["XCODE_XCCONFIG_FILE"])
                    self.assertIn("DEVELOPMENT_TEAM = ABCDE12345", config.read_text())
                    self.assertNotIn("CODE_SIGN_STYLE", config.read_text())
                    configs.append(config)
                    self.make_apple_artifacts(root)
            with patch.object(installer, "ROOT", root), patch.object(installer, "run", side_effect=command) as run:
                artifacts = installer.build(self.devices[2:] * 2, "debug", "ABCDE12345")
            self.assertEqual(run.call_count, 2)  # One Flutter build and one signature verification.
            self.assertEqual(set(artifacts), {("ios", "phone"), ("ios", "watch")})
        self.assertFalse(configs[0].exists())

    def test_apple_companion_mismatch_stops_before_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_apple_artifacts(root, companion="wrong.phone")
            with patch.object(installer, "ROOT", root), patch.object(installer, "run"), self.assertRaisesRegex(ValueError, "配套手机标识"):
                installer.build(self.devices[2:], "debug", "ABCDE12345")

    def test_release_build_requires_the_official_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)

            def command(argv, **kwargs):
                if argv[0] == "flutter":
                    self.assertEqual(argv, ["flutter", "build", "ios", "--release"])
                    self.make_apple_artifacts(
                        root,
                        companion=installer.RELEASE_PHONE_ID,
                        phone_id=installer.RELEASE_PHONE_ID,
                    )

            with patch.object(installer, "ROOT", root), patch.object(installer, "run", side_effect=command):
                artifacts = installer.build(self.devices[2:], "release", "ABCDE12345")
            self.assertEqual(set(artifacts), {("ios", "phone"), ("ios", "watch")})

    def test_debug_bundle_is_rejected_for_the_default_release_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_apple_artifacts(root)
            with patch.object(installer, "ROOT", root), patch.object(installer, "run"), self.assertRaisesRegex(ValueError, "正式版"):
                installer.build(self.devices[2:], "release", "ABCDE12345")

    def test_release_widget_in_debug_bundle_stops_before_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_apple_artifacts(root)
            plist = root / "build/ios/iphoneos/Runner.app/Watch/AILinkWatch.app/PlugIns/AILinkWatchWidgets.appex/Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.maxhall.ailink.watchkitapp.widgets"}))
            with patch.object(installer, "ROOT", root), patch.object(installer, "run"), self.assertRaisesRegex(ValueError, "开发版"):
                installer.build(self.devices[2:], "debug", "ABCDE12345")

    def test_release_share_extension_in_debug_bundle_stops_before_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_apple_artifacts(root)
            plist = root / "build/ios/iphoneos/Runner.app/PlugIns/AILinkShare.appex/Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.maxhall.ailink.share"}))
            with patch.object(installer, "ROOT", root), patch.object(installer, "run"), self.assertRaisesRegex(ValueError, "开发版"):
                installer.build(self.devices[2:], "debug", "ABCDE12345")

    def test_cli_installs_only_selected_devices_after_build(self):
        events = []
        def build(selected, mode, team):
            events.append("built")
            self.assertEqual(selected, [self.devices[3], self.devices[0]])
            return {("android", "phone"): Path("phone.apk"), ("ios", "watch"): Path("watch.app")}
        def run(command, **kwargs):
            self.assertEqual(events[0], "built")
            events.append(command)
        with patch("sys.argv", ["install-dev.sh", "--select", "4,1"]), \
             patch.object(installer, "discover", return_value=self.devices), \
             patch.object(installer.shutil, "which", return_value="tool"), \
             patch.object(installer, "development_team", return_value="ABCDE12345"), \
             patch.object(installer, "build", side_effect=build), \
             patch.object(installer, "run", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            installer.main()
        self.assertEqual(events[1], ["adb", "-s", "phone-a", "install", "-r", Path("phone.apk")])
        self.assertEqual(events[2], ["xcrun", "devicectl", "device", "install", "app", "--device", "apple-watch-a", Path("watch.app")])

    def test_invalid_selection_does_not_build_or_install(self):
        with patch("sys.argv", ["install-dev.sh", "--select", "99"]), \
             patch.object(installer, "discover", return_value=self.devices), \
             patch.object(installer, "build") as build, patch.object(installer, "run") as run, \
             contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ValueError):
            installer.main()
        build.assert_not_called()
        run.assert_not_called()

    def test_install_failure_stops_and_reports_successful_devices(self):
        artifacts = {("android", "phone"): Path("phone.apk"), ("android", "watch"): Path("watch.apk")}
        output = io.StringIO()
        with patch("sys.argv", ["install-dev.sh", "--select", "1,2", "--mode", "debug"]), \
             patch.object(installer, "discover", return_value=self.devices), \
             patch.object(installer.shutil, "which", return_value="tool"), \
             patch.object(installer, "build", return_value=artifacts), \
             patch.object(installer, "run", side_effect=[None, subprocess.CalledProcessError(1, "adb")]) as run, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(output), \
             self.assertRaises(subprocess.CalledProcessError):
            installer.main()
        self.assertEqual(run.call_count, 2)
        self.assertIn("此前已安装成功：Phone A", output.getvalue())
        self.assertIn("--device watch-a", output.getvalue())
        self.assertIn("--mode debug", output.getvalue())


if __name__ == "__main__":
    unittest.main()
