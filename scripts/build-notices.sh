#!/usr/bin/env bash
# Writes the notices of the third-party code linked into the app, which the
# app shows in Help > Acknowledgements (spec §4.4).
#
#   scripts/build-notices.sh <output file>
#
# The Rust crates' notices are generated with cargo-about from core/'s
# dependencies, and the rest come from notices/other.txt. Fails if a crate's
# licence isn't one notices/about.toml accepts, or if something
# notices/other.txt covers changed since it was checked (notices/pins.txt).
set -euo pipefail

output=${1:?usage: build-notices.sh <output file>}

# Xcode's build phases don't see the login shell's PATH: cargo comes from
# rustup, and cargo-about from mise.
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin:$PATH"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

root=$(cd "$(dirname "$0")/.." && pwd)
notices="$root/notices"
# rustup picks the toolchain from the current directory (rust-toolchain.toml),
# and mise its tools (mise.toml).
cd "$root"

cargo_about=$(command -v cargo-about || mise which cargo-about 2>/dev/null || true)
if [[ -z "$cargo_about" ]]; then
  echo "cargo-about not found: run \`mise install\` (CONTRIBUTING.md)" >&2
  exit 1
fi

fail() {
  echo "$1" >&2
  echo "Check notices/other.txt still covers it, then update notices/pins.txt (spec §4.4)." >&2
  exit 1
}

# swift-toml, and the toml++ built into it.
pinned_toml=$(awk '$1 == "swift-toml" { print $2 }' "$notices/pins.txt")
project_toml=$(awk '/mattt\/swift-toml/ { found = 1 } found && /exactVersion:/ { print $2; exit }' \
  "$root/project.yml")
if [[ "$project_toml" != "$pinned_toml" ]]; then
  fail "project.yml has swift-toml $project_toml; its notices were checked for ${pinned_toml:-no version}."
fi

# The fonts livesplit-core builds in: every file in its font assets, each
# with the hash it was checked at.
metadata=$(cargo metadata --format-version 1 --locked --manifest-path "$root/core/Cargo.toml")
core_dir=$(jq -r '.packages[] | select(.name == "livesplit-core")
  | .manifest_path | rtrimstr("/Cargo.toml")' <<<"$metadata")
fonts="$core_dir/src/rendering/font/assets"
if [[ ! -d "$fonts" ]]; then
  fail "livesplit-core has no $fonts any more: its fonts moved."
fi
found=$(cd "$fonts" && shasum -a 256 -- * | awk '{ print "font", $2, $1 }' | sort)
pinned=$(grep '^font ' "$notices/pins.txt" | sort)
if [[ "$found" != "$pinned" ]]; then
  fail "livesplit-core's fonts changed. Its fonts now:
$found
The fonts checked:
$pinned"
fi

# cargo-about's dependency graph (the krates crate) takes livesplit-core-capi
# for livesplit-core, since the C API's library is named livesplit_core. So it
# reads a copy of core/'s manifest with the livesplit-core dependency renamed:
# the same crates, features and lock file.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed 's/^livesplit-core = { /livesplit-core-renamed = { package = "livesplit-core", /' \
  "$root/core/Cargo.toml" >"$work/Cargo.toml"
if ! grep -q '^livesplit-core-renamed = ' "$work/Cargo.toml"; then
  echo "core/Cargo.toml has no 'livesplit-core = { ' line to rename" >&2
  exit 1
fi
cp "$root/core/Cargo.lock" "$work/Cargo.lock"
ln -s "$root/core/src" "$work/src"
# Offline: only the crates' own files, which `cargo metadata` above fetched.
"$cargo_about" generate --locked --offline --manifest-path "$work/Cargo.toml" \
  --config "$notices/about.toml" --format json --output-file "$work/crates.json"

# lso-core is core/ itself, under the app's own licence.
crates=$(jq -r '
  .licenses[]
  | .used_by |= map(select(.crate.name != "lso-core"))
  | select(.used_by | length > 0)
  | "--------------------------------------------------------------------------------\n\n"
    + .name + ", used by:\n"
    + (.used_by | map("  " + .crate.name + " " + .crate.version) | join("\n"))
    + "\n\n" + (.text | rtrimstr("\n")) + "\n"
' "$work/crates.json")
if [[ -z "$crates" ]]; then
  echo "cargo-about listed no crates" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
{
  cat <<'HEADER'
LiveSplit One for macOS includes the third-party software below, with the
notices and licences it is distributed under.

HEADER
  cat "$notices/other.txt"
  cat <<'HEADER'

================================================================================
Rust crates
================================================================================

The crates built into the app with livesplit-core, grouped by licence text.

HEADER
  echo "$crates"
} >"$output.tmp"
mv "$output.tmp" "$output"
