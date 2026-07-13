# SpeakDuck

A tiny macOS menu-bar app that quiets background audio while Spoken Content is speaking. Pick a mode from the menu bar:

- **Lower volume** — ducks all background audio (music, video, browser tabs, AirPlay-received) to a level you choose, then restores it. Universal, no permissions.
- **Pause media** — pauses the current *Now Playing* source (Music, Spotify, Safari, Chrome, or an iPhone AirPlaying to this Mac) and resumes it when speech stops. Reaches any Now-Playing-aware source; needs a one-time Accessibility grant.
- **Do nothing** — armed but idle.

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
