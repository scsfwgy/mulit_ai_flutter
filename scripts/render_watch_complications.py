#!/usr/bin/env python3
"""Render the current SwiftUI complication layout with example content on macOS."""
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "build/complication-preview/statuses.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ailink-complication-render-") as folder:
        folder = Path(folder)
        views = folder / "WidgetViews.swift"
        # Exclude the extension entry point and Xcode previews from the macOS executable.
        source = (root / "ios/AILinkWatchWidgets/AILinkWatchWidgets.swift").read_text()
        views.write_text(source.split("@main", 1)[0])
        executable = folder / "render"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
            str(root / "ios/AILinkWatchShared/WatchComplicationSnapshot.swift"),
            str(root / "ios/AILinkWatchShared/WatchChatShortcut.swift"), str(views),
            str(root / "scripts/render_watch_complications.swift"), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable), str(output)], check=True)


if __name__ == "__main__":
    main()
