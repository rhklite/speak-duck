// probe.swift — read-only: is the current audio visible to MediaRemote?
// Build & run while YouTube Music is playing:
//   swiftc probe.swift -o probe && ./probe
import Foundation

typealias InfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let h = dlopen(path, RTLD_NOW) else { print("dlopen FAILED"); exit(1) }
guard let pInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"),
      let pPlay = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
    print("dlsym FAILED — symbols missing"); exit(1)
}
let getInfo = unsafeBitCast(pInfo, to: InfoFn.self)
let getIsPlaying = unsafeBitCast(pPlay, to: IsPlayingFn.self)

let group = DispatchGroup()
group.enter()
getIsPlaying(.main) { p in print("MediaRemote isPlaying = \(p)"); group.leave() }
group.enter()
getInfo(.main) { info in
    if let d = info {
        let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = d["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        print("nowPlaying: title=\(title ?? "nil") artist=\(artist ?? "nil") keyCount=\(d.count)")
    } else {
        print("nowPlaying info = NIL (nothing visible to MediaRemote)")
    }
    group.leave()
}
group.notify(queue: .main) { exit(0) }
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { print("(timeout)"); exit(0) }
RunLoop.main.run()
