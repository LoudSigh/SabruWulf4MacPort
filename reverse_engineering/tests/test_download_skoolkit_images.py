"""Rights-safe unit tests; all image and HTML fixtures are synthetic."""

import io
from email.message import Message
from pathlib import Path
import stat
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import download_skoolkit_images as images


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def synthetic_png() -> bytes:
    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    return (
        images.PNG_SIGNATURE
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00"))
        + png_chunk(b"IEND", b"")
    )


class FakeResponse(io.BytesIO):
    def __init__(self, data: bytes, url: str, content_type: str = "image/png") -> None:
        super().__init__(data)
        self.url = url
        self.headers = Message()
        self.headers["Content-Type"] = content_type
        self.headers["Content-Length"] = str(len(data))

    def geturl(self) -> str:
        return self.url


class AssetDownloadTests(unittest.TestCase):
    def test_finds_only_unique_game_images(self) -> None:
        html = """
        <img src="../images/logo.png">
        <img src="../../images/udgs/01.png">
        <img src="../../images/udgs/01.png">
        <img src="../../images/udgs/02.png">
        <img src="https://elsewhere.invalid/steal.png">
        """
        assets = images.asset_urls(html)
        self.assertEqual([name for name, _ in assets], ["01.png", "02.png"])
        self.assertTrue(all(url.startswith(f"https://{images.HOST}/") for _, url in assets))

    def test_rejects_unsafe_asset_url(self) -> None:
        with self.assertRaisesRegex(images.DownloadError, "Unsafe asset URL"):
            images.asset_urls('<img src="../../images/udgs/traversal%2Fbad.png">')
        with self.assertRaisesRegex(images.DownloadError, "No Sabre Wulf"):
            images.asset_urls('<img src="../images/logo.png">')

    def test_validates_full_png_and_detects_corrupt_crc(self) -> None:
        data = synthetic_png()
        self.assertEqual(images.validate_png(data), (1, 1))
        with self.assertRaisesRegex(images.DownloadError, "CRC"):
            images.validate_png(data[:-5] + b"\x01" + data[-4:])
        with self.assertRaisesRegex(images.DownloadError, "IEND"):
            images.validate_png(data[:-12])

    def test_downloads_synthetic_image_without_overwriting(self) -> None:
        url = f"https://{images.HOST}{images.ASSET_PREFIX}01.png"
        data = synthetic_png()
        calls = 0

        def opener(request, timeout):
            nonlocal calls
            calls += 1
            self.assertEqual(timeout, 20)
            return FakeResponse(data, request.full_url)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            first = images.download_one("01.png", url, output, opener=opener)
            second = images.download_one("01.png", url, output, opener=opener)
            self.assertEqual((first["status"], second["status"]), ("downloaded", "existing"))
            self.assertEqual(first["sha256"], second["sha256"])
            self.assertEqual(calls, 1)
            self.assertEqual(stat.S_IMODE((output / "01.png").stat().st_mode), 0o600)

    def test_rejects_redirect_and_non_png_content(self) -> None:
        url = f"https://{images.HOST}{images.ASSET_PREFIX}01.png"
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(images.DownloadError, "Redirected"):
                images.download_one(
                    "01.png",
                    url,
                    Path(directory),
                    opener=lambda request, timeout: FakeResponse(
                        synthetic_png(), "https://elsewhere.invalid/01.png"
                    ),
                )
            with self.assertRaisesRegex(images.DownloadError, "Unexpected content type"):
                images.download_one(
                    "01.png",
                    url,
                    Path(directory),
                    opener=lambda request, timeout: FakeResponse(
                        b"not an image", url, "text/html"
                    ),
                )

    def test_rejects_existing_corrupt_file_and_size_overrun(self) -> None:
        url = f"https://{images.HOST}{images.ASSET_PREFIX}01.png"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "01.png").write_bytes(b"not a PNG")
            with self.assertRaisesRegex(images.DownloadError, "PNG signature"):
                images.download_one("01.png", url, output)
            (output / "01.png").unlink()
            with self.assertRaisesRegex(images.DownloadError, "safety limit"):
                images.download_one(
                    "01.png",
                    url,
                    output,
                    opener=lambda request, timeout: FakeResponse(synthetic_png(), url),
                    max_allowed=10,
                )
            self.assertFalse((output / "01.png").exists())

    def test_refuses_download_without_rights_confirmation(self) -> None:
        with patch.object(sys, "argv", ["download_skoolkit_images.py", "--download"]):
            with self.assertRaisesRegex(images.DownloadError, "requires --confirm-rights"):
                images.main()
        with patch.object(sys, "argv", ["download_skoolkit_images.py", "--confirm-rights"]):
            with self.assertRaisesRegex(images.DownloadError, "only valid with --download"):
                images.main()


if __name__ == "__main__":
    unittest.main()
