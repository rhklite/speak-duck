// SpeakDuckApp.swift — menu-bar (agent) app. Engine lives in Engine.swift.
//
// Build the .app bundle:  ./bundle.sh
// Run:  open SpeakDuck.app

import AppKit
import ServiceManagement

let TARGET_BUNDLE_ID = "com.apple.accessibility.AXVisualSupportAgent"  // Speak Selection + hover-speak
let RESUME_DELAY: TimeInterval = 0.3

// MARK: - MediaRemote pause/play

// Deterministic pause/play of the macOS "Now Playing" session via the private
// MediaRemote framework — the same path Control Center's controls use. Replaces the
// old synthesized play/pause media key, which (a) was a blind TOGGLE that could
// invert state, and (b) is swallowed system-wide on machines where another app
// (dictation tools, Logitech agents) grabs media keys — verified: the key never
// reached players on this setup while MRMediaRemoteSendCommand(pause) worked.
// Needs no Accessibility grant. Send-command is not gated (the now-playing *query*
// functions are, so we don't rely on them).
private enum MediaRemote {
    private typealias SendCommand = @convention(c) (Int32, AnyObject?) -> Bool
    private static let send: SendCommand? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let sym = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendCommand.self)
    }()
    static func pause() { _ = send?(1, nil) }   // kMRPause
    static func play()  { _ = send?(0, nil) }   // kMRPlay
}

@main
struct SpeakDuckApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var offItem: NSMenuItem!
    private var duckItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var dictateItem: NSMenuItem!
    private var levelSlider: NSSlider!
    private var levelLabel: NSTextField!
    private var engine: DuckEngine?

    private var muting = false           // an action (duck or pause) is currently active
    private var currentSymbol = ""

    private let modeKey = "mode"
    private var mode: DuckMode = .duck    // default preserves the original ducking behavior

    private let levelKey = "duckLevel"
    private var duckLevel: Float = 0.3   // lower background to 30% by default

    private let dictateKey = "pauseWhileDictating"
    private var pauseWhileDictating = true   // pause media while dictating, on by default

    func applicationDidFinishLaunching(_ note: Notification) {
        if let raw = UserDefaults.standard.object(forKey: modeKey) as? Int, let m = DuckMode(rawValue: raw) {
            mode = m
        }
        if UserDefaults.standard.object(forKey: levelKey) != nil {
            duckLevel = Float(UserDefaults.standard.double(forKey: levelKey))
        }
        if UserDefaults.standard.object(forKey: dictateKey) != nil {
            pauseWhileDictating = UserDefaults.standard.bool(forKey: dictateKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let engine = DuckEngine(voiceBundle: TARGET_BUNDLE_ID, resumeDelay: RESUME_DELAY, duckLevel: duckLevel)
        engine.mode = mode
        engine.pauseWhileDictating = pauseWhileDictating
        engine.sendPause = { MediaRemote.pause() }
        engine.sendPlay = { MediaRemote.play() }
        engine.onMute = { [weak self] m in self?.muting = m; self?.refresh() }
        engine.start()
        self.engine = engine

        setupLoginItemIfNeeded()   // honor the one-time "launch at login" choice
        buildMenu()
        refresh()
    }

    // MARK: Login item

    private var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private func setupLoginItemIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "loginSetupDone") else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: "loginSetupDone")
    }

    @objc private func toggleLogin() {
        do {
            if loginEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { dlog("login toggle error: \(error)") }
        refresh()
    }

    // MARK: Indicator

    private func desiredSymbol() -> String {
        switch mode {
        case .off:   return "waveform.slash"
        case .duck:  return muting ? (duckLevel <= 0 ? "speaker.slash.fill" : "speaker.wave.1.fill") : "waveform"
        case .pause: return muting ? "pause.fill" : "playpause"
        }
    }

    private func statusText() -> String {
        switch mode {
        case .off:   return "Off"
        case .duck:  return muting ? "Media \(duckLevel <= 0 ? "muted" : "lowered") — speaking…" : "Active — waiting for speech"
        case .pause: return muting ? "Media paused — speaking…" : "Active — waiting for speech"
        }
    }

    private func refresh() {
        let sym = desiredSymbol()
        if sym != currentSymbol {
            currentSymbol = sym
            let img = NSImage(systemSymbolName: sym, accessibilityDescription: "speak-duck")
            img?.isTemplate = true
            statusItem.button?.image = img
        }
        statusLine?.title = statusText()
        offItem?.state   = mode == .off   ? .on : .off
        duckItem?.state  = mode == .duck  ? .on : .off
        pauseItem?.state = mode == .pause ? .on : .off
        // The level slider only applies to ducking; grey it out in the other modes.
        levelSlider?.isEnabled = (mode == .duck)
        levelLabel?.textColor  = (mode == .duck) ? .secondaryLabelColor : .tertiaryLabelColor
        dictateItem?.state = pauseWhileDictating ? .on : .off
        loginItem?.state = loginEnabled ? .on : .off
    }

    private func levelText() -> String {
        duckLevel <= 0 ? "Mute background while speaking"
                       : "Lower background to \(Int((duckLevel * 100).rounded()))%"
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())
        let header = NSMenuItem(title: "While speaking:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        offItem   = addModeItem("Do nothing", mode: .off, to: menu)
        duckItem  = addModeItem("Lower volume", mode: .duck, to: menu)
        pauseItem = addModeItem("Pause media", mode: .pause, to: menu)

        menu.addItem(makeLevelItem())

        menu.addItem(.separator())
        dictateItem = NSMenuItem(title: "Pause media while dictating",
                                 action: #selector(toggleDictate), keyEquivalent: "")
        dictateItem.target = self
        menu.addItem(dictateItem)

        loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit speak-duck", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: Level slider

    private func makeLevelItem() -> NSMenuItem {
        let item = NSMenuItem()
        let width: CGFloat = 240, height: CGFloat = 46
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let label = NSTextField(labelWithString: levelText())
        label.frame = NSRect(x: 20, y: 24, width: width - 40, height: 16)
        label.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor

        let slider = NSSlider(value: Double(duckLevel), minValue: 0, maxValue: 1,
                              target: self, action: #selector(levelChanged(_:)))
        slider.frame = NSRect(x: 20, y: 4, width: width - 40, height: 20)
        slider.isContinuous = true

        container.addSubview(label)
        container.addSubview(slider)
        item.view = container
        levelLabel = label
        levelSlider = slider
        return item
    }

    @objc private func levelChanged(_ sender: NSSlider) {
        duckLevel = Float(sender.doubleValue)
        UserDefaults.standard.set(Double(duckLevel), forKey: levelKey)
        engine?.duckLevel = duckLevel
        levelLabel?.stringValue = levelText()
        refresh()
    }

    private func addModeItem(_ title: String, mode m: DuckMode, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
        item.target = self
        item.tag = m.rawValue
        menu.addItem(item)
        return item
    }

    @objc private func toggleDictate() {
        pauseWhileDictating.toggle()
        UserDefaults.standard.set(pauseWhileDictating, forKey: dictateKey)
        engine?.pauseWhileDictating = pauseWhileDictating
        refresh()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        setMode(DuckMode(rawValue: sender.tag) ?? .duck)
    }

    private func setMode(_ m: DuckMode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: modeKey)
        engine?.mode = m
        refresh()
    }

    @objc private func quit() { engine?.stop(); NSApp.terminate(nil) }
}
