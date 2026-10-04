import tempfile
import unittest
import io
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import MagicMock

from play_upload import require_tracks, upload_to_edit


class PlayUploadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.phone = Path(self.temp.name) / "phone.aab"
        self.wear = Path(self.temp.name) / "wear.aab"
        self.phone.write_bytes(b"phone")
        self.wear.write_bytes(b"wear")
        self.service = MagicMock()
        self.service.edits.return_value.insert.return_value.execute.return_value = {
            "id": "edit-1"
        }
        self.service.edits.return_value.tracks.return_value.list.return_value.execute.return_value = {
            "tracks": [{"track": "internal"}, {"track": "wear:internal"}]
        }

    def test_phone_and_wear_use_distinct_tracks_in_one_edit(self):
        self.service.edits.return_value.bundles.return_value.upload.return_value.execute.side_effect = [
            {"versionCode": 7},
            {"versionCode": 1000007},
        ]
        edit_id, codes = upload_to_edit(
            self.service,
            self.phone,
            self.wear,
            7,
            1000007,
            "internal",
            [{"language": "en-US", "text": "Initial test"}],
            lambda *args, **kwargs: object(),
        )
        self.assertEqual(edit_id, "edit-1")
        self.assertEqual(codes, {"phone": 7, "wear": 1000007})
        updates = self.service.edits.return_value.tracks.return_value.update.call_args_list
        self.assertEqual([call.kwargs["track"] for call in updates], ["internal", "wear:internal"])
        self.assertEqual(
            [call.kwargs["body"]["releases"][0]["versionCodes"] for call in updates],
            [["7"], ["1000007"]],
        )
        self.service.edits.return_value.validate.assert_called_once()
        self.service.edits.return_value.commit.assert_called_once()

    def test_wrong_wear_version_discards_edit_without_commit(self):
        self.service.edits.return_value.bundles.return_value.upload.return_value.execute.side_effect = [
            {"versionCode": 7},
            {"versionCode": 42},
        ]
        with self.assertRaisesRegex(ValueError, "wear AAB versionCode 不符"):
            upload_to_edit(
                self.service,
                self.phone,
                self.wear,
                7,
                1000007,
                "internal",
                [],
                lambda *args, **kwargs: object(),
            )
        self.service.edits.return_value.tracks.return_value.update.assert_not_called()
        self.service.edits.return_value.commit.assert_not_called()
        self.service.edits.return_value.delete.assert_called_once()

    def test_missing_wear_track_stops_before_upload(self):
        self.service.edits.return_value.tracks.return_value.list.return_value.execute.return_value = {
            "tracks": [{"track": "internal"}]
        }
        with self.assertRaisesRegex(RuntimeError, "尚未提供 Wear OS wear:internal"):
            upload_to_edit(
                self.service,
                self.phone,
                self.wear,
                7,
                1000007,
                "internal",
                [],
                lambda *args, **kwargs: object(),
            )
        self.service.edits.return_value.bundles.return_value.upload.assert_not_called()
        self.service.edits.return_value.delete.assert_called_once()

    def test_missing_wear_alpha_stops_before_upload_or_creation(self):
        self.service.edits.return_value.tracks.return_value.list.return_value.execute.return_value = {
            "tracks": [{"track": "alpha"}]
        }
        with self.assertRaisesRegex(RuntimeError, "--wear-track"):
            upload_to_edit(
                self.service, self.phone, self.wear, 7, 1000007,
                "alpha", [], lambda *args, **kwargs: object(),
            )
        self.service.edits.return_value.tracks.return_value.create.assert_not_called()
        self.service.edits.return_value.bundles.return_value.upload.assert_not_called()
        self.service.edits.return_value.commit.assert_not_called()
        self.service.edits.return_value.delete.assert_called_once()

    def test_explicit_wear_track_does_not_change_phone_destination(self):
        wear_track = "wear:手表内部测试V2"
        self.service.edits.return_value.tracks.return_value.list.return_value.execute.return_value = {
            "tracks": [{"track": "alpha"}, {"track": wear_track}]
        }
        self.service.edits.return_value.bundles.return_value.upload.return_value.execute.side_effect = [
            {"versionCode": 7}, {"versionCode": 1000007},
        ]
        upload_to_edit(
            self.service,
            self.phone,
            self.wear,
            7,
            1000007,
            "alpha",
            [],
            lambda *args, **kwargs: object(),
            wear_track=wear_track,
        )
        self.assertEqual(
            [call.kwargs["track"] for call in self.service.edits.return_value.tracks.return_value.update.call_args_list],
            ["alpha", wear_track],
        )
        self.service.edits.return_value.commit.assert_called_once()

    def test_validation_failure_identifies_stage_and_never_commits(self):
        self.service.edits.return_value.bundles.return_value.upload.return_value.execute.side_effect = [
            {"versionCode": 7}, {"versionCode": 1000007},
        ]
        self.service.edits.return_value.validate.return_value.execute.side_effect = RuntimeError("HTTP 500")
        output = io.StringIO()
        with redirect_stderr(output), self.assertRaisesRegex(RuntimeError, "HTTP 500"):
            upload_to_edit(
                self.service, self.phone, self.wear, 7, 1000007,
                "internal", [], lambda *args, **kwargs: object(),
            )
        self.assertIn("edits.validate", output.getvalue())
        self.assertIn("editId=edit-1", output.getvalue())
        self.service.edits.return_value.commit.assert_not_called()
        self.service.edits.return_value.delete.assert_called_once()

    def test_invalid_wear_track_is_rejected(self):
        for name in ("alpha", "wear:", "wear:  "):
            with self.subTest(name=name), self.assertRaises(ValueError):
                require_tracks(self.service, "edit-1", "internal", name)


if __name__ == "__main__":
    unittest.main()
