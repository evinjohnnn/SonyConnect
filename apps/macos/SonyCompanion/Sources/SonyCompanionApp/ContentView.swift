import SwiftUI
import AppKit
import MDRKit

/// One page for the headphones. Only Sony headphones are listed, usually a
/// single pair, so the device list is a toolbar menu rather than a sidebar.
struct ContentView: View {
    @EnvironmentObject private var session: HeadphoneSession
    @AppStorage(Pref.autoConnect) private var autoConnect = true
    /// Shared with the Headphones menu, which chooses between headphones.
    @EnvironmentObject private var ui: AppUI
    private var selection: PairedDevice.ID? {
        get { ui.selection }
        nonmutating set { ui.selection = newValue }
    }
    /// Set once this connection has reached `.ready`, so a later resync or
    /// reconnect stays on the page instead of returning to the stage.
    @State private var readyOnce = false
    /// Pages pushed over the main page. `SONY_UI_PAGE` starts with one
    /// pushed, so it has its back button like any other.
    @State private var path: [SettingsPage] = DesignSnapshot.requestedPage.map { [$0] } ?? []
    /// Counts returns to the main page, which macOS keeps on screen under a
    /// pushed page and so never "appears" again.
    @State private var returns = 0
    @Environment(\.openWindow) private var openWindow
    /// Keeps the stage up for a short "Connected" beat after a fast link,
    /// so the moment reads instead of flashing past.
    @State private var stageHeld = false
    @State private var stageStart = Date()
    /// The first sync counts as done once nothing new has arrived for this
    /// long, or at the cap, whichever comes first.
    private static let syncQuiet: TimeInterval = 0.8
    private static let syncCap: TimeInterval = 3.0
    @Namespace private var stage

    private var headphones: [PairedDevice] { PairedDevice.preferred(session.devices) }

    var body: some View {
        NavigationStack(path: $path) {
            detail
                .pageReturn(returns)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { PageBackdrop() }
                // The page colour runs up under the window controls.
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .task {
            if ProcessInfo.processInfo.environment["SONY_UI_PANEL"] == "1" { openWindow(id: "panel-preview") }
        }
        .task {
            guard let demo = DesignSnapshot.navDemoPage else { return }
            try? await Task.sleep(for: .seconds(14))
            while !Task.isCancelled {
                path = [demo]
                try? await Task.sleep(for: .seconds(2.5))
                path = []
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
        .task {
            session.refreshDevices()
            if let live = session.connected { selection = live.id }
            // `BluetoothLink.open` waits for IOBluetooth's open callback by
            // spinning the run loop. Inside this main-actor task we are in a
            // main-queue job, which the nested run loop cannot drain, so the
            // callback never arrives and the open times out (0xE00002D6).
            // Run it as a run-loop block instead.
            RunLoop.main.perform { autoConnectIfAvailable() }
        }
        .onChange(of: path.isEmpty) { _, home in
            if home { returns += 1 }
        }
        .onChange(of: session.connected?.id) { _, id in
            if let id { selection = id }
            readyOnce = false
            stageStart = .now
        }
        .onChange(of: session.status.phase) { old, phase in
            if phase.isReady {
                if !readyOnce, old.isBusy, session.connected != nil {
                    // "Ready" comes before the settings: noise control,
                    // equaliser, playback and pairing follow over the next
                    // two seconds. Hold the stage until they stop arriving,
                    // so the page appears whole in one entrance instead of
                    // rows popping in one after another.
                    stageHeld = true
                    let floor = max(0.8, 1.6 - Date().timeIntervalSince(stageStart))
                    Task {
                        try? await Task.sleep(for: .seconds(floor))
                        let readyAt = Date()
                        var last = session.status.revision
                        var quietSince = Date()
                        while stageHeld, Date().timeIntervalSince(readyAt) < Self.syncCap {
                            try? await Task.sleep(for: .milliseconds(100))
                            let now = session.status.revision
                            if now != last { last = now; quietSince = .now }
                            if Date().timeIntervalSince(quietSince) >= Self.syncQuiet { break }
                        }
                        stageHeld = false
                    }
                }
                readyOnce = true
            } else if !phase.isBusy {
                stageHeld = false
            }
        }
        .environment(\.stageNamespace, stage)
        // Battery and wearing history for the charts.
        .onReceive(session.$status) { status in
            UsageLog.shared.observe(status, address: session.connected?.address)
        }
    }

    private func autoConnectIfAvailable() {
        guard session.connected == nil else { return }

        // Prefer a Sony headset. The Mac's paired list also contains phones,
        // earbuds from other vendors and accessories; auto-connecting to the
        // first connected one would open the wrong product.
        let sonyDevices = PairedDevice.preferred(session.devices)
        if autoConnect, let live = sonyDevices.first(where: { $0.isConnected && !$0.isLEEntry }) {
            selection = live.id
            session.connect(to: live)
            return
        }
        if selection == nil {
            selection = sonyDevices.first?.id
        }
    }

    /// While a first connection is still opening, the stage stays up; the
    /// page takes over once the headphones are ready.
    private var onStage: Bool {
        if stageHeld { return true }
        guard !readyOnce else { return false }
        switch session.status.phase {
        case .connecting, .handshaking, .discoveringCapabilities, .syncing: return true
        default: return false
        }
    }

    /// Which screen the detail shows, so swapping screens can cross-fade.
    private var detailKey: String {
        if let connected = session.connected, selection == nil || selection == connected.id {
            return onStage ? "stage-\(connected.id)" : "form-\(connected.id)"
        }
        return "prompt-\(selection.map { "\($0)" } ?? "none")"
    }

    private var detail: some View {
        detailContent
            .id(detailKey)
            // A plain cross-fade: the disc carries the motion between the
            // two screens, and blurring the rest would muddy it.
            .transition(.opacity)
            .animation(Motion.medium, value: detailKey)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let connected = session.connected, selection == nil || selection == connected.id {
            if onStage || DesignSnapshot.holdStage {
                ConnectPrompt(device: connected)
            } else {
                HeadphoneForm(device: connected)
            }
        } else if let selected = selection,
                  let device = session.devices.first(where: { $0.id == selected }) {
            ConnectPrompt(device: device)
        } else if !session.devices.contains(where: \.isSonyLike) {
            NoDevicesState()
        } else {
            ContentUnavailableView(
                "No Headphones Selected",
                systemImage: "headphones",
                description: Text("Choose headphones in the sidebar.")
            )
        }
    }
}

// MARK: - States

/// Selected but not open yet: the product, its name and one prominent
/// Connect button, centred on the window background.
struct ConnectPrompt: View {
    @EnvironmentObject private var session: HeadphoneSession
    @AppStorage(Pref.headphoneFinish) private var finish: HeadphoneFinish = .black
    let device: PairedDevice
    @State private var showHelp = false

    private var connecting: Bool {
        session.connected?.address == device.address && session.status.phase.isBusy
    }

    /// The short beat between the link opening and the page taking over.
    private var linked: Bool {
        session.connected?.address == device.address && session.status.phase.isReady
    }

    var body: some View {
        GeometryReader { geo in
            let disc = min(300, geo.size.height * 0.40, geo.size.width * 0.5)
            VStack(alignment: .leading, spacing: 0) {
                // The headline, as on a setup card.
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.largeTitle.bold())
                        .contentTransition(.opacity)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                // Only the headline animates: the status line below it can
                // change several times a second.
                .animation(Motion.fast, value: headline)
                .entrance(0)

                Spacer(minLength: 12)

                VStack(spacing: 22) {
                    ProductDisc(model: session.status.model.isEmpty ? device.displayName : session.status.model,
                                color: session.status.modelColor, finish: finish, diameter: disc,
                                searching: connecting, rays: connecting, done: linked)
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .entrance(2)
                }
                .frame(maxWidth: .infinity)
                .entrance(1)

                Spacer(minLength: 12)

                actions
                    .entrance(3)
            }
            .padding(.horizontal, 44)
            .padding(.top, 28)
            .padding(.bottom, 30)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .navigationTitle(device.displayName)
        .navigationSubtitle(device.isConnected ? "Connected to this Mac" : "Not connected")
    }

    /// A wide pill between two round glass buttons. Everything but the
    /// stage dims while the link opens, so the eye goes to the disc.
    private var actions: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(RoundButtonStyle())
                .help("Open Bluetooth Settings")

                Button {
                    session.connect(to: device)
                } label: {
                    Text(linked ? "Connected" : connecting ? "Connecting…" : "Connect")
                        .contentTransition(.opacity)
                }
                .buttonStyle(PillButtonStyle(kind: .accent, minWidth: 240))
                .keyboardShortcut(.defaultAction)
                .disabled(connecting || linked || device.isLEEntry)

                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "info")
                }
                .buttonStyle(RoundButtonStyle())
                .help("Connection help")
                .popover(isPresented: $showHelp, arrowEdge: .top) { help }
            }
            .opacity(connecting || linked ? 0.45 : 1)
            .animation(Motion.fast, value: connecting || linked)

            Text(footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .opacity(connecting || linked ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connecting").font(.headline)
            Text("Turn the headphones on and keep them near this Mac. They need to be paired with this Mac in Bluetooth Settings first.")
            Text("Only one app can hold the control channel at a time. If the headphones' own app is open on another device, it can take a moment to let go.")
        }
        .font(.callout)
        .frame(width: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }

    private var headline: String {
        if linked { return "Connected" }
        if connecting { return "Connecting…" }
        return device.isConnected ? "Ready to connect" : "Not nearby"
    }

    private var message: String {
        if linked {
            if let percent = session.status.batteryPercent { return "Battery \(percent)%." }
            return "The control channel is open."
        }
        if connecting {
            return session.activity.isEmpty ? session.status.phase.label : session.activity
        }
        return device.isConnected
            ? "Change noise control, the equalizer and more from this Mac."
            : "Turn on your headphones and keep them close."
    }

    private var footnote: String {
        if device.isLEEntry {
            return "This is the LE Audio pairing, which has no control channel. Choose the entry without “LE_” in the Headphones menu."
        }
        return "Not these headphones? Choose others in the Headphones menu."
    }
}

struct NoDevicesState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Headphones", systemImage: "headphones")
        } description: {
            Text("Pair your headphones with this Mac in Bluetooth settings, and they appear here.")
        } actions: {
            Button("Open Bluetooth Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Activity window

struct ActivityWindow: View {
    @EnvironmentObject private var session: HeadphoneSession

    var body: some View {
        Group {
            if session.log.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Frames sent to and received from the headphones appear here.")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(session.log.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("error") ? .red : .primary)
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .listStyle(.inset)
                    .alternatingRowBackgrounds()
                    .onAppear { proxy.scrollTo(session.log.count - 1, anchor: .bottom) }
                    .onChange(of: session.log.count) { _, count in
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .navigationSubtitle(session.connected?.displayName ?? "Not connected")
        .toolbar {
            ToolbarItem {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.log.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .disabled(session.log.isEmpty)
                .help("Copy the whole log")
            }
        }
    }
}

// MARK: - Settings window

struct AppSettingsView: View {
    @AppStorage(Pref.autoConnect) private var autoConnect = true
    @AppStorage(Pref.showMenuBarExtra) private var showMenuBarExtra = true
    @AppStorage(Pref.headphoneFinish) private var finish: HeadphoneFinish = .black
    @AppStorage(Pref.useProductImages) private var useProductImages = true
    @AppStorage(Pref.productImagesFolder) private var folderPath = ""

    private var folder: URL { ProductPictureLibrary.folder }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoConnect) {
                    Text("Connect automatically")
                    Text("When the app opens and Sony headphones are connected to this Mac, open their controls straight away.")
                }
                Toggle(isOn: $showMenuBarExtra) {
                    Text("Show in menu bar")
                    Text("Switch noise control and check the battery without opening the window.")
                }
            }
            Section {
                Toggle(isOn: $useProductImages) {
                    Text("Show product pictures")
                    Text("Uses pictures you keep on this Mac. Models without one show a 3D model.")
                }
                LabeledContent("Pictures folder") {
                    HStack(spacing: 8) {
                        Text(folder.path(percentEncoded: false).replacingOccurrences(
                            of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(folder.path(percentEncoded: false))
                        Button("Choose…", action: chooseFolder)
                        Button {
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        } label: {
                            Image(systemName: "arrow.right.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Show in Finder")
                        .accessibilityLabel("Show in Finder")
                    }
                }
                .disabled(!useProductImages)
                Picker(selection: $finish) {
                    ForEach(HeadphoneFinish.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Headphone colour")
                    Text("Used until the headphones report their colour.")
                }
            } footer: {
                Text("One folder per model, such as WH-1000XM6, holding 0x01-image.png for each colour.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path(percentEncoded: false)
        }
    }
}
