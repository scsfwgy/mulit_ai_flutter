import contextlib
import io
from argparse import Namespace
from pathlib import Path
import plistlib
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
            apk = root / "build/wear/outputs/apk/debug/wear-debug.apk"
            apk.parent.mkdir(parents=True)
            apk.touch()
            with patch.object(installer, "ROOT", root), patch.object(installer, "run") as run:
                artifacts = installer.build([self.devices[1]] * 2, "profile", None)
            self.assertEqual(artifacts, {("android", "watch"): apk})
            run.assert_called_once_with([root / "android/gradlew", "-p", root / "android", ":wear:assembleDebug"])

    def make_apple_artifacts(self, root, companion=installer.PHONE_ID):
        phone = root / "build/ios/iphoneos/Runner.app"
        watch = phone / "Watch/AILinkWatch.app"
        for path, identifier in ((phone, installer.PHONE_ID), (watch, installer.WATCH_ID)):
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
                    self.assertEqual(argv, ["flutter", "build", "ios", "--profile"])
                    config = Path(kwargs["env"]["XCODE_XCCONFIG_FILE"])
                    self.assertIn("DEVELOPMENT_TEAM = ABCDE12345", config.read_text())
                    configs.append(config)
                    self.make_apple_artifacts(root)
            with patch.object(installer, "ROOT", root), patch.object(installer, "run", side_effect=command) as run:
                artifacts = installer.build(self.devices[2:] * 2, "profile", "ABCDE12345")
            self.assertEqual(run.call_count, 2)  # One Flutter build and one signature verification.
            self.assertEqual(set(artifacts), {("ios", "phone"), ("ios", "watch")})
        self.assertFalse(configs[0].exists())

    def test_apple_companion_mismatch_stops_before_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_apple_artifacts(root, companion="wrong.phone")
            with patch.object(installer, "ROOT", root), patch.object(installer, "run"), self.assertRaisesRegex(ValueError, "配套手机标识"):
                installer.build(self.devices[2:], "profile", "ABCDE12345")

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
        with patch("sys.argv", ["install-dev.sh", "--select", "1,2"]), \
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


if __name__ == "__main__":
    unittest.main()
