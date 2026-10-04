import hashlib
import json
import os
import tempfile
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError

import website_release as publisher

CONFIG = {"access_key_id": "test-id", "access_key_secret": "test-secret",
          "bucket": "test", "endpoint": "https://oss.example.com", "cdn_domain": "cdn.example.com"}
PAYLOAD = {"version": "1.0.1-abcd1234", "versionCode": 10, "wearVersionCode": 1000010,
           "downloadUrl": "https://cdn.example.com/phone.apk", "wearDownloadUrl": "https://cdn.example.com/wear.apk"}


class WebsiteReleaseTest(unittest.TestCase):
    def test_settings_reject_tools24_endpoint_and_preserve_local_config(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            root = Path(directory)
            config = root / "oss.json"
            config.write_text(json.dumps(CONFIG))
            env_file = root / ".env.local"
            env_file.write_text(f"RELEASE_ADMIN_TOKEN=test-token\nOSS_CONFIG_FILE={config}\n")
            endpoint, token, loaded = publisher.settings(env_file)
            self.assertEqual(endpoint, publisher.DEFAULT_ENDPOINT)
            self.assertEqual(token, "test-token")
            self.assertEqual(loaded, CONFIG)
            with patch.dict(os.environ, {"WEBSITE_RELEASE_URL": "https://www.tools24.uk/api/v1/app/release"}):
                with self.assertRaises(ValueError):
                    publisher.settings(env_file)

    def test_two_verified_uploads_are_required_before_publish(self):
        for bad_etag in (False, True):
            with self.subTest(bad_etag=bad_etag), tempfile.TemporaryDirectory() as directory:
                phone, wear = (Path(directory) / name for name in ("AI-Link-phone-1.apk", "AI-Link-wear-1.apk"))
                phone.write_bytes(b"phone APK")
                wear.write_bytes(b"wear APK")
                uploads = []
                def put(key, path, headers):
                    uploads.append(key)
                    return SimpleNamespace(etag="wrong" if bad_etag and len(uploads) == 2
                                           else hashlib.md5(Path(path).read_bytes()).hexdigest())
                bucket = SimpleNamespace(put_object_from_file=put)
                sdk = SimpleNamespace(Auth=lambda *args: None, Bucket=lambda *args: bucket)
                with patch.dict("sys.modules", {"oss2": sdk}), patch.object(publisher, "publish") as publish:
                    if bad_etag:
                        with self.assertRaises(ValueError):
                            publisher.release("endpoint", "token", CONFIG, phone, wear, "1.0.1-abcd", 10, 1000010)
                        publish.assert_not_called()
                    else:
                        data = publisher.release("endpoint", "token", CONFIG, phone, wear, "1.0.1-abcd", 10, 1000010)
                        self.assertEqual(len(uploads), 2)
                        self.assertTrue(all(key.startswith("ai-link/release/") for key in uploads))
                        self.assertTrue(data["wearDownloadUrl"].endswith(wear.name))
                        publish.assert_called_once_with("endpoint", "token", data)

    def test_put_get_readback_and_redirect_secret_protection(self):
        for mode in ("success", "mismatch", "redirect"):
            with self.subTest(mode=mode):
                seen = []
                class Handler(BaseHTTPRequestHandler):
                    def log_message(self, *args):
                        pass
                    def do_PUT(self):
                        seen.append((self.path, self.headers.get("X-Admin-Token")))
                        self.rfile.read(int(self.headers.get("Content-Length", "0")))
                        if mode == "redirect":
                            self.send_response(307)
                            self.send_header("Location", "/other")
                            self.end_headers()
                        else:
                            self.send_response(200)
                            self.end_headers()
                            self.wfile.write(json.dumps({"ok": True, "data": PAYLOAD}).encode())
                    def do_GET(self):
                        seen.append((self.path, self.headers.get("X-Admin-Token")))
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(json.dumps({"ok": True, "data": PAYLOAD if mode == "success" else {}}).encode())
                server = HTTPServer(("127.0.0.1", 0), Handler)
                thread = Thread(target=server.serve_forever, daemon=True)
                thread.start()
                try:
                    endpoint = f"http://127.0.0.1:{server.server_port}/api/v1/ai-link/release"
                    if mode == "success":
                        publisher.publish(endpoint, "secret", PAYLOAD)
                        self.assertEqual(seen[-1][1], None)
                    else:
                        with self.assertRaises(HTTPError if mode == "redirect" else ValueError):
                            publisher.publish(endpoint, "secret", PAYLOAD)
                    self.assertTrue(all(path == "/api/v1/ai-link/release" for path, _ in seen))
                    self.assertEqual(seen[0][1], "secret")
                finally:
                    server.shutdown()
                    thread.join(timeout=5)
                    server.server_close()


if __name__ == "__main__":
    unittest.main()
