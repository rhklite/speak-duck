# Changelog

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
