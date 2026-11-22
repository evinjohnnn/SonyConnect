import SwiftUI
import AppKit
import MDRKit

/// Preference keys shared by the Settings window and the scenes that read them.
enum Pref {
    static let autoConnect = "autoConnect"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let headphoneFinish = "headphoneFinish"
    static let useProductImages = "useProductImages"
    static let productImagesFolder = "productImagesFolder"
    /// Per headphone address: whether it has reported a music volume, so
    /// its slider's place is kept while the volume is still on its way.
    static func hasVolume(_ address: String) -> String { "hasVolume.\(address)" }
}

/// Window-independent UI requests that come from the menu bar, so a command
/// can ask for a confirmation the main window then presents.
final class AppUI: ObservableObject {
    @Published var confirmingPowerOff = false
    /// The headphones the window shows.
    @Published var selection: PairedDevice.ID?
}

@main
struct SonyCompanionApp: App {
    @StateObject private var session = HeadphoneSession()
    @StateObject private var ui = AppUI()
    @AppStorage(Pref.showMenuBarExtra) private var showMenuBarExtra = true

    init() {
        // SwiftPM executables start as accessory apps; make the window behave
        // like a normal app (Dock icon, focusable, Cmd-Tab).
        NSApplication.shared.setActivationPolicy(.regular)

        // The app follows the system appearance. Design-review aid:
        // `SONY_UI_APPEARANCE=light|dark` forces one without changing it.
        switch ProcessInfo.processInfo.environment["SONY_UI_APPEARANCE"] {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: NSApplication.shared.appearance = nil
        }
        DesignSnapshot.scheduleIfRequested()
    }

    var body: some Scene {
        // One main window: the menu bar panel's "Settings…" brings it
        // forward instead of opening another copy.
        Window("Sony Companion", id: "main") {
            ContentView()
                .environmentObject(session)
                .environmentObject(ui)
                .frame(minWidth: 460, minHeight: 640)
                // No scroll bars: the page scrolls by trackpad and wheel.
                .scrollIndicators(.never)
                .onAppear {
                    DesignSnapshot.showPanelIfRequested(MenuBarPanel().environmentObject(session).environmentObject(ui))
                }
        }
        // A tall 2:3 window, like a companion app beside your work.
        .defaultSize(width: 600, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            HeadphoneCommands(session: session, ui: ui)
        }

        // The frame log is a tool window, not a modal: it stays open beside
        // the main window while settings change.
        Window("Activity", id: "activity") {
            ActivityWindow()
                .environmentObject(session)
                .scrollIndicators(.never)
        }
        .defaultSize(width: 640, height: 460)
        .keyboardShortcut("l", modifiers: [.command, .option])

        // Design review: the menu bar panel in a window, which a script can
        // capture (`SONY_UI_PANEL=1`).
        Window("Panel Preview", id: "panel-preview") {
            MenuBarPanel()
                .environmentObject(session)
                .environmentObject(ui)
                .background(.regularMaterial)
        }
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView()
                .scrollIndicators(.never)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarPanel()
                .environmentObject(session)
                .environmentObject(ui)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        guard session.connected != nil else { return "headphones" }
        switch session.status.noiseControl {
        case .noiseCancelling: return NoiseControlChoice.noiseCancelling.uiSymbol
        case .ambient: return NoiseControlChoice.ambient.uiSymbol
        default: return "headphones"
        }
    }
}

/// The Headphones menu: every control the window offers that a keyboard user
/// would reach for, with standard-style shortcuts.
struct HeadphoneCommands: Commands {
    @ObservedObject var session: HeadphoneSession
    @ObservedObject var ui: AppUI

    var body: some Commands {
        CommandMenu("Headphones") {
            // Which headphones the window shows. An LE_ entry is listed only
            // when its classic twin is missing: it has no control channel.
            let all = PairedDevice.preferred(session.devices)
            let classic = Set(all.filter { !$0.isLEEntry }.map(\.name))
            let choices = all.filter { !$0.isLEEntry || !classic.contains(String($0.name.dropFirst(3))) }
            if !choices.isEmpty {
                Picker("Headphones", selection: $ui.selection) {
                    ForEach(choices) { device in
                        Text(device.displayName).tag(PairedDevice.ID?.some(device.id))
                    }
                }
                .pickerStyle(.inline)
                Divider()
            }

            Picker("Noise Control", selection: Binding(
                get: { session.status.noiseControl.choice },
                set: { if let choice = $0 { session.setNoiseControl(choice) } }
            )) {
                Text("Noise Cancelling")
                    .tag(NoiseControlChoice?.some(.noiseCancelling))
                    .keyboardShortcut("1")
                Text("Ambient Sound")
                    .tag(NoiseControlChoice?.some(.ambient))
                    .keyboardShortcut("2")
                Text("Off")
                    .tag(NoiseControlChoice?.some(.off))
                    .keyboardShortcut("3")
            }
            .pickerStyle(.inline)
            .disabled(!session.isReady)

            Divider()

            Button("Refresh Status") { session.refreshStatus() }
                .keyboardShortcut("r")
                .disabled(!session.isReady)
            Button("Disconnect") { session.disconnect() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(session.connected == nil)
            Button("Rescan Paired Devices") { session.refreshDevices() }
            Button("Open Bluetooth Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Power Off Headphones…") { ui.confirmingPowerOff = true }
                .disabled(!session.isReady)
        }
    }
}

extension NoiseControlView {
    /// The user-facing mode, or nil before the device has reported one.
    var choice: NoiseControlChoice? {
        switch self {
        case .noiseCancelling: return .noiseCancelling
        case .ambient: return .ambient
        case .off: return .off
        case .unknown: return nil
        }
    }
}
