# SpeakDuck

A tiny macOS menu-bar app that **ducks background audio while Spoken Content is speaking** — it lowers your music/video sound the moment macOS starts reading text aloud, then restores it when speech stops.

Runs in the menu bar only (no Dock icon).

## Install

Download **`SpeakDuck.dmg`** from the [latest release](https://github.com/rhklite/speak-duck/releases/latest), open it, and drag **SpeakDuck** onto **Applications**. Grant the audio permission it requests on first launch.

## Build from source

```sh
./bundle.sh     # compile SpeakDuck.app
./makedmg.sh    # package the drag-to-install SpeakDuck.dmg
```

Requires the Xcode command-line tools (`swiftc`).

- `Engine.swift` — audio-ducking engine
- `SpeakDuckApp.swift` — menu-bar app
- `speak-duck-cyan.svg` — app icon source
