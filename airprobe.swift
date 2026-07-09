// airprobe.swift — can the Mac SEE and CONTROL the AirPlay session?
// Build & run while iPhone is casting audio to the Mac and playing:
//   swiftc airprobe.swift -o airprobe && ./airprobe
import Foundation

typealias InfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
typealias SendCmdFn = @convention(c) (Int32, CFDictionary?) -> Bool

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let h = dlopen(path, RTLD_NOW) else { print("dlopen FAILED"); exit(1) }
guard let pi = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"),
      let pp = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
      let ps = dlsym(h, "MRMediaRemoteSendCommand") else { print("dlsym FAILED"); exit(1) }
let getInfo = unsafeBitCast(pi, to: InfoFn.self)
let getPlaying = unsafeBitCast(pp, to: IsPlayingFn.self)
let sendCmd = unsafeBitCast(ps, to: SendCmdFn.self)

func snapshot(_ label: String, _ done: @escaping () -> Void) {
    let g = DispatchGroup()
    g.enter(); getPlaying(.main) { print("[\(label)] isPlaying = \($0)"); g.leave() }
    g.enter(); getInfo(.main) { info in
        let t = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let a = info?["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        print("[\(label)] title=\(t ?? "nil") artist=\(a ?? "nil") keys=\(info?.count ?? 0)")
        g.leave()
    }
    g.notify(queue: .main, execute: done)
}

snapshot("before") {
    let okPause = sendCmd(1, nil)            // kMRPause
    print(">> sent PAUSE → returned \(okPause)  (watch: did the audio stop?)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        snapshot("after-pause") {
            let okPlay = sendCmd(0, nil)     // kMRPlay
            print(">> sent PLAY → returned \(okPlay)  (watch: did it resume?)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { print("(timeout)"); exit(0) }
RunLoop.main.run()
