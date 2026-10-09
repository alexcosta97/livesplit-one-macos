#!/usr/bin/env bash
# Builds core/ and regenerates the Swift bindings into LiveSplitCore/ (spec
# §4.2).
#
#   scripts/build-core.sh                        debug, this Mac's architecture
#   scripts/build-core.sh --release              release, this Mac's architecture
#   scripts/build-core.sh --release --universal  release, Apple Silicon and Intel
#   scripts/build-core.sh --bindings-only        only the Swift bindings, for
#                                                xcodegen's preGenCommand
#
# In Xcode's build phase, CONFIGURATION and ARCHS choose instead, and the
# script writes a dependency file so Xcode skips the phase when nothing it
# read has changed.
set -euo pipefail

# Xcode's build phases don't see the login shell's PATH.
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/core/Cargo.toml"
out="$root/LiveSplitCore"

# rustup picks the toolchain from the current directory, so every cargo call
# runs from the repository and sees rust-toolchain.toml.
cd "$root"

release=false
bindings_only=false
archs=$(uname -m)
for arg in "$@"; do
  case "$arg" in
    --release) release=true ;;
    --universal) archs="arm64 x86_64" ;;
    --bindings-only) bindings_only=true ;;
    *)
      echo "usage: build-core.sh [--release] [--universal] [--bindings-only]" >&2
      exit 2
      ;;
  esac
done
if [[ -n "${CONFIGURATION:-}" ]]; then
  if [[ "$CONFIGURATION" == Release ]]; then release=true; else release=false; fi
  archs=${ARCHS:-$archs}
fi
profile=debug
if $release; then profile=release; fi

rust_target() {
  case "$1" in
    arm64) echo aarch64-apple-darwin ;;
    x86_64) echo x86_64-apple-darwin ;;
    *)
      echo "unsupported architecture: $1" >&2
      exit 1
      ;;
  esac
}

toolchain=$(rustup show active-toolchain | cut -d' ' -f1)
metadata=$(cargo metadata --format-version 1 --locked --manifest-path "$manifest")
# The C API's features are read from core/Cargo.toml, so the bindings always
# describe the library that is built.
features=$(jq -r '.packages[] | select(.name == "lso-core") | .dependencies[]
  | select(.name == "livesplit-core-capi") | .features | join(",")' <<<"$metadata")
capi_dir=$(jq -r '.packages[] | select(.name == "livesplit-core-capi")
  | .manifest_path | rtrimstr("/Cargo.toml")' <<<"$metadata")

# Builds one target. Prints "<crate> <path>" for its two static libraries:
# livesplit_core (the C API) and lso_core (core/).
build_target() {
  local target=$1 release_flag=""
  if $release; then release_flag=--release; fi
  # shellcheck disable=SC2086 # release_flag is empty or one word
  cargo build --locked --manifest-path "$manifest" --target "$target" $release_flag \
    --message-format=json-render-diagnostics |
    jq -r 'select(.reason == "compiler-artifact" and (.target.kind | index("staticlib")))
      | [.target.name, (.filenames[] | select(endswith(".a")))] | @tsv'
}

build_libraries() {
  local arch target artifacts name path capi_libs=() core_libs=()
  for arch in $archs; do
    target=$(rust_target "$arch")
    # Captured first, so a failing cargo build stops the script.
    artifacts=$(build_target "$target")
    while IFS=$'\t' read -r name path; do
      case "$name" in
        livesplit_core) capi_libs+=("$path") ;;
        lso_core) core_libs+=("$path") ;;
      esac
    done <<<"$artifacts"
  done
  local count
  count=$(wc -w <<<"$archs")
  if ((${#capi_libs[@]} != count || ${#core_libs[@]} != count)); then
    echo "cargo didn't report both static libraries for: $archs" >&2
    exit 1
  fi
  mkdir -p "$out/lib"
  lipo -create "${capi_libs[@]}" -output "$out/lib/liblivesplit_core.a"
  lipo -create "${core_libs[@]}" -output "$out/lib/liblso_core.a"
}

# The bindings only change with the livesplit-core revision or the features,
# so bind_gen only runs when one of them changed.
generate_bindings() {
  local stamp="$out/Generated/.source"
  local source_id="$capi_dir $features"
  local swift_out="$out/Generated/LiveSplitCore.swift"
  local header_out="$out/CLiveSplitCore/include/livesplit_core.h"
  if [[ -f "$swift_out" && -f "$header_out" && "$(cat "$stamp" 2>/dev/null)" == "$source_id" ]]; then
    return
  fi
  local bindings
  bindings=$(mktemp -d)
  # Removed on any failure too; the success path removes it below.
  trap 'rm -rf "$bindings"' EXIT
  # bind_gen reads ../src relative to its own folder, so it runs from there
  # (where rust-toolchain.toml isn't seen, hence RUSTUP_TOOLCHAIN), and builds
  # into core/target instead of Cargo's checkout.
  (cd "$capi_dir/bind_gen" &&
    RUSTUP_TOOLCHAIN="$toolchain" cargo run --release --quiet \
      --target-dir "$root/core/target/bind_gen" -- \
      --no-default-features --features "$features" --output-dir "$bindings")
  mkdir -p "$out/Generated"
  cp "$bindings/swift/LiveSplitCore/LiveSplitCore.swift" "$swift_out"
  cp "$bindings/swift/CLiveSplitCore/include/livesplit_core.h" "$header_out"
  echo "$source_id" >"$stamp"
  rm -rf "$bindings"
  trap - EXIT
}

# Tells Xcode what this run read, so it skips the phase until one of them
# changes (spec §4.2): core/'s Rust sources (cargo's dependency file), its
# manifest and lock file, the toolchain file and this script.
write_xcode_dependencies() {
  local first depinfo inputs
  first=$(rust_target "${archs%% *}")
  depinfo="$root/core/target/$first/$profile/liblso_core.d"
  inputs=$(cut -d: -f2- "$depinfo")
  mkdir -p "$DERIVED_FILE_DIR"
  echo "$out/lib/liblso_core.a: $inputs $root/core/Cargo.toml $root/core/Cargo.lock" \
    "$root/rust-toolchain.toml $root/scripts/build-core.sh" >"$DERIVED_FILE_DIR/build-core.d"
}

generate_bindings
if $bindings_only; then
  exit 0
fi
build_libraries
if [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
  write_xcode_dependencies
fi
