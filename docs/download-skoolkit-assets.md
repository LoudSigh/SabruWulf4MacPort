# List or privately download the linked graphics

The supplied `SNAPSHOTS/graphics/Graphics.html` references **160 distinct Sabre Wulf UDG PNGs** on the [SkoolKit graphics page](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/graphics/graphics.html). The page's site logo is excluded. The site has copyright notices but no clear asset reuse license. **Only download if you have permission for your intended use; never commit, publish, or bundle these third-party images without the relevant rights.** The script uses Python 3.11+ and its standard library; no extra packages are required.

From the repository root, first inspect the source list without downloading anything:

```sh
python3 reverse_engineering/tools/download_skoolkit_images.py
python3 reverse_engineering/tools/download_skoolkit_images.py --list
```

The script reads your existing `SNAPSHOTS/graphics/Graphics.html` by default. To list the current *online* page instead, use `--live --list`. Once **you** have confirmed that a private local copy is permitted, run:

```sh
python3 reverse_engineering/tools/download_skoolkit_images.py --download --confirm-rights
```

Use `--live --download --confirm-rights` if you prefer the current online HTML rather than the saved copy. **All downloaded images and the manifest live under `SNAPSHOTS/graphics/downloaded/`**, as requested; the reusable script itself is versioned under `reverse_engineering/tools/`. `SNAPSHOTS/` is excluded from Git. The script refuses off-host URLs, path traversal, unexpected redirects/content types, malformed PNGs, unsafe output locations, and attempts to overwrite existing files. Downloads are sequential, paced, bounded by per-file and total size limits, and checked against the site's `robots.txt`. If a download fails, the error is explicit; rerunning validates existing files before continuing.

This command downloads images referenced **directly on the Graphics page**, not images on the separate [Backgrounds page](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/graphics/backgrounds.html). It does not import images into the native app.

### TC-Assets-001: Preview source list without copying artwork
- **Priority**: P0
- **Preconditions**: The user-supplied `Graphics.html` is present.
- **Steps**: Run the script without flags, then with `--list`.
- **Expected Result**: Both identify 160 distinct game PNGs; the logo is omitted and no `downloaded/` directory is created.
- **Edge Cases / Variants**: Missing HTML fails with a suggestion to use `--live`.

### TC-Assets-002: Authorized local download
- **Priority**: P1
- **Preconditions**: You have established permission for the intended local use.
- **Steps**: Run with `--download --confirm-rights`, inspect `SNAPSHOTS/graphics/downloaded/manifest.json`, then rerun.
- **Expected Result**: The first run saves validated PNGs under ignored `SNAPSHOTS/`; the second validates and reports existing files without overwriting them. A missing rights confirmation or corrupt image stops with an explicit error.
- **Edge Cases / Variants**: Offline network, site redirect, changed PNG, denied robots policy or unexpectedly large asset.
