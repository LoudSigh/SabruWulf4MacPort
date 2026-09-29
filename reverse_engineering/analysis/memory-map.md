# Initial 48K menu memory inventory

Input: user-captured `SNAPSHOTS/Snapshot.z80`, SHA-256 `34d98ec3dc55d60755a7d9ceebe45c3a7e345ce5961692d25d2d6718bcdc20ea`. A read-only restore with reference ROM SHA-256 `d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42` produced an independently verified, nonblank main menu. Raw RAM, screenshots and program instructions remain local.

| Address interval | Standard 48K machine role | Observed classification in this capture |
| --- | --- | --- |
| `0000-3FFF` | 16 KiB ROM | Reference ROM, not present in snapshot RAM |
| `4000-57FF` | ULA bitmap | Menu screen bitmap; 3,135/6,144 bytes nonzero |
| `5800-5AFF` | ULA attributes | Menu color attributes (13 distinct byte values) |
| `5B00-5FFF` | Printer buffer/system/workspace region | Unknown; do not classify as game code by location alone |
| `6000-6065` | General RAM | Unknown (external reference identifies a game entry at `6000`; entry signature only partially cross-checked) |
| `6066-6165` | General RAM | Verified 256-byte 16x16 world layout indexes |
| `6166-61C5` | General RAM | Verified 48-entry little-endian room pointer table |
| `61C6-61FF` | General RAM | Verified terminated special menu-room record |
| `6200-70BB` | General RAM | Verified 48 contiguous terminated room-template records |
| `70BC-9691` | General RAM | Verified 41 contiguous bitmap-plus-attribute background records (9,686 bytes) |
| `9692-BF83` | General RAM | Mixed code, state and other data, mostly **unclassified** |
| `BF84-C10B` | General RAM | Verified 196-entry sprite-frame pointer table, 392 bytes |
| `C10C-FFFF` | General RAM | Pointed-to sprite data and other mixed RAM, not yet classified by byte |

At the capture the PC is `BDAF` (RAM) and the SP is `5FF8`; these pinpoint one **executing address** and the stack top, not code extents or routine names. The ROM and game RAM relationship to the supplied TZX revision still needs validation.

## SHA-256 and nonzero counts by 4 KiB page

Nonzero counts describe density only; they do **not** distinguish instructions from graphics, packed data, encryption or uninitialized RAM. Addresses below are the first address of each page in the restored 48K memory.

| Start | Nonzero/4096 | SHA-256 |
| --- | ---: | --- |
| `4000` | 1994 | `9a332864377d092479844ca1b5db7d4640dc272c99eb9f310b90795352d1d911` |
| `5000` | 2130 | `7c7dcc8ed8995933a8d09a792f8493807c0c619c095020c7f7145ed029c5ef14` |
| `6000` | 3830 | `b17bca36f836b4669027fdc2edcdf25c74dbe9fc0f92fe360d4b7c300c97abf4` |
| `7000` | 3563 | `b597677acbe56007c68c27b8ce2289d022bd037becac9871305658c16dbfe070` |
| `8000` | 3623 | `ab0ed52c6e3a05cc18665238f64eef029b8275d80c1718f4fff610eab6dae592` |
| `9000` | 3204 | `16f932e8a9f7aca90ed118b6f0b0bcf2cb34a4108dae44c1254278e01aa30fb8` |
| `A000` | 3877 | `4123e5883feb86db8933a96d9431406eccbedb016abc585c09dd85578d09821f` |
| `B000` | 3961 | `5d9a51ead461aee6897732d2790950b3524acfa305c3a6dc495f0483816eeabb` |
| `C000` | 3382 | `732bed0a20f2dea428c66c15fa0ed9fccb03830814a330ef955c61051072ccf9` |
| `D000` | 3037 | `47f56b983b4b26b9b514cd40b86e47a31b2cea671fd5737ad76e096a34178c83` |
| `E000` | 3023 | `cff32417993d24fd9acee40ad55f6d33c034dc90beb127d37e32d068790cf22d` |
| `F000` | 3331 | `bc4f3b160d9b4a53b2a66ebb3e40c9e6ce74f3e75642b1af816b7945b866b9f1` |

Next: validate more input-driven states against the existing gameplay snapshot and verify graphics pointer formats. Use controlled emulator tracing to identify actual read/write/execute regions before naming routines or extracting assets for a distributed app. Maintain the `[code, data, padding, unknown]` accounting required by [Spec.md](../../Spec.md); this page is a starting inventory, **not** completed byte coverage.

## Menu-to-gameplay comparison

The user later supplied a distinct, same-machine in-game snapshot, SHA-256 `803e4197989c73408cfc5113f8f30c81ac0269958aa9e105b474b6f52437203c`, captured with one player and keyboard selected. It renders a 256×192 jungle playfield with a player figure and status display. Its PC is `B8A1`, SP `5FF6`, full 48K RAM SHA-256 `6de170c1b2518c82c5bfefc0f7dbfc8b8766097e020950d51b01baf045064864`. Menu vs. gameplay differs at **4,558/49,152** RAM byte positions: 3,159 bitmap bytes, 445 attribute bytes, 44 bytes in `5B00-5FFF`, and 910 bytes in `6000-FFFF`.

| Page start | Changed bytes from menu |
| --- | ---: |
| `4000` | 1240 |
| `5000` | 2408 |
| `6000` | 0 |
| `7000` | 0 |
| `8000` | 0 |
| `9000` | 225 |
| `A000` | 0 |
| `B000` | 2 |
| `C000` | 0 |
| `D000` | 357 |
| `E000` | 326 |
| `F000` | 0 |

**Interpretation limit:** identical pages are candidate static game code/data, not proven code. Differences outside the screen mark potential state/tables/stack/animation; two captures alone cannot separate these. `B8A1` is an observed PC, not a function name. [byte-coverage.json](./byte-coverage.json) now also classifies verified world, background, actor-handler pointer and sprite data; other unclassified bytes remain `unknown`.

## Bounded diagnostic trace

The private [`SnapshotTrace.swift`](../tools/SnapshotTrace.swift) runs the existing backup's Z80 CPU on a copy of the restored memory **without frame interrupts or accurate I/O timing**. A 200,000-step exploratory run from the in-game capture saw 1,083 distinct instruction starts, 74 distinct CALL edges and writes to 317 RAM addresses. Execution was concentrated in `9000-BFFF` plus one start at `5CB0` (outside display RAM). The corresponding menu trace reached only 58 distinct starts and four RAM write addresses. Aggregate counts and provenance are in [trace-summary.json](./trace-summary.json); complete numeric traces, raw RAM and preliminary assembly listings remain in the ignored `reverse_engineering/private/` directory only. These are **not** verified whole-game control flow or complete classification.

An instruction-PC-to-write-address correlation placed all 1,141 diagnostic display writes at twelve PC addresses in `BA59-BB4C`, with repeated CALL targets `BA0D` and `BA8C`. This gives a **candidate rendering cluster** (see [functions.json](./functions.json)); it does not establish sprite layout, frame timing, or all other code boundaries. Only address/count metadata is public.

A longer *separate* 1,000,000-step no-input diagnostic reached 1,422 distinct instruction starts and 100 CALL edges; the extra addresses remain within `9000-BFFF` plus `5CB0`. These are **observed instruction-start candidates in an incomplete, untimed execution mode**. They do not establish that the other 48K RAM bytes are data or that the complete game state space has been reached.

While this cluster was running, diagnostic reads outside display/code regions touched 174 distinct addresses in `D000-DFFF` and 191 in `F000-FFFF`, alongside smaller groups in `5xxx`, `9xxx` and `Cxxx`. These pages are **candidates to investigate for graphics and lookup data**, not proven sprite tables: reads may also be control flags, pointers or other mutable state. Original content stays only in the ignored local RAM image.

## Reference-guided room structure

The user-supplied [SkoolKit index](../../docs/external-reference.md) gave numeric boundaries that were checked against **both** snapshot RAM images: layout `6066-6165`, 48 room pointers `6166-61C5`, special menu room `61C6-61FF` and 48 contiguous zero-terminated room templates `6200-70BB`. The 256 layout bytes use room type indexes 0–47 and reuse 45 distinct types across the 16×16 world. The private `SnapshotRoomIndex` parser validates the complete region without committing map IDs, placement records or background graphics. These extra 4,182 bytes are now classified as data in [byte-coverage.json](./byte-coverage.json); the remainder remains unknown until analyzed, not presumed code.
The same parser validates **41 adjacent background records** from `70BC` through `9691`: each has a bounded pixel bitmap followed by a correctly sized per-cell attribute grid. All 41 end at the next record or the `9692` game-state boundary; **9,686/9,686 bytes** agree across both captures. At that stage, known data reached **29,178 bytes** (unknown **19,974**). All source pixels remain ignored, never in this memory map or Git.

A separate private `SnapshotSpriteIndex` check confirmed 196 little-endian pointers at `BF84-C10B` in **both** captures, 153 distinct targets, and an identical table hash. Each unique pointed-to record has a plausible two-byte width/height header and `width × height` bounded data bytes; 148 records end precisely at the next pointer, five leave gaps. The **392 table bytes and 8,006 bounded record bytes** are identical across menu and gameplay captures and now classified as data. The gaps, image orientation, color/mask rendering semantics and sprite animation rules remain unknown. See [sprite-index.json](./sprite-index.json); no original frames are stored in Git.
An independent [actor handler index](./actor-handler-index.json) checks another **196 little-endian pointers** at `9B3E–9CC5`, with **25 distinct bounded targets** and identical pointer bytes in menu/gameplay captures. The source actor-kind dispatcher at numeric PC **39390** was reached in eight RAM-verified runs; **18/25 target entry addresses** were observed as executed PC starts there and seven were not. A twelve-run, **7,720-frame** private exact-fetch probe found **zero** instruction-byte overlaps with this 392-byte table. It is now data, taking known RAM data to **29,570/49,152** and leaving **19,582 unknown**, of which **14,667** were not fetched as instructions in those twelve observed paths. The targets' instruction extents and unvisited behavior are still unknown; neither pointers nor disassembly are published.
