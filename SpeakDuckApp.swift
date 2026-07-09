// SpeakDuckApp.swift — menu-bar (agent) app. Engine lives in Engine.swift.
//
// Build the .app bundle:  ./bundle.sh
// Run:  open SpeakDuck.app

import AppKit
import ServiceManagement

let TARGET_BUNDLE_ID = "com.apple.accessibility.AXVisualSupportAgent"  // Speak Selection + hover-speak
let RESUME_DELAY: TimeInterval = 0.6

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
    private var enableItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var levelSlider: NSSlider!
    private var levelLabel: NSTextField!
    private var engine: DuckEngine?

    private var muting = false
    private var currentSymbol = ""

    private let enabledKey = "enabled"
    private var enabled = true

    private let levelKey = "duckLevel"
    private var duckLevel: Float = 0.3   // lower background to 30% by default

    func applicationDidFinishLaunching(_ note: Notification) {
        enabled = (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true
        if UserDefaults.standard.object(forKey: levelKey) != nil {
            duckLevel = Float(UserDefaults.standard.double(forKey: levelKey))
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let engine = DuckEngine(voiceBundle: TARGET_BUNDLE_ID, resumeDelay: RESUME_DELAY, duckLevel: duckLevel)
        engine.enabled = enabled
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
        if !enabled { return "waveform.slash" }
        if muting { return duckLevel <= 0 ? "speaker.slash.fill" : "speaker.wave.1.fill" }
        return "waveform"
    }

    private func refresh() {
        let sym = desiredSymbol()
        if sym != currentSymbol {
            currentSymbol = sym
            let img = NSImage(systemSymbolName: sym, accessibilityDescription: "speak-duck")
            img?.isTemplate = true
            statusItem.button?.image = img
        }
        let action = duckLevel <= 0 ? "muted" : "lowered"
        statusLine?.title = !enabled ? "Off" : (muting ? "Media \(action) — speaking…" : "Active — waiting for speech")
        enableItem?.state = enabled ? .on : .off
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
        enableItem = NSMenuItem(title: "Lower audio while speaking",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)

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

    @objc private func toggleEnabled() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        engine?.enabled = enabled
        refresh()
    }

    @objc private func quit() { engine?.stop(); NSApp.terminate(nil) }
}
