// taptest.swift — STEP 1 of the universal ducker: safely confirm a system audio
// tap captures audio (and whether it captures AirPlay). Mutes nothing, changes no
// routing — it only reads the tap mix and prints the peak level.
//
// Build: swiftc taptest.swift -o taptest
// Run:   ./taptest   (Ctrl-C to stop; nothing to restore)
//
// macOS 14.4+ only. May prompt once for audio-recording permission.

import AudioToolbox
import CoreAudio
import Foundation

setvbuf(stdout, nil, _IONBF, 0)   // unbuffered so piped output appears immediately

func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

func defaultOutputDevice() -> AudioObjectID {
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
    var dev = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
    return dev
}

func deviceUID(_ dev: AudioObjectID) -> String? {
    var a = addr(kAudioDevicePropertyDeviceUID)
    var cf: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &cf) == noErr, let cf else { return nil }
    return cf.takeRetainedValue() as String
}

// --- Create a global tap (exclude nothing), unmuted so audio is untouched ---
let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDesc.name = "speak-duck-observe"
tapDesc.isPrivate = true
tapDesc.muteBehavior = .unmuted
var tapID = AudioObjectID(kAudioObjectUnknown)
let tapErr = AudioHardwareCreateProcessTap(tapDesc, &tapID)
guard tapErr == noErr else {
    print("tap create failed: OSStatus \(tapErr) (needs macOS 14.4+ and audio-recording permission)")
    exit(1)
}
let tapUID = tapDesc.uuid.uuidString

// --- Private aggregate device wrapping the tap (clocked off the output device) ---
let outDev = defaultOutputDevice()
guard let outUID = deviceUID(outDev) else { print("no output device UID"); exit(1) }
let aggDict: [String: Any] = [
    kAudioAggregateDeviceNameKey: "speak-duck-agg",
    kAudioAggregateDeviceUIDKey: "speak-duck-agg-\(getpid())",
    kAudioAggregateDeviceMainSubDeviceKey: outUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
    kAudioAggregateDeviceTapListKey: [[
        kAudioSubTapDriftCompensationKey: true,
        kAudioSubTapUIDKey: tapUID,
    ]],
]
var aggID = AudioObjectID(kAudioObjectUnknown)
let aggErr = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &aggID)
guard aggErr == noErr else { print("aggregate create failed: OSStatus \(aggErr)"); exit(1) }

// --- IOProc: measure peak of the tapped mix; output left silent ---
let lock = NSLock()
var peak: Float = 0
var cbCount = 0
var bufCount = 0
var maxBytes: UInt32 = 0
var everNonZero = false
var ioProc: AudioDeviceIOProcID?
let block: AudioDeviceIOBlock = { _, inInput, _, _, _ in
    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
    var local: Float = 0
    var mb: UInt32 = 0
    for buf in list {
        if buf.mDataByteSize > mb { mb = buf.mDataByteSize }
        guard let data = buf.mData else { continue }
        let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        let s = data.assumingMemoryBound(to: Float.self)
        for i in 0..<n { let v = abs(s[i]); if v > local { local = v } }
    }
    lock.lock()
    cbCount += 1; bufCount = list.count
    if mb > maxBytes { maxBytes = mb }
    if local > peak { peak = local }
    if local > 0 { everNonZero = true }
    lock.unlock()
}
guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggID, nil, block) == noErr, ioProc != nil else {
    print("IOProc create failed"); exit(1)
}
AudioDeviceStart(aggID, ioProc)

func cleanup() {
    if let p = ioProc { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p) }
    AudioHardwareDestroyAggregateDevice(aggID)
    AudioHardwareDestroyProcessTap(tapID)
}

signal(SIGINT, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sig.setEventHandler { print("\ncleaning up…"); cleanup(); exit(0) }
sig.resume()

print("Listening to the system audio tap. Play Chrome music, then AirPlay from iPhone.")
print("A rising bar = that audio IS captured by the tap (so it can be ducked). Ctrl-C to stop.\n")
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
timer.setEventHandler {
    lock.lock()
    let p = peak; let c = cbCount; let b = bufCount; let mx = maxBytes; let nz = everNonZero
    peak = 0
    lock.unlock()
    let bars = Int((min(p, 1) * 30).rounded())
    let bar = String(repeating: "█", count: bars) + String(repeating: "·", count: 30 - bars)
    print(String(format: "level %5.3f |%@| cb=%d buffers=%d maxBytes=%u everAudio=%@",
                 p, bar, c, b, mx, nz ? "YES" : "no"))
}
timer.resume()
RunLoop.main.run()
