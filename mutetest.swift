// mutetest.swift — does a muteBehavior=.muted tap capture real audio or silence?
// If peak > 0, the tap sees pre-mute audio (re-render is feasible). If peak == 0,
// a muted tap yields silence and partial-volume re-render is impossible this way.
import AudioToolbox
import CoreAudio
import Foundation
setvbuf(stdout, nil, _IONBF, 0)

func addr(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}
func defOut() -> AudioObjectID {
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice); var d = AudioObjectID(0); var sz = UInt32(4)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &d); return d
}
func uid(_ dev: AudioObjectID) -> String? {
    var a = addr(kAudioDevicePropertyDeviceUID); var cf: Unmanaged<CFString>?; var sz = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &cf) == noErr, let cf else { return nil }
    return cf.takeRetainedValue() as String
}

let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tap.name = "mutetest"; tap.isPrivate = true; tap.muteBehavior = .muted
var tapID = AudioObjectID(0)
guard AudioHardwareCreateProcessTap(tap, &tapID) == noErr else { print("tap failed"); exit(1) }
guard let outUID = uid(defOut()) else { print("no uid"); exit(1) }
let dict: [String: Any] = [
    kAudioAggregateDeviceNameKey: "mutetest-agg",
    kAudioAggregateDeviceUIDKey: "mutetest-agg-\(getpid())",
    kAudioAggregateDeviceMainSubDeviceKey: outUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
    kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tap.uuid.uuidString]],
]
var aggID = AudioObjectID(0)
guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID) == noErr else { print("agg failed"); exit(1) }
let lock = NSLock(); var peak: Float = 0
var proc: AudioDeviceIOProcID?
let blk: AudioDeviceIOBlock = { _, input, _, out, _ in
    let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    var p: Float = 0
    for b in ins { if let d = b.mData { let n = Int(b.mDataByteSize)/4; let s = d.assumingMemoryBound(to: Float.self); for i in 0..<n { let a = abs(s[i]); if a>p {p=a} } } }
    lock.lock(); if p>peak {peak=p}; lock.unlock()
    let o = UnsafeMutableAudioBufferListPointer(out); for b in o { if let d = b.mData { memset(d,0,Int(b.mDataByteSize)) } }
}
_ = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, nil, blk)
AudioDeviceStart(aggID, proc)
func cleanup() { if let p = proc { AudioDeviceStop(aggID,p); AudioDeviceDestroyIOProcID(aggID,p) }; AudioHardwareDestroyAggregateDevice(aggID); AudioHardwareDestroyProcessTap(tapID) }
signal(SIGINT, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main); sig.setEventHandler { cleanup(); exit(0) }; sig.resume()
let t = DispatchSource.makeTimerSource(queue: .main); t.schedule(deadline: .now()+0.5, repeating: 0.5)
t.setEventHandler { lock.lock(); let p = peak; peak = 0; lock.unlock(); print(String(format: "muted-tap input peak = %.4f", p)) }
t.resume()
print("measuring muted-tap input (play audio)…")
RunLoop.main.run()
