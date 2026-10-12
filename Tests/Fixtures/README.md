# Test fixtures

Files the tests open, copied into each test bundle as a folder (never into the app).

| File | From |
|---|---|
| `GameTime.lss` | livesplit-core `tests/run_files/livesplit1.6_gametime.lss` |
| `Llanfair.lfs` | livesplit-core `tests/run_files/llanfair_gered.lfs` |
| `Dark.lsl` | livesplit-core `tests/layout_files/dark.lsl` |
| `TextShadow.ls1l` | livesplit-core `tests/layout_files/TextShadow.ls1l` |
| `NotSplits.txt` | Written by hand: `hello`. Neither splits nor a layout. |
| `Empty.lss` | Written by hand: a `<Run>` with no segments. Parses, but has none. |

The livesplit-core files are copied from the revision pinned in `core/Cargo.lock`.
livesplit-core is dual licensed under the MIT and Apache-2.0 licenses, and so are these
copies; see `LICENSE-MIT` and `LICENSE-APACHE` at the repository root.

`GameTime.lss` links no layout: it has no `<LayoutPath>` element.
