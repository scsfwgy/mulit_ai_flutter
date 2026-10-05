#!/usr/bin/env python3
"""Exercise the Apple watch Markdown parser locally, without user data or network."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='ai-link-watch-markdown-') as directory:
        executable = Path(directory) / 'watch-markdown-tests'
        subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
            str(ROOT / 'ios/AILinkWatch/WatchMarkdownDocument.swift'),
            str(ROOT / 'test/native/watch_markdown_tests.swift'),
            '-o', str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)
