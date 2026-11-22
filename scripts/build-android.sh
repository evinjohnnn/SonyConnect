#!/bin/sh
# Build the Android APK with the Rust engine packaged for each ABI.
#
# Prerequisites (installed on this workstation):
#   Android SDK 36, build-tools 36.0.0, NDK 28.2.13676358
#   rustup targets: aarch64-linux-android, armv7-linux-androideabi, x86_64-linux-android
#   cargo-ndk
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK=${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}
NDK=${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}
export ANDROID_SDK_ROOT="$SDK"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_HOME="$SDK"

command -v cargo-ndk >/dev/null 2>&1 || cargo install cargo-ndk --locked
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

JNI="$ROOT/apps/flutter/sony_companion/android/app/src/main/jniLibs"
mkdir -p "$JNI"
cd "$ROOT/core"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$JNI" build --release

cd "$ROOT/apps/flutter/sony_companion"
flutter build apk --release
