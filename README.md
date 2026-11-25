<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/soundconnect/png/soundconnect-lockup-horizontal-on-dark-1600.png">
    <img alt="Sound Connect" src="brand/soundconnect/png/soundconnect-lockup-horizontal-1600.png" width="560">
  </picture>
</p>

# Sound Connect

An independent, open-source companion app for Sony headphones on macOS, with
iOS, Android and Windows versions in progress. It talks to the headphones
directly over Bluetooth, using the same control channel as Sony's own app, so
noise cancelling, the equaliser, battery and other settings work from your
computer.

> **Not affiliated with Sony.** This is not Sony's Sound Connect app and is
> not made, endorsed or supported by Sony. Sony, WH-1000XM6 and related names
> are trademarks of Sony Group Corporation, used here only to say which
> headphones this works with. This project contains no Sony code, images,
> fonts or credentials.

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

## Download

Get the macOS app from
[Releases](https://github.com/evinjohnnn/SonyConnect/releases): open the
`.dmg` and drag Sound Connect to Applications. It needs macOS 26 and runs on
Apple silicon and Intel Macs.

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
brand/soundconnect/        Logo, icons and the usage guide
scripts/                   Build scripts
```

## Build

Needs Rust and Xcode.

```sh
./scripts/build-macos.sh            # release
./scripts/build-macos.sh debug      # debug
```

The script builds the Rust core first, then the Swift package that links it.
The app is `apps/macos/SonyCompanion/.build/out/Products/<Debug|Release>/SonyCompanionApp`;
it shows up as Sound Connect in the Dock and the menu bar.

To make a release build (`dist/Sound Connect.app` and a `.dmg`), run
`./scripts/package-macos.sh`. The comments at the top of the script cover
signing and notarisation.

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
