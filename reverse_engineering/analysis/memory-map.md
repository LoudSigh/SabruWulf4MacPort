# Initial 48K menu memory inventory

Input: user-captured `SNAPSHOTS/Snapshot.z80`, SHA-256 `34d98ec3dc55d60755a7d9ceebe45c3a7e345ce5961692d25d2d6718bcdc20ea`. A read-only restore with reference ROM SHA-256 `d55daa439b673b0e3f5897f99ac37ecb45f974d1862b4dadb85dec34af99cb42` produced an independently verified, nonblank main menu. Raw RAM, screenshots and program instructions remain local.

| Address interval | Standard 48K machine role | Observed classification in this capture |
| --- | --- | --- |
| `0000-3FFF` | 16 KiB ROM | Reference ROM, not present in snapshot RAM |
| `4000-57FF` | ULA bitmap | Menu screen bitmap; 3,135/6,144 bytes nonzero |
| `5800-5AFF` | ULA attributes | Menu color attributes (13 distinct byte values) |
| `5B00-5FFF` | Printer buffer/system/workspace region | Unknown; do not classify as game code by location alone |
| `6000-FFFF` | General RAM | Mixed code/data/graphics/stack, mostly **unclassified** |

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

Next: acquire a snapshot during gameplay and compare per-address changes with the menu image. Use controlled emulator tracing to identify actual read/write/execute regions before naming routines or extracting assets for a distributed app. Maintain the `[code, data, padding, unknown]` accounting required by [Spec.md](../../Spec.md); this page is a starting inventory, **not** completed byte coverage.
