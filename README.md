# SpeakDuck

A tiny macOS menu-bar app that quiets background audio while Spoken Content is speaking. Pick a mode from the menu bar:

- **Lower volume** — ducks all background audio (music, video, browser tabs, AirPlay-received) to a level you choose, then restores it.
- **Pause media** — fully mutes all background audio while speech plays, then restores it.
- **Do nothing** — armed but idle.

Both use one mechanism: a Core Audio tap that lowers or mutes **every** output source at once (not a single app), so it's universal and needs no permissions.

Independently of the mode above, **Pause media while dictating** (on by default) mutes all audio whenever a dictation app (e.g. Wispr Flow) holds the microphone — so your media doesn't bleed into what you're dictating — and restores it when you stop. It's the same suppression, just triggered by the mic instead of the screen reader. Toggle it from the menu; disable your dictation app's own "mute audio" setting so only SpeakDuck acts.

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
