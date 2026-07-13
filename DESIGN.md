# speak-duck

Lowers all background audio to a chosen level while macOS *Spoken Content* (Speak
Selection / Speak item under the pointer) is talking, then restores it —
system-wide, for any source (apps, browser tabs, AirPlay-received audio), with the
speech voice itself left clear. The menu-bar app has a slider to pick the level
(0% = full mute, e.g. 30% = background ducked to 30%).

## How it works (final)
- **Trigger**: both Speak Selection and hover-speak run through the audio process
  `com.apple.accessibility.AXVisualSupportAgent` (found via `discover.swift`).
  A 0.12 s poll watches its `kAudioProcessPropertyIsRunningOutput`.
- **Action**: on speech, create a global Core Audio **process tap**
  (`CATapDescription(stereoGlobalTapButExcludeProcesses:)`, `muteBehavior = .muted`)
  that **excludes the voice process**, wrapped in a private aggregate device.
  The tap mutes all *other* audio from the normal output path and captures it; the
  aggregate's IOProc re-injects that captured audio at `duckLevel` gain (0 = leave
  silent, 1 = full). The voice keeps playing untouched. On speech end (+0.6 s
  debounce) the tap is torn down → audio restored.
- **On-demand**: the tap exists ONLY during speech. At idle there is no tap, so
  normal audio is never touched. If the app dies, the tap dies with it.
- **No permissions**: the tap needs no TCC grant on this macOS (14.4+ required;
  built on macOS 26). Needs `kAudioAggregateDeviceTapAutoStartKey` + a unique
  aggregate UID per process.

## Partial-volume ducking (capture + replay)
Writing into the aggregate's own IOProc **output** buffers never reaches the
speakers (re-verified 2026-07: any non-zero level still produced full mute).
Working architecture instead:

1. Tap (`muteBehavior = .muted`) silences background and hands us its audio in the
   aggregate IOProc's **input** buffers → written to a lock-free SPSC ring buffer.
2. A second IOProc on the **real default output device** reads the ring and plays
   it back scaled by `duckLevel` — a normal audio client, mixed by coreaudiod.
3. Our own process object is excluded from the tap (alongside the voice) so the
   replay isn't re-captured → no feedback loop. Doing IO on the replay device is
   what registers our process object (`kAudioHardwarePropertyTranslatePIDToProcessObject`).

`duckLevel` 0 skips replay entirely — identical to the original full-mute. If our
process object can't be resolved, the engine falls back to full mute (logged).
Assumes Float32 PCM stereo in buffer 0 on both sides (standard). Latency = ring
transit, ~one IO cycle. Test: `./speak-duck 0.2` + Speak Selection over music.

Earlier dead ends (kept for the record): MediaRemote (gated / blind to Chrome),
synthesized media keys (Chrome not in Now Playing), per-tab AppleScript+JS
(worked but Chrome-only). All replaced by the universal tap.

## Pause mode (MediaRemote)
A menu radio picks the action taken while speaking: **Do nothing** / **Lower volume**
(the tap above) / **Pause media**. One action runs at a time — pause does *not* also
duck. The mode lives on `DuckEngine` (`.off/.duck/.pause`); the same 0.05 s poll and
0.3 s resume debounce drive both duck and pause, and changing mode live unwinds
whatever was active (restores volume / resumes media) so media is never left stuck.

Pause sends **deterministic `MRMediaRemoteSendCommand` pause/play** (private
MediaRemote framework via `dlopen`) — the same path Control Center's Now Playing
controls use, reaching Music/Spotify/Safari/modern Chrome and iPhone→Mac AirPlay.
An earlier iteration synthesized the hardware Play/Pause key instead; that was
dropped after verifying (QuickTime A/B test, 2026-07-13) that media-key events are
swallowed system-wide on this setup (dictation tools / Logitech agents grab them)
while the MediaRemote command paused reliably. Explicit pause+play also can't
invert state the way a blind key *toggle* could. Note: only send-command works —
the now-playing *query* functions (`MRMediaRemoteGetNowPlaying*`) are gated on
macOS 15.4+ and return empty, so the engine never relies on them.

Guards & caveats:
- Resume ("play") fires only if we actually paused, and pause is skipped when no
  media is playing (any non-voice, non-self, non-dictation process with
  `IsRunningOutput`) — else the trailing "play" would start playback the user never
  had. The dictation app is excluded from that check because its helper keeps an
  output stream running even when idle.
- **No permissions**: MediaRemote send needs no Accessibility/TCC grant (the old
  media-key path did, and re-signing kept invalidating it).
- Only the single Now Playing session is paused (not every source at once, the way
  ducking mutes everything). Verify AirPlay-from-iPhone routing on hardware.

## Pause while dictating
A separate trigger, independent of the while-speaking mode: whenever a dictation app
holds the mic, pause the Now Playing source so playback doesn't bleed into the
transcription. Detection mirrors the Spoken-Content output check on the input side —
poll for any process whose bundle id starts with `com.electron.wispr-flow` reporting
`kAudioProcessPropertyIsRunningInput != 0`. Validated: Wispr Flow's helper flips that
flag only while actively dictating and clears it on stop, so the same 0.3 s resume
debounce applies. Always pauses (never ducks) and reuses the same MediaRemote
pause/play path. Menu toggle "Pause media while dictating", on by default; turn off
Wispr Flow's own mute so the two don't both act.

## Files
- `Engine.swift` — tap-based mute engine + Core Audio helpers.
- `SpeakDuckApp.swift` — menu-bar app. `speak-duck.swift` — headless CLI (debug).
- `bundle.sh` — builds/signs `SpeakDuck.app`. `discover.swift` — finds the voice
  process. `taptest.swift` / `mutetest.swift` — tap diagnostics.

## Menu-bar icon
`waveform` = armed; `speaker.wave.1.fill` = lowering during speech;
`speaker.slash.fill` = muting (level 0) during speech; `waveform.slash` = disabled.

## Milestones
- [x] Identify voice process; duck universally during speech; menu-bar app.
- [x] Partial-% ducking via tap re-injection + level slider (verify on hardware).
- [ ] Launch at login.
