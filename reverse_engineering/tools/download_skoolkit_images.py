#!/usr/bin/env python3
"""List or privately download the PNG assets referenced by Graphics.html."""

from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from typing import Callable
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import Request, urlopen
from urllib.robotparser import RobotFileParser
import zlib

PAGE_URL = "https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/graphics/graphics.html"
ASSET_PREFIX = "/ultimate/sabrewulf/images/udgs/"
HOST = "skoolkit.arcadegeek.co.uk"
ROBOTS_URL = f"https://{HOST}/robots.txt"
USER_AGENT = "SabreWulf4MacPort-private-study/1.0"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_HTML_BYTES = 2_000_000
MAX_PNG_BYTES = 2_000_000
MAX_TOTAL_BYTES = 64_000_000


class DownloadError(Exception):
    """A source, rights, content, or local-safety check failed."""


class ImageSources(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.sources: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "img":
            return
        for name, value in attrs:
            if name.lower() == "src" and value:
                self.sources.append(value)


def asset_urls(html: str, page_url: str = PAGE_URL) -> list[tuple[str, str]]:
    parser = ImageSources()
    parser.feed(html)
    found: dict[str, tuple[str, str]] = {}
    for source in parser.sources:
        url = urljoin(page_url, source)
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc != HOST:
            continue
        decoded_path = unquote(parsed.path)
        if not decoded_path.startswith(ASSET_PREFIX):
            continue  # Excludes the site's logo and unrelated images.
        name = decoded_path[len(ASSET_PREFIX) :]
        if (
            parsed.query
            or parsed.fragment
            or ".." in name
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*\.png", name, re.I)
        ):
            raise DownloadError(f"Unsafe asset URL in page: {url}")
        key = name.casefold()
        if key in found and found[key] != (name, url):
            raise DownloadError(f"Conflicting image filename: {name}")
        found[key] = (name, url)
    if not found:
        raise DownloadError("No Sabre Wulf UDG PNG assets found in the supplied page")
    return sorted(found.values(), key=lambda pair: pair[0].casefold())


def verified_response(opener: Callable, url: str, accept: str, limit: int) -> bytes:
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    with opener(request, timeout=20) as response:
        if response.geturl() != url:
            raise DownloadError(f"Redirected URL refused: {url}")
        content_type = response.headers.get_content_type()
        if content_type != accept:
            raise DownloadError(f"Unexpected content type for {url}: {content_type}")
        length = response.headers.get("Content-Length")
        if length is not None and int(length) > limit:
            raise DownloadError(f"Content-Length exceeds safety limit for {url}")
        data = response.read(limit + 1)
    if len(data) > limit:
        raise DownloadError(f"Response exceeds safety limit for {url}")
    return data


def validate_png(data: bytes) -> tuple[int, int]:
    if not data.startswith(PNG_SIGNATURE):
        raise DownloadError("Response does not have a PNG signature")
    offset = len(PNG_SIGNATURE)
    width = height = 0
    saw_data = False
    while offset + 12 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], "big")
        end = offset + 12 + length
        if end > len(data):
            raise DownloadError("PNG contains a truncated chunk")
        kind = data[offset + 4 : offset + 8]
        contents = data[offset + 8 : offset + 8 + length]
        checksum = int.from_bytes(data[offset + 8 + length : end], "big")
        if zlib.crc32(kind + contents) & 0xFFFFFFFF != checksum:
            raise DownloadError("PNG chunk CRC does not match")
        if offset == len(PNG_SIGNATURE):
            if kind != b"IHDR" or length != 13:
                raise DownloadError("PNG must begin with a 13-byte IHDR")
            width = int.from_bytes(contents[:4], "big")
            height = int.from_bytes(contents[4:8], "big")
            if not (1 <= width <= 4096 and 1 <= height <= 4096):
                raise DownloadError("PNG dimensions are outside safety limits")
        if kind == b"IDAT":
            saw_data = True
        if kind == b"IEND":
            if length != 0 or end != len(data) or not saw_data:
                raise DownloadError("PNG is missing complete image data")
            return width, height
        offset = end
    raise DownloadError("PNG is missing its final IEND chunk")


def private_destination(
    root: Path, relative: Path = Path("SNAPSHOTS/graphics/downloaded")
) -> Path:
    if "SNAPSHOTS/" not in (root / ".gitignore").read_text(encoding="utf-8").splitlines():
        raise DownloadError("SNAPSHOTS/ must be in .gitignore before downloading")
    if (
        relative.is_absolute()
        or not relative.parts
        or relative.parts[0] != "SNAPSHOTS"
        or any(part in ("..", ".") for part in relative.parts)
    ):
        raise DownloadError("Output must be under SNAPSHOTS/")
    result = subprocess.run(
        ["git", "check-ignore", "-q", str(relative / "probe.png")],
        cwd=root,
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        raise DownloadError("The output directory is not ignored by Git")
    output = root
    for part in relative.parts:
        output = output / part
        if output.is_symlink():
            raise DownloadError(f"Output path must not be a symbolic link: {output}")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    return output


def save_image(destination: Path, data: bytes) -> None:
    if destination.exists() or destination.is_symlink():
        raise DownloadError(f"Refusing to overwrite an existing file: {destination}")
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=".pending-", dir=destination.parent, delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if temporary is None:
            raise DownloadError("Failed to create an image staging file")
        os.link(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def fetch_robots(opener: Callable) -> RobotFileParser:
    data = verified_response(opener, ROBOTS_URL, "text/plain", 100_000)
    parser = RobotFileParser()
    parser.parse(data.decode("utf-8").splitlines())
    return parser


def download_one(
    name: str,
    url: str,
    directory: Path,
    opener: Callable = urlopen,
    max_allowed: int = MAX_PNG_BYTES,
) -> dict[str, str | int]:
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or parsed.netloc != HOST
        or parsed.query
        or parsed.fragment
        or unquote(parsed.path) != ASSET_PREFIX + name
        or ".." in name
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*\.png", name, re.I)
    ):
        raise DownloadError(f"Unsafe asset URL: {url}")
    destination = directory / name
    if destination.is_symlink():
        raise DownloadError(f"Image path must not be a symbolic link: {destination}")
    if destination.exists():
        if not destination.is_file() or destination.stat().st_size > max_allowed:
            raise DownloadError(f"Existing image is invalid or oversized: {destination}")
        data = destination.read_bytes()
        status = "existing"
    else:
        data = verified_response(opener, url, "image/png", min(MAX_PNG_BYTES, max_allowed))
        status = "downloaded"
    width, height = validate_png(data)
    if status == "downloaded":
        save_image(destination, data)
    return {
        "filename": name,
        "url": url,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "width": width,
        "height": height,
        "status": status,
    }


def main(
    page_url: str = PAGE_URL,
    default_html: Path | None = None,
    output_relative: Path = Path("SNAPSHOTS/graphics/downloaded"),
) -> int:
    root = Path(__file__).resolve().parents[2]
    if default_html is None:
        default_html = root / "SNAPSHOTS/graphics/Graphics.html"
    options = argparse.ArgumentParser(description=__doc__)
    source = options.add_mutually_exclusive_group()
    source.add_argument("--html", type=Path, default=default_html)
    source.add_argument("--live", action="store_true", help="Fetch the current page instead of using Graphics.html")
    action = options.add_mutually_exclusive_group()
    action.add_argument("--list", action="store_true", help="Print all asset filenames and URLs")
    action.add_argument("--download", action="store_true", help=f"Fetch assets into ignored {output_relative}/")
    options.add_argument(
        "--confirm-rights",
        action="store_true",
        help="Confirm you have permission for a local copy; required with --download",
    )
    args = options.parse_args()
    if args.download and not args.confirm_rights:
        raise DownloadError("--download requires --confirm-rights; do not distribute copyrighted images")
    if args.confirm_rights and not args.download:
        raise DownloadError("--confirm-rights is only valid with --download")

    if args.live:
        html_bytes = verified_response(urlopen, page_url, "text/html", MAX_HTML_BYTES)
        html = html_bytes.decode("utf-8")
    else:
        html_file: Path = args.html
        if not html_file.is_file():
            raise DownloadError(f"HTML file not found: {html_file}; use --live to fetch the page")
        if html_file.stat().st_size > MAX_HTML_BYTES:
            raise DownloadError("HTML input exceeds safety limit")
        html = html_file.read_text(encoding="utf-8")
    images = asset_urls(html, page_url)
    print(f"Found {len(images)} distinct UDG PNG assets; the site logo is excluded.")
    if args.list:
        for name, url in images:
            print(f"{name}\t{url}")
        return 0
    if not args.download:
        print("No images downloaded. To save permitted local copies, rerun with --download --confirm-rights.")
        return 0

    robots = fetch_robots(urlopen)
    for _, url in images:
        if not robots.can_fetch(USER_AGENT, url):
            raise DownloadError(f"robots.txt forbids this URL: {url}")
    output = private_destination(root, output_relative)
    delay = max(0.4, robots.crawl_delay(USER_AGENT) or 0)
    records: list[dict[str, str | int]] = []
    total = 0
    for index, (name, url) in enumerate(images, start=1):
        if total >= MAX_TOTAL_BYTES:
            raise DownloadError("Image collection exceeds the total safety limit")
        record = download_one(
            name, url, output, max_allowed=min(MAX_PNG_BYTES, MAX_TOTAL_BYTES - total)
        )
        total += int(record["bytes"])
        records.append(record)
        print(f"[{index}/{len(images)}] {name}: {record['status']}")
        if record["status"] == "downloaded" and index < len(images):
            time.sleep(delay)

    manifest = {
        "source": page_url,
        "copyrightNotice": "The source site credits Ultimate Play the Game and ArcadeGeek; no redistribution permission is assumed.",
        "files": records,
    }
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", prefix=".manifest-", dir=output, delete=False
        ) as handle:
            temporary = Path(handle.name)
            json.dump(manifest, handle, indent=2)
            handle.write("\n")
        if temporary is None:
            raise DownloadError("Failed to create a manifest staging file")
        os.replace(temporary, output / "manifest.json")
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(f"Saved {len(records)} validated images under {output}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (DownloadError, OSError, ValueError) as error:
        print(f"Asset download aborted: {error}", file=sys.stderr)
        sys.exit(1)
