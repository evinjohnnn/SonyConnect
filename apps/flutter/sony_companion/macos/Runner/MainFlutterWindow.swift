import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The storyboard frame can come through degenerate (a 33 px-tall window was
    // observed), so the size is set explicitly rather than trusted.
    // A tall 2:3 window, as on Windows, no taller than the screen's visible
    // area (a 13-inch MacBook Air at default scaling has about 800 pt).
    let visible = (self.screen ?? NSScreen.main)?.visibleFrame.size
      ?? NSSize(width: 1440, height: 900)
    let chrome = self.frameRect(forContentRect: .zero).height
    let height = max(480, min(900, visible.height - chrome))
    self.setContentSize(NSSize(width: (height * 2 / 3).rounded(), height: height))
    self.minSize = NSSize(width: 460, height: min(640, height))
    self.center()
    // A new autosave name: frames saved for the old 900x720 window would
    // otherwise keep the wide size for existing users.
    self.setFrameAutosaveName("SonyCompanionMainTall")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
