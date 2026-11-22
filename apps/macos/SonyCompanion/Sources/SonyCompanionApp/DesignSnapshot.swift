import AppKit
import SwiftUI
import SceneKit
import Metal

/// Design-review aid: renders the app's own windows to PNG files, so the
/// interface can be checked when the screen is locked or capture is not
/// permitted. Opt-in only, via `SONY_UI_SNAPSHOT=<directory>`; an optional
/// `SONY_UI_WINDOW=<width>x<height>` resizes the main window first.
enum DesignSnapshot {
    /// `SONY_UI_RENDER3D=<directory>` renders the headphone model offscreen in
    /// every finish (SceneKit views do not appear in window snapshots).
    static func render3DIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["SONY_UI_RENDER3D"],
              let device = MTLCreateSystemDefaultDevice() else { return }
        for model in ["WH-1000XM6", "WF-1000XM5"] {
            for finish in HeadphoneFinish.allCases {
                let rig = HeadphoneRig()
                rig.build(model: model, tint: .accentColor, finish: finish)
                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = rig.scene
                renderer.pointOfView = rig.cameraNode
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 600, height: 600), antialiasingMode: .multisampling4X)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(model)-\(finish.rawValue).png"))
                }
            }
        }
    }

    /// `SONY_UI_RENDERCHART=<directory>` draws the battery history card for
    /// every headphone this Mac has recorded, from the recorded samples, so
    /// the charts can be reviewed while the headphones are asleep.
    @MainActor
    static func renderChartsIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["SONY_UI_RENDERCHART"],
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let usage = base.appendingPathComponent("SonyCompanion/Usage")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: usage.path)) ?? []
        for file in files where file.hasSuffix(".json") {
            let address = String(file.dropLast(5))
            UsageLog.shared.prepare(address)
            let card = BatteryHistory(address: address)
                .padding(16)
                .frame(width: 520)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            // The app follows the system; resolve the theme's dynamic colours
            // in light, as the snapshot asks for.
            var rendered: NSImage?
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { rendered = renderer.nsImage }
            if let image = rendered, let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("history-\(address).png"))
            }
        }
    }

    static func scheduleIfRequested() {
        render3DIfRequested()
        MainActor.assumeIsolated { renderChartsIfRequested(); renderNoiseFieldsIfRequested() }
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SONY_UI_SNAPSHOT"] else { return }
        let size = env["SONY_UI_WINDOW"].flatMap(parseSize)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let size, let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "Item-0" }) {
                window.setContentSize(size)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (env["SONY_UI_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 3.5)) {
            capture(page: 0, dir: dir, quit: env["SONY_UI_SNAPSHOT_QUIT"] == "1")
        }
    }

    /// Captures every visible window, then pages the tallest scroll view down
    /// one screen and repeats until it reaches the end.
    private static func capture(page: Int, dir: String, quit: Bool) {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = window.title.isEmpty ? "window\(index)" : window.title
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(page).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        let scrollers = NSApp.windows.filter(\.isVisible).flatMap { scrollViews(in: $0.contentView) }
        if let main = scrollers.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
           let doc = main.documentView, page < 8 {
            let visible = main.contentView.bounds
            let maxY = doc.frame.height - visible.height
            let current = visible.origin.y
            if maxY - current > 1 {
                let next = min(maxY, current + visible.height * 0.85)
                main.contentView.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? next : maxY - next))
                main.reflectScrolledClipView(main.contentView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    capture(page: page + 1, dir: dir, quit: quit)
                }
                return
            }
        }
        if quit { NSApp.terminate(nil) }
    }

    private static func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// `SONY_UI_PANEL=1` also shows the menu bar panel in a plain window, since
    /// a menu bar extra cannot be opened without a click.
    /// `SONY_UI_STAGE=1` keeps the connect stage up after the link opens,
    /// for reviewing it with the headphones connected.
    static var holdStage: Bool { ProcessInfo.processInfo.environment["SONY_UI_STAGE"] == "1" }

    /// Pushes and pops a page on a timer, to record the navigation motion:
    /// `SONY_UI_NAVDEMO=power|noise|…`.
    static var navDemoPage: SettingsPage? {
        ProcessInfo.processInfo.environment["SONY_UI_NAVDEMO"].flatMap { SettingsPage(rawValue: $0) }
    }

    /// Opens a detail page instead of the main page, for reviewing it:
    /// `SONY_UI_PAGE=sound|noise|playback|controls|power|connections|about`.
    static var requestedPage: SettingsPage? {
        switch ProcessInfo.processInfo.environment["SONY_UI_PAGE"] {
        case "sound": return .sound
        case "noise": return .noise
        case "playback": return .playback
        case "controls": return .controls
        case "power": return .power
        case "connections": return .connections
        case "about": return .about
        default: return nil
        }
    }

    static func showPanelIfRequested<V: View>(_ content: V) {
        guard ProcessInfo.processInfo.environment["SONY_UI_PANEL"] == "1" else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 300, height: 260),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "MenuBarPanel"
        window.contentView = NSHostingView(rootView: content)
        window.setContentSize(window.contentView!.fittingSize)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
    }

    private static func parseSize(_ text: String) -> NSSize? {
        let parts = text.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : nil
    }
}
