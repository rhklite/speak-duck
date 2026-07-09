// speak-duck.swift — headless CLI entry (debugging). Engine lives in Engine.swift.
//
// Build: swiftc Engine.swift speak-duck.swift -o speak-duck
// Run:   SPEAKDUCK_DEBUG=1 ./speak-duck [level 0..1] [resumeDelay]
//        level 0 = mute (default), e.g. 0.2 = duck background to 20%

import Foundation

@main
struct SpeakDuckCLI {
    static func main() {
        let args = CommandLine.arguments
        let level = args.count > 1 ? (Float(args[1]) ?? 0) : 0
        let delay = args.count > 2 ? (Double(args[2]) ?? 0.6) : 0.6

        let engine = DuckEngine(voiceBundle: "com.apple.accessibility.AXVisualSupportAgent",
                                resumeDelay: delay, duckLevel: level)
        engine.onMute = { m in log(m ? "DUCK" : "RESTORE") }
        guard engine.start() else {
            FileHandle.standardError.write(Data("engine failed to start\n".utf8)); exit(1)
        }
        let pct = Int((level * 100).rounded())
        log("speak-duck (\(pct == 0 ? "mute" : "lower to \(pct)%")) running. resumeDelay=\(delay)s. Ctrl-C to stop.")
        signal(SIGINT, SIG_IGN)
        let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sig.setEventHandler { engine.stop(); exit(0) }
        sig.resume()
        RunLoop.main.run()
    }
}
