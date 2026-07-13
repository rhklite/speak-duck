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

## Modes & triggers (one mechanism)
There is a single suppression mechanism — the Core Audio tap above — and it is the
*only* way media is quieted. It has one knob (a target gain: 0 = full mute, >0 = lower
to that fraction) and is driven by two independent triggers that share the same
begin/resume path. The only difference between them is what turns it on.

A menu radio picks the while-speaking action: **Do nothing** (`.off`) / **Lower volume**
(`.duck`, tap at the slider level) / **Pause media** (`.pause`, tap at gain 0 = full
mute). `DuckEngine.poll()` (0.05 s) computes a target gain from the live triggers via
`desiredGain()`, brings the tap up/down, and applies the 0.3 s resume debounce; the tap
crosses the mute↔partial boundary by tearing down and rebuilding, and a partial-level
change is written live to `gainPtr`.

An earlier design paused only the single *Now Playing* app by synthesizing the
Play/Pause media key. That was dropped: it reached one app at a time (not universal),
depended on flaky Now-Playing registration (Chrome), and needed an Accessibility grant
that ad-hoc re-signing kept invalidating. The tap mutes **every** source at once with
no permission, which is what "pause all media" actually requires.

## Pause while dictating
A second trigger for the same tap, independent of the while-speaking mode: whenever a
dictation app holds the mic, full-mute all output so playback doesn't bleed into the
transcription. Detection mirrors the Spoken-Content output check on the input side —
any process whose bundle id starts with `com.electron.wispr-flow` reporting
`kAudioProcessPropertyIsRunningInput != 0`. Validated: Wispr Flow's helper flips that
flag only while actively dictating and clears it on stop. `desiredGain()` returns 0
(full mute) whenever this trigger is active, so it wins over a concurrent duck. Menu
toggle "Pause media while dictating", on by default; turn off Wispr Flow's own mute so
the two don't both act.

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
