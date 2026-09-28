# Sabre Wulf reference cross-check

The user pointed to [ArcadeGeek's SkoolKit Sabre Wulf index](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/), labeled there as a **work-in-progress** RAM disassembly. Useful navigable references include its [data map](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/maps/data.html), [routines map](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/maps/routines.html), [backgrounds](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/graphics/backgrounds.html), [graphics index](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/graphics/graphics.html), [game-state buffer](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/buffers/gbuffer.html) and [credits](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/reference/credits.html).

**Copyright boundary:** the pages credit Ultimate Play the Game and ArcadeGeek; the linked upstream repository reports no explicit reuse license. These pages are pointers for analysis, **not** permission to copy their disassembly, graphics, rendered room images or game data into this repository. The user additionally requires **no disassembly on GitHub**. Keep all source bytes, local listings and derived original layouts/images inside ignored `reverse_engineering/private/` only. Public analysis here contains numeric addresses, counts, hashes and independently worded conclusions.

## Independent checks against the supplied 48K snapshots

| Reference claim | Check against local menu/gameplay snapshots | Result |
| --- | --- | --- |
| [Game entry at 24576 (`0x6000`)](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/asm/24576.html) | Two-byte entry signature checked privately in the in-game RAM image, without outputting bytes | Matches; a short signature does **not** establish whole-binary identity |
| [Layout at 24678 (`0x6066`)](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/asm/24678.html) | Independently parsed exactly 256 indexes, each in range 0–47; SHA-256 stable in two snapshots | 16×16 world positions; 45 distinct template IDs occur |
| [Room table at 24934 (`0x6166`)](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/asm/24934.html) | Independently decoded 48 two-byte pointers; first two match the linked room records; 96 bytes identical across captures | 48 distinct template records, **not** only 48 world positions |
| [Menu room at 25030](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/asm/25030.html) and [first regular room at 25088](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/asm/25088.html) | Local parser found 14 placements in the special room and 48 contiguous, terminated regular records ending at 28860 (`0x70BC`) | Room records occupy 3,772 bytes and have 919 background placements referencing 41 distinct starting addresses between `0x70BC` and `0x9673` |
| [Game options at 38546 (`0x9692`)](https://skoolkit.arcadegeek.co.uk/ultimate/sabrewulf/dec/asm/38546.html) | Private one-byte check in the user-captured 1-player game state | Matches the reference's 1-player option; other flags/rules unverified |

The source-backed ranges `0x6066–0x70BB` can now be treated as data in [byte-coverage.json](../reverse_engineering/analysis/byte-coverage.json). Screen bitmap/attributes are also known, totaling **11,094 classified data bytes** of 49,152 RAM bytes. The remaining 38,058 are still marked `unknown`; diagnostic instruction-start addresses do not by themselves classify instruction lengths. [room-index.json](../reverse_engineering/analysis/room-index.json) records aggregate counts and input hashes without publishing original map or placement bytes.

## Reproduce and inspect privately

Run from the repository root. This tool uses the locally installed Carbon Neural emulator's `SpeccyCore` parser without copying its source here:

```sh
SPECCY_CORE_DIR='/Volumes/July2025inclOct2022/Visual Studio Code Backups/Carbon Neural/2025-09-13_22-10-25/CarbonNeural_portable_2025-09-13_22-10-25/Sources/SpeccyCore'
OUT="$(mktemp -d)"
swiftc -O -parse-as-library "$SPECCY_CORE_DIR"/*.swift reverse_engineering/tools/SnapshotRoomIndex.swift -o "$OUT/SnapshotRoomIndex"
"$OUT/SnapshotRoomIndex" --self-test
"$OUT/SnapshotRoomIndex" SNAPSHOTS/Snapshot.z80 SNAPSHOTS/Snapshot_GamePlay.z80 --private-map
open reverse_engineering/private/snapshot-803e4197989c-world.html
```

The opened **private** local HTML shows 256 world positions colored by room-template ID (generic colors and numbers, not original graphics). It and all snapshot bytes stay ignored by Git. Next, trace how the program selects backgrounds and collisions from these records before replacing the current 2×2 placeholder world in the native prototype. This reference cross-check advances *static* map recovery; it does not establish tape revision equality or continuous input-driven behavior.
