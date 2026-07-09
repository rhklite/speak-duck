// discover.swift — identify which process emits audio when macOS speaks.
//
// Run:   swift discover.swift
// Then:  trigger "Speak Selection" (your shortcut) AND "Speak item under the
//        pointer" (hover). Watch which bundle id / executable flips to active.
// Stop:  Ctrl-C.
//
// Doubles as a permission probe: if it prints process data at all, then reading
// process audio state needs no TCC/Accessibility grant. If the list is always
// empty, the process-tap permission is required for this info.

import CoreAudio
import Darwin
import Foundation

func processList() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func uint32Prop(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var addr = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
    return value
}

func pidProp(_ obj: AudioObjectID) -> pid_t {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: pid_t = -1
    var size = UInt32(MemoryLayout<pid_t>.size)
    _ = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
    return value
}

func bundleID(_ obj: AudioObjectID) -> String? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(obj, &addr) else { return nil }
    var size = UInt32(MemoryLayout<CFString?>.size)
    var result: Unmanaged<CFString>? = nil
    guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &result) == noErr,
          let r = result else { return nil }
    let s = r.takeRetainedValue() as String
    return s.isEmpty ? nil : s
}

func execPath(_ pid: pid_t) -> String {
    guard pid > 0 else { return "(unknown)" }
    var buf = [CChar](repeating: 0, count: 4096)
    let len = proc_pidpath(pid, &buf, UInt32(buf.count))
    return len > 0 ? String(cString: buf) : "(pid \(pid))"
}

func label(_ obj: AudioObjectID) -> String {
    let pid = pidProp(obj)
    let id = bundleID(obj) ?? execPath(pid)
    return "\(id) [pid \(pid)]"
}

let stamp = DateFormatter()
stamp.dateFormat = "HH:mm:ss.SSS"

print("Watching process audio output. Trigger Speak Selection + hover-speak now. Ctrl-C to stop.\n")
var previous = Set<String>()
while true {
    var active = Set<String>()
    for obj in processList() where uint32Prop(obj, kAudioProcessPropertyIsRunningOutput) != 0 {
        active.insert(label(obj))
    }
    if active != previous {
        let now = stamp.string(from: Date())
        let started = active.subtracting(previous).map { "+ \($0)" }
        let stopped = previous.subtracting(active).map { "- \($0)" }
        for line in (started + stopped).sorted() { print("\(now)  \(line)") }
        previous = active
    }
    Thread.sleep(forTimeInterval: 0.2)
}
