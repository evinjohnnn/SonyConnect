#!/usr/bin/env bash
# Build the macOS command-line harness.
#
# Two stages, both required:
#   1. Cargo builds the shared Rust core as a static library.
#   2. SwiftPM links the Swift UI/transport layer against it.
#
# SwiftPM cannot build Rust, so this script is the single entry point.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

mode="${1:-release}"

echo "==> building Rust core (release, always)"
# The Swift package links a fixed path (core/target/release), so the core is
# always built in release mode even when the Swift side is debug.
cargo build --release --manifest-path "$root/core/Cargo.toml"

echo "==> building sonyctl ($mode)"
cd "$root/apps/macos/SonyCompanion"
if [[ "$mode" == "debug" ]]; then
    swift build
    echo "binary: $(swift build --show-bin-path)/sonyctl"
else
    swift build -c release
    echo "binary: $(swift build -c release --show-bin-path)/sonyctl"
fi
