import io
import json
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

import appstore_upload as upload


class AppStorePreflightTest(unittest.TestCase):
    token = 'eyJ0ZXN0.fakepayload.fakesignature'

    def test_checks_exact_app_using_bearer_token_without_logging_it(self):
        result = {'data': [{'attributes': {'bundleId': upload.BUNDLE_ID}}]}
        with patch.object(upload.urllib.request, 'build_opener') as opener:
            opener.return_value.open.return_value = io.BytesIO(json.dumps(result).encode())
            upload.check_app_access(self.token)
        request = opener.return_value.open.call_args.args[0]
        self.assertEqual(request.headers['Authorization'], 'Bearer ' + self.token)
        self.assertEqual(request.full_url,
                         'https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=com.maxhall.ailink&limit=1')
        self.assertEqual(opener.return_value.open.call_args.kwargs['timeout'], 30)
        self.assertIsInstance(opener.call_args.args[0], upload._NoRedirect)

    def test_missing_agreement_reports_account_holder_action_without_raw_response(self):
        body = {'errors': [{'code': 'FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED',
                            'detail': 'unsafe echo ' + self.token}]}
        error = urllib.error.HTTPError('https://api.appstoreconnect.apple.com', 403,
                                      'Forbidden', {}, io.BytesIO(json.dumps(body).encode()))
        with patch.object(upload.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = error
            with self.assertRaises(ValueError) as raised:
                upload.check_app_access(self.token)
        self.assertIn('Account Holder', str(raised.exception))
        self.assertIn('协议', str(raised.exception))
        self.assertNotIn(self.token, str(raised.exception))
        self.assertNotIn('unsafe echo', str(raised.exception))

    def test_other_http_errors_remain_failures(self):
        for status, expected in [(401, '认证失败'), (403, '权限不足'), (429, 'HTTP 429'),
                                 (503, 'HTTP 503'), (307, 'HTTP 307')]:
            with self.subTest(status=status), patch.object(upload.urllib.request, 'build_opener') as opener:
                opener.return_value.open.side_effect = urllib.error.HTTPError(
                    'https://api.appstoreconnect.apple.com', status, 'error', {},
                    io.BytesIO(self.token.encode()))
                with self.assertRaises(ValueError) as raised:
                    upload.check_app_access(self.token)
                self.assertIn(expected, str(raised.exception))
                self.assertNotIn(self.token, str(raised.exception))

    def test_missing_app_or_invalid_response_cannot_pass_preflight(self):
        for body in [b'{"data":[]}', b'{"data":[{"attributes":{"bundleId":"other.app"}}]}',
                     b'{"errors":[]}', b'not json', b'[]']:
            with self.subTest(body=body), patch.object(upload.urllib.request, 'build_opener') as opener:
                opener.return_value.open.return_value = io.BytesIO(body)
                with self.assertRaises(ValueError):
                    upload.check_app_access(self.token)

    def test_network_errors_hide_transport_details(self):
        with patch.object(upload.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = urllib.error.URLError(self.token)
            with self.assertRaisesRegex(ValueError, '检查网络与 HTTP 代理') as raised:
                upload.check_app_access(self.token)
        self.assertNotIn(self.token, str(raised.exception))

    def test_redirects_never_forward_authorization(self):
        self.assertIsNone(upload._NoRedirect().redirect_request(
            None, None, 307, 'redirect', {}, 'https://other.example'))

    def test_online_check_uses_generated_jwt_and_hides_auth_output(self):
        stream = io.StringIO()
        with patch.object(upload, 'settings', return_value=('key', 'issuer', Path('/fake/key.p8'))), \
             patch.object(upload, 'find_altool', return_value=Path('/fake/altool')), \
             patch.object(upload, 'run_altool', return_value=(0, 'JWT: ' + self.token)) as altool, \
             patch.object(upload, 'check_app_access') as check, redirect_stdout(stream):
            self.assertEqual(upload.main(['--check-online']), 0)
        check.assert_called_once_with(self.token)
        self.assertEqual(altool.call_count, 1)
        self.assertFalse(altool.call_args.kwargs['echo'])
        self.assertIn('App 访问校验通过', stream.getvalue())
        self.assertNotIn(self.token, stream.getvalue())

    def test_online_failure_exits_nonzero_and_keeps_jwt_hidden(self):
        stream = io.StringIO()
        with patch.object(upload, 'settings', return_value=('key', 'issuer', Path('/fake/key.p8'))), \
             patch.object(upload, 'find_altool', return_value=Path('/fake/altool')), \
             patch.object(upload, 'run_altool', return_value=(0, 'JWT: ' + self.token)), \
             patch.object(upload, 'check_app_access', side_effect=ValueError('需要接受协议')), \
             redirect_stdout(stream), redirect_stderr(stream):
            self.assertEqual(upload.main(['--check-online']), 1)
        self.assertIn('APPSTORE_UPLOAD_STATUS=FAIL|需要接受协议', stream.getvalue())
        self.assertNotIn(self.token, stream.getvalue())

    def test_local_check_does_not_access_network(self):
        with patch.object(upload, 'settings', return_value=('key', 'issuer', Path('/fake/key.p8'))), \
             patch.object(upload, 'find_altool', return_value=Path('/fake/altool')), \
             patch.object(upload, 'run_altool', return_value=(0, 'JWT: ' + self.token)), \
             patch.object(upload, 'check_app_access') as check, redirect_stdout(io.StringIO()):
            self.assertEqual(upload.main(['--check']), 0)
        check.assert_not_called()


if __name__ == '__main__':
    unittest.main()
