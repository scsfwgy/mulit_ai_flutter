#!/usr/bin/env python3
"""Exercise watch Swift adapters against local fixtures; no real keys or services."""
import base64
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]

class Handler(BaseHTTPRequestHandler):
    redirected = False
    searches = 0
    grounded = 0

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        payload = {} if 'multipart/' in self.headers.get('Content-Type', '') else json.loads(body)
        if self.path.startswith('/search/'):
            service = self.path.rsplit('/', 1)[-1]
            assert self.headers.get('x-api-key' if service == 'exa' else 'Authorization') == ('watch-search-key' if service == 'exa' else 'Bearer watch-search-key')
            if service == 'exa':
                assert self.headers.get('Authorization') is None
            assert payload['query'] == 'question'
            Handler.searches += 1
            status, headers = 200, {}
            if service == 'redirect':
                status, headers, content = 307, {'Location': '/stolen'}, b''
            elif service == 'rejected':
                status, content = 401, b'echo watch-search-key'
            elif service == 'huge':
                content = b'x' * (512 * 1024 + 1)
            elif service == 'empty':
                content = b'{"results":[]}'
            else:
                if service == 'bocha':
                    assert payload['summary'] is True and payload['count'] == 3 and payload['freshness'] == 'oneWeek'
                    result = {'code': 200, 'data': {'webPages': {'value': [
                        {'name': 'source', 'url': 'https://example.com/source', 'summary': 'evidence watch-search-key'},
                    ]}}}
                else:
                    if service == 'tavily':
                        assert payload['max_results'] == 3 and payload['search_depth'] == 'advanced' and payload['time_range'] == 'week'
                    elif service == 'exa':
                        assert payload['numResults'] == 3 and payload['type'] == 'auto' and 'startPublishedDate' in payload
                    else:
                        raise AssertionError(service)
                    result = {'results': [
                        {'title': 'unsafe', 'url': 'https://example.com/watch-search-key', 'content': 'unsafe', 'text': 'unsafe'},
                        {'title': 'source', 'url': 'https://example.com/source', 'content': 'evidence watch-search-key', 'text': 'evidence watch-search-key'},
                    ]}
                content = json.dumps(result).encode()
            self.send_response(status)
            for key, value in headers.items(): self.send_header(key, value)
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            try: self.wfile.write(content)
            except (BrokenPipeError, ConnectionResetError): pass
            return
        is_claude = self.path.endswith('/messages')
        assert self.headers.get('x-api-key' if is_claude else ('X-Api-Key' if '/api/v3/' in self.path else 'Authorization')) == ('watch-test-key' if is_claude or '/api/v3/' in self.path else 'Bearer watch-test-key')
        model = payload.get('model', '')
        status, content, headers = 200, b'', {}
        if self.path == '/stolen':
            Handler.redirected = True
        elif model == 'redirect':
            status, headers = 307, {'Location': '/stolen'}
        elif model == 'rejected':
            status, content = 401, b'error echo watch-test-key'
        elif payload.get('stream'):
            assert self.headers['Accept'] == 'text/event-stream'
            if model == 'grounded':
                Handler.grounded += 1
                assert 'untrusted webpage evidence' in payload['messages'][-1]['content']
                assert 'https://example.com/source' in payload['messages'][-1]['content'].replace('\\/', '/')
                assert 'watch-search-key' not in json.dumps(payload)
                assert 'cite the exact source URLs' in (payload['system'] if is_claude else payload['messages'][0]['content'])
            else:
                assert (payload.get('system') == 'system') if is_claude else (payload['messages'][0]['role'] == 'system')
            if is_claude:
                events = [{'type': 'content_block_delta', 'delta': {'text': '你好👋'}}, {'type': 'message_stop'}]
            else:
                events = [{'choices': [{'delta': {'content': '你好👋'}}]}]
            content = ''.join('data: ' + json.dumps(e, ensure_ascii=False) + '\r\n\r\n' for e in events).encode()
            if not is_claude and model != 'truncated':
                content += b'data: [DONE]\n\n'
            headers['Content-Type'] = 'text/event-stream'
        elif self.path.endswith('/audio/transcriptions'):
            assert b'filename="speech.wav"' in body and b'RIFF' in body
            content = b'{"text":"hello"}'
        elif self.path.endswith('/audio/speech'):
            content = b'audio'
        elif self.path.endswith('/chat/completions'):
            if payload['messages'][0]['role'] == 'assistant':
                response = {'choices': [{'message': {'audio': {'data': base64.b64encode(b'audio').decode()}}}]}
            else:
                assert payload['messages'][0]['content'][0]['input_audio']['format'] == 'wav'
                response = {'choices': [{'message': {'content': 'hello'}}]}
            content = json.dumps(response).encode()
        elif '/recognize/flash' in self.path:
            assert self.headers['X-Api-Resource-Id'] == 'asr'
            headers['X-Api-Status-Code'] = '20000000'
            content = b'{"result":{"text":"hello"}}'
        elif '/tts/unidirectional/sse' in self.path:
            assert self.headers['X-Api-Resource-Id'] == 'tts'
            content = b'data: {"code":0,"data":"YXVkaW8="}\n\ndata: {"code":20000000}\n\n'
        else:
            raise AssertionError(self.path)
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        # Fragment SSE across UTF-8 boundaries as an actual HTTP response.
        self.wfile.write(content)


def main():
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix='ai-link-watch-tests-') as folder:
            executable = str(Path(folder) / 'watch-tests')
            subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                            str(ROOT / 'ios/AILinkWatch/WatchNetworkConfiguration.swift'),
                            str(ROOT / 'ios/AILinkWatch/WatchNetworkClient.swift'),
                            str(ROOT / 'ios/AILinkPurchases/ApplePurchaseStore.swift'),
                            str(ROOT / 'test/native/watch_network_tests.swift'), '-o', executable], check=True)
            env = dict(os.environ, WATCH_TEST_URL=f'http://127.0.0.1:{server.server_port}')
            subprocess.run([executable], env=env, check=True, timeout=45)
            assert Handler.searches == 10 and Handler.grounded == 6, 'Search before model / failed search must block model'
            assert not Handler.redirected, 'Redirect forwarded a credentialed request'
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
