# Changelog

## 1.1.4 — 2026-07-17

### Fixed
- Triggering a read or dictation while a **FaceTime/AirPlay call** or a
  **notification/alert sound** was audible could inadvertently **unpause media the
  user had already paused**. The audibility probe measured *global* output, so
  non-pausable system audio (FaceTime via `avconferenced`, alert sounds via
  `systemsoundserverd`) counted as "media playing" — arming a resume that then
  fired a global MediaRemote PLAY on trigger-clear. These daemons are now excluded
  from both the playing-check and the probe, exactly like the dictation app.
- The probe now **fails closed**: if the capture tap can't be built it treats
  output as silent (skip the pause) instead of failing open and arming a resume,
  removing an intermittent path back to the same spurious-unpause bug.

## 1.1.3 — 2026-07-13

### Fixed
- The distributed DMG shipped an app whose code signature was invalidated by a
  `com.apple.FinderInfo` xattr that Finder writes during the DMG icon-layout step,
  so macOS could report **"SpeakDuck is damaged and can't be opened"** even after
  clearing the download quarantine. `makedmg.sh` now strips that xattr and
  re-verifies the signature before packaging.

### Docs
- README documents the one-time `xattr -dr com.apple.quarantine` step (or Settings
  ▸ Privacy & Security ▸ Open Anyway) needed because the app is self-signed rather
  than Apple-notarized.

## 1.1.2 — 2026-07-13

### Fixed
- The 1.1.1 audibility check never detected playing media, so pause-on-read and
  pause-on-dictation stopped firing: its 120 ms sampling window was shorter than
  the audio tap's ~175 ms warm-up, so it always read silence. The probe now
  samples up to 600 ms with early exit (~200 ms typical when media is playing).
- Debug logging is now unbuffered, and SPEAKDUCK_PROBE_TEST=1 runs a one-shot
  probe self-test at launch.

## 1.1.1 — 2026-07-13

### Fixed
- Ending dictation (or a read) no longer restarts media the user had already
  paused. Players like Chrome keep their audio output unit open for a while after
  pausing, which fooled the playing-media guard into arming a resume. The guard now
  verifies audible audio by briefly sampling the output mix with a capture-only tap
  before arming the resume.

## 1.1.0 — 2026-07-13

### Added
- **Pause media while dictating**: while a dictation app (Wispr Flow) holds the
  microphone, the Now Playing source is paused and resumed automatically — the same
  pause/resume as pause mode, just triggered by the mic instead of the screen
  reader. Menu toggle, on by default.
- Stable self-signed code-signing identity so TCC grants survive rebuilds.

### Changed
- **Pause now uses MediaRemote** (deterministic `pause`/`play` commands, the same
  path as Control Center) instead of synthesizing the Play/Pause media key. The key
  was swallowed system-wide by other agents on some setups and, being a toggle,
  could invert state. No Accessibility permission is needed anymore.
- Faster response: speech/dictation detection poll 0.12 s → 0.05 s, resume debounce
  0.6 s → 0.3 s.

### Fixed
- DMG showed the app as a plain folder (a forced Finder custom-icon flag with no
  icon resource behind it).
- Build could silently produce an unsigned app when the Syncthing-synced source
  folder re-tagged files mid-build; the bundle is now assembled and signed in a
  temp directory.
- The "is media playing" guard no longer counts the dictation helper's always-on
  output stream as playing media.

## 1.0 — 2026-06-24

- Initial release: menu-bar app that lowers or mutes all background audio while
  macOS Spoken Content is speaking, via a global Core Audio process tap with the
  voice excluded. Modes: Do nothing / Lower volume (slider) / Pause media.
  Launch-at-login support.
