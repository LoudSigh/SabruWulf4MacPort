#!/usr/bin/env python3
"""Download linked backgrounds into ignored SNAPSHOTS/backgrounds/ (local use only).

Run with: python3 reverse_engineering/tools/download_skoolkit_backgrounds.py
To download: add --download --confirm-rights after confirming permitted use.
"""

from pathlib import Path
import sys

from download_skoolkit_images import DownloadError, main


def run() -> int:
    root = Path(__file__).resolve().parents[2]
    return main(
        page_url="https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/graphics/backgrounds.html",
        default_html=root / "SNAPSHOTS/backgrounds/Backgrounds.html",
        output_relative=Path("SNAPSHOTS/backgrounds"),
    )


if __name__ == "__main__":
    try:
        sys.exit(run())
    except (DownloadError, OSError, ValueError) as error:
        print(f"Background download aborted: {error}", file=sys.stderr)
        sys.exit(1)
