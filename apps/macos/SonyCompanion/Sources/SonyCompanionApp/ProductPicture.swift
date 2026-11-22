import SwiftUI
import AppKit
import ImageIO

// Product pictures come from a folder on this Mac that the user fills
// themselves. Nothing is bundled with the app or kept in the repository; when
// no picture matches, the procedural 3D model is drawn instead.
//
// Layout, one folder per model name (spaces become hyphens):
//
//     <folder>/WH-1000XM6/0x01-image.png    still, keyed by ModelColor byte
//     <folder>/WH-1000XM6/0x01-anime.png    optional APNG entrance, played once

enum ProductPictureLibrary {
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sony Companion", isDirectory: true)
            .appendingPathComponent("Product Images", isDirectory: true)
    }

    /// `SONY_PRODUCT_IMAGES` overrides the chosen folder, then the default.
    static var folder: URL {
        if let env = ProcessInfo.processInfo.environment["SONY_PRODUCT_IMAGES"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let path = UserDefaults.standard.string(forKey: Pref.productImagesFolder), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultFolder
    }

    struct Files: Hashable {
        let still: URL
        let animation: URL?
    }

    /// Exact colour first, then the model's default and black entries, then
    /// whatever the folder has, so a model always shows some picture.
    static func files(model: String, color: UInt8?) -> Files? {
        let fm = FileManager.default
        guard let dir = directory(for: model, fm: fm),
              let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        let stills = Set(names.filter { $0.hasSuffix("-image.png") })
        guard !stills.isEmpty else { return nil }

        var order: [String] = []
        if let color { order.append(key(color)) }
        order += [key(0x00), key(0x01)]
        let chosen = order.first { stills.contains("\($0)-image.png") }
            ?? stills.sorted().first!.replacingOccurrences(of: "-image.png", with: "")

        let anime = "\(chosen)-anime.png"
        return Files(
            still: dir.appendingPathComponent("\(chosen)-image.png"),
            animation: names.contains(anime) ? dir.appendingPathComponent(anime) : nil
        )
    }

    private static func key(_ color: UInt8) -> String { String(format: "0x%02x", color) }

    private static func directory(for model: String, fm: FileManager) -> URL? {
        var name = model.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("LE_") { name.removeFirst(3) }
        guard !name.isEmpty else { return nil }
        let candidates = [name, name.replacingOccurrences(of: " ", with: "-")]
        for candidate in candidates {
            let url = folder.appendingPathComponent(candidate, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return nil
    }

    // MARK: Decoding

    private static let cache = NSCache<NSString, CGImage>()

    /// A still decoded at the size it is drawn, cached per file and size.
    static func still(_ url: URL, maxPixels: Int) -> CGImage? {
        let cacheKey = "\(url.path)#\(maxPixels)" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = thumbnail(source, index: 0, maxPixels: maxPixels) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    static func thumbnail(_ source: CGImageSource, index: Int, maxPixels: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }

    static func frameDelay(_ source: CGImageSource, index: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let png = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let delay = (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
            ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double)
            ?? 1.0 / 30
        return delay > 0.005 ? delay : 1.0 / 30
    }
}

// MARK: - Hero

/// The headphones at the top of a page: the product picture when the user has
/// one for this model, otherwise the procedural 3D model.
struct HeadphoneHero: View {
    let model: String
    /// `ModelColor` the device reported; nil falls back to `finish`.
    var color: UInt8? = nil
    var finish: HeadphoneFinish = .black
    var playsEntrance = true

    @AppStorage(Pref.useProductImages) private var useProductImages = true
    @AppStorage(Pref.productImagesFolder) private var folderPath = ""

    var body: some View {
        if useProductImages,
           let files = ProductPictureLibrary.files(model: model, color: color ?? finish.modelColor) {
            ProductPicture(files: files, playsEntrance: playsEntrance)
                .id(files)
                .accessibilityLabel(model)
        } else {
            Headphone3DView(model: model, finish: finish)
        }
    }
}

/// A still, or an APNG entrance played once that rests on its last frame.
struct ProductPicture: View {
    let files: ProductPictureLibrary.Files
    var playsEntrance = true

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGImage?
    @State private var size: CGSize = .zero
    /// The entrance frame the picture rests on, and the pixel size it was
    /// decoded at, so a larger window can decode it again instead of
    /// stretching a small copy.
    @State private var restIndex: Int?
    @State private var restPixels = 0

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = frame ?? stillImage(for: geo.size) {
                    Image(decorative: image, scale: scale)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Entrances rise in from below the canvas edge. Fade that edge so
            // it reads as intended; every still ends above 82% of the height.
            .mask(LinearGradient(
                stops: [.init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom))
            .onChange(of: geo.size, initial: true) { _, new in size = new }
        }
        .task(id: files) { await playEntrance() }
        .task(id: RestKey(index: restIndex, pixels: pixels(for: size))) { await sharpenRest() }
    }

    private struct RestKey: Equatable {
        let index: Int?
        let pixels: Int
    }

    /// After a resize, decodes the resting frame again at the new size. Only
    /// grows: a smaller window draws the larger copy down without blur.
    private func sharpenRest() async {
        guard let restIndex, let url = files.animation else { return }
        let wanted = pixels(for: size)
        guard wanted > restPixels else { return }
        // Wait out a live resize; a new size cancels this task.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        guard let (image, _) = await FrameDecoder(url: url, maxPixels: wanted).frame(restIndex),
              !Task.isCancelled else { return }
        frame = image
        restPixels = wanted
    }

    private func pixels(for size: CGSize) -> Int {
        max(64, Int((max(size.width, size.height) * scale).rounded(.up)))
    }

    private func stillImage(for size: CGSize) -> CGImage? {
        guard size.width > 0 else { return nil }
        return ProductPictureLibrary.still(files.still, maxPixels: pixels(for: size))
    }

    /// Decodes frames one at a time off the main thread, so a 150-frame
    /// entrance never sits in memory at once.
    private func playEntrance() async {
        guard playsEntrance, !reduceMotion, let url = files.animation else { return }
        // Wait for the first layout pass to know the drawn size.
        var waited = 0
        while size == .zero, waited < 20 {
            try? await Task.sleep(for: .milliseconds(10)); waited += 1
        }
        let maxPixels = pixels(for: size == .zero ? CGSize(width: 180, height: 180) : size)
        let decoder = FrameDecoder(url: url, maxPixels: maxPixels)
        guard let count = await decoder.count, count > 1 else { return }
        restIndex = nil

        let clock = ContinuousClock()
        var due = clock.now
        for index in 0..<count {
            guard !Task.isCancelled else { return }
            guard let (image, delay) = await decoder.frame(index) else { return }
            try? await clock.sleep(until: due)
            frame = image
            due = due.advanced(by: .milliseconds(Int(delay * 1000)))
        }
        restPixels = maxPixels
        restIndex = count - 1
    }
}

/// Owns the image source so decoding stays off the main actor.
private actor FrameDecoder {
    private let source: CGImageSource?
    private let maxPixels: Int

    init(url: URL, maxPixels: Int) {
        source = CGImageSourceCreateWithURL(url as CFURL, nil)
        self.maxPixels = maxPixels
    }

    var count: Int? { source.map(CGImageSourceGetCount) }

    func frame(_ index: Int) -> (CGImage, Double)? {
        guard let source,
              let image = ProductPictureLibrary.thumbnail(source, index: index, maxPixels: maxPixels)
        else { return nil }
        return (image, ProductPictureLibrary.frameDelay(source, index: index))
    }
}

extension HeadphoneFinish {
    /// The `ModelColor` byte this finish stands for, used when the device
    /// has not reported its colour.
    var modelColor: UInt8 {
        switch self {
        case .black: return 0x01
        case .silver: return 0x03
        case .midnightBlue: return 0x05
        }
    }
}
