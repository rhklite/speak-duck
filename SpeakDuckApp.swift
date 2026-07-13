// SpeakDuckApp.swift — menu-bar (agent) app. Engine lives in Engine.swift.
//
// Build the .app bundle:  ./bundle.sh
// Run:  open SpeakDuck.app

import AppKit
import ApplicationServices
import ServiceManagement

let TARGET_BUNDLE_ID = "com.apple.accessibility.AXVisualSupportAgent"  // Speak Selection + hover-speak
let RESUME_DELAY: TimeInterval = 0.3

// MARK: - Media-key play/pause

// Synthesize the hardware Play/Pause key (NX_KEYTYPE_PLAY = 16). macOS routes it to
// the current "Now Playing" session — a local app (Music/Spotify/Safari/Chrome) or,
// when the Mac is an AirPlay receiver, forwarded back to the iPhone that's playing.
// Posting to other apps requires this app be trusted for Accessibility (granted once
// in System Settings → Privacy & Security → Accessibility).
private let NX_KEYTYPE_PLAY: Int = 16

func postPlayPauseKey() {
    func post(down: Bool) {
        let state = down ? 0xA : 0xB
        let data1 = (NX_KEYTYPE_PLAY << 16) | (state << 8)
        let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00))
        guard let ev = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8 /* NX_SUBTYPE_AUX_CONTROL_BUTTONS */, data1: data1, data2: -1)
        else { return }
        ev.cgEvent?.post(tap: .cghidEventTap)
    }
    post(down: true); post(down: false)
}

/// True if Accessibility is granted. Passing prompt=true surfaces the system prompt
/// (and adds us to the Accessibility list) the first time pause mode is chosen.
@discardableResult
func accessibilityTrusted(prompt: Bool) -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
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
    private var levelSlider: NSSlider!
    private var levelLabel: NSTextField!
    private var engine: DuckEngine?

    private var muting = false           // an action (duck or pause) is currently active
    private var currentSymbol = ""

    private let modeKey = "mode"
    private var mode: DuckMode = .duck    // default preserves the original ducking behavior

    private let levelKey = "duckLevel"
    private var duckLevel: Float = 0.3   // lower background to 30% by default

    func applicationDidFinishLaunching(_ note: Notification) {
        if let raw = UserDefaults.standard.object(forKey: modeKey) as? Int, let m = DuckMode(rawValue: raw) {
            mode = m
        }
        if UserDefaults.standard.object(forKey: levelKey) != nil {
            duckLevel = Float(UserDefaults.standard.double(forKey: levelKey))
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let engine = DuckEngine(voiceBundle: TARGET_BUNDLE_ID, resumeDelay: RESUME_DELAY, duckLevel: duckLevel)
        engine.mode = mode
        engine.sendPlayPause = { postPlayPauseKey() }
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

    @objc private func selectMode(_ sender: NSMenuItem) {
        setMode(DuckMode(rawValue: sender.tag) ?? .duck)
    }

    private func setMode(_ m: DuckMode) {
        // Pause mode posts media keys to other apps → needs Accessibility. Prompt the
        // first time it's chosen without the grant; the action degrades quietly if denied.
        if m == .pause && !accessibilityTrusted(prompt: false) {
            accessibilityTrusted(prompt: true)
        }
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: modeKey)
        engine?.mode = m
        refresh()
    }

    @objc private func quit() { engine?.stop(); NSApp.terminate(nil) }
}
