# Sony Companion

An independent, open-source companion app for Sony headphones on macOS, with
iOS, Android and Windows versions in progress. It talks to the headphones
directly over Bluetooth, using the same control channel as Sony's own app, so
noise cancelling, the equaliser, battery and other settings work from your
computer.

> **Not affiliated with Sony.** Sony, WH-1000XM6 and related names are
> trademarks of Sony Group Corporation, used here only to say which headphones
> this works with. This project contains no Sony code, images, fonts or
> credentials.

## What works

Tested on a **WH-1000XM6** (firmware 3.1.5). Other models that speak the same
protocol may work; the app only shows settings the headphones report.

- Battery level and charging state
- Noise cancelling, ambient sound and off, ambient level 0–20
- Equaliser presets and a 10-band custom curve
- Music and call volume
- Speak-to-Chat, listening mode (Standard, BGM, Cinema)
- Playback controls and playback state
- Voice guidance, voice assistant, auto power off, pause when removed
- Paired devices: list, connect, disconnect, pairing mode
- A menu bar panel on macOS

## Platforms

| Platform | State |
| --- | --- |
| macOS (SwiftUI) | Main app. Needs macOS 26 |
| macOS CLI (`sonyctl`) | Reads and changes settings from the terminal |
| iOS (SwiftUI) | Builds; needs the headphones' accessory link to connect |
| Android, Windows (Flutter) | Experimental |

## Layout

```
core/                      Rust protocol engine (no I/O, no threads)
  mdr-core/                framing, protocol, session, state, simulator
  mdr-ffi/                 C interface for Swift, Kotlin and Dart
apps/macos/SonyCompanion/  Swift package: MDRKit, sonyctl, the macOS app
apps/ios/SonyCompanion/    iOS app (XcodeGen project)
apps/flutter/              Flutter app for Android and Windows
scripts/                   Build scripts
```

## Build

Needs Rust and Xcode.

```sh
./scripts/build-macos.sh            # release
./scripts/build-macos.sh debug      # debug
```

The script builds the Rust core first, then the Swift package that links it.
The app is `apps/macos/SonyCompanion/.build/out/Products/<Debug|Release>/SonyCompanionApp`.

iOS (simulator):

```sh
cd core && cargo build --release --target aarch64-apple-ios-sim -p mdr-ffi
cd ../apps/ios/SonyCompanion && xcodegen generate
xcodebuild -project SonyCompanionIOS.xcodeproj -scheme SonyCompanionIOS \
  -sdk iphonesimulator -derivedDataPath .build/sim build
```

Android: `./scripts/build-android.sh`.

## Test

```sh
cd core && cargo test
```

The tests cover framing, escaping and checksums, the acknowledgement rules,
the command scheduler, timeouts and retries, and a simulated headset.

## Using `sonyctl`

```sh
BIN=apps/macos/SonyCompanion/.build/out/Products/Debug/sonyctl
$BIN devices
$BIN status WH-1000XM6
```

Only one app can hold the headphones' control channel at a time, so quit
Sony's app (or this one) before using the other.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
