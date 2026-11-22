import Foundation
import Combine
import MDRKit

/// What the headphones reported at one moment, as recorded by this Mac.
struct UsageSample: Codable, Equatable {
    var time: Date
    var battery: Int
    var charging: Bool
    /// nil when the headphones did not report whether they were worn.
    var worn: Bool?
}

/// A local history of battery level, charging and wearing, per headphone.
///
/// The headphones keep no history of their own, so this is what the Mac saw
/// while it was connected: a sample whenever one of those values changes,
/// and otherwise every five minutes from the last value they reported (no
/// extra traffic to the headphones). Times the Mac was not connected are
/// gaps, never filled in. Ten days are kept, in Application Support.
@MainActor
final class UsageLog: ObservableObject {
    static let shared = UsageLog()

    static let keep: TimeInterval = 10 * 24 * 3600
    /// A sample stands for at most this long; a longer gap means the Mac
    /// was not connected.
    static let maxSpan: TimeInterval = 10 * 60
    private static let heartbeat: TimeInterval = 5 * 60

    @Published private(set) var samples: [String: [UsageSample]] = [:]

    private var latest: (address: String, sample: UsageSample)?
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.heartbeat, repeats: true) { _ in
            Task { @MainActor in UsageLog.shared.beat() }
        }
    }

    /// What has been recorded for these headphones. Call `prepare` first
    /// (from a view's task) so the file is read outside a view update.
    func history(for address: String) -> [UsageSample] { samples[address] ?? [] }

    func prepare(_ address: String) {
        if samples[address] == nil { load(address) }
    }

    private func list(for address: String) -> [UsageSample] {
        prepare(address)
        return samples[address] ?? []
    }

    /// Called with every status update for the connected headphones.
    func observe(_ status: HeadphoneStatus, address: String?) {
        guard let address, status.phase.isReady, let battery = status.batteryPercent else {
            latest = nil
            return
        }
        let sample = UsageSample(time: .now, battery: battery,
                                 charging: status.charging == .charging,
                                 worn: status.wearingStatus)
        let previous = latest
        latest = (address, sample)
        if let previous, previous.address == address,
           previous.sample.battery == sample.battery,
           previous.sample.charging == sample.charging,
           previous.sample.worn == sample.worn,
           let last = list(for: address).last,
           Date.now.timeIntervalSince(last.time) < Self.heartbeat {
            return
        }
        append(sample, to: address)
    }

    private func beat() {
        guard var current = latest else { return }
        current.sample.time = .now
        append(current.sample, to: current.address)
    }

    private func append(_ sample: UsageSample, to address: String) {
        var all = list(for: address)
        all.append(sample)
        let cutoff = Date.now.addingTimeInterval(-Self.keep)
        all.removeAll { $0.time < cutoff }
        samples[address] = all
        save(address)
    }

    // MARK: Storage

    private func url(_ address: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("SonyCompanion/Usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = address.replacingOccurrences(of: ":", with: "").lowercased()
        return dir.appendingPathComponent("\(name).json")
    }

    private func load(_ address: String) {
        guard let url = url(address), let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([UsageSample].self, from: data)
        else { samples[address] = []; return }
        samples[address] = list
    }

    private func save(_ address: String) {
        guard let url = url(address), let list = samples[address],
              let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Chart data

/// One bar of the time chart: minutes worn (or connected) in a slot.
struct TimeBar: Identifiable {
    let start: Date
    let end: Date
    let minutes: Double
    var id: Date { start }
}

enum UsageRange: String, CaseIterable, Identifiable {
    case day = "Last 24 Hours"
    case tenDays = "Last 10 Days"
    var id: String { rawValue }

    var span: TimeInterval { self == .day ? 24 * 3600 : UsageLog.keep }
    /// Where the range begins: on the hour for a day, at midnight for ten
    /// days.
    func start(_ now: Date) -> Date {
        let cal = Calendar.current
        let raw = now.addingTimeInterval(-span)
        return self == .day
            ? cal.dateInterval(of: .hour, for: raw)?.start ?? raw
            : cal.startOfDay(for: raw.addingTimeInterval(24 * 3600))
    }
    /// Slot width for the time bars.
    var timeSlot: TimeInterval { self == .day ? 3600 : 24 * 3600 }
}

extension Array where Element == UsageSample {
    /// Slots aligned to the hour (day view) or the day (ten days), from the
    /// start of the range to now.
    private func slots(_ width: TimeInterval, range: UsageRange, now: Date) -> [(Date, Date)] {
        let start = range.start(now)
        var out: [(Date, Date)] = []
        var t = start
        while t < now {
            out.append((t, t.addingTimeInterval(width)))
            t = t.addingTimeInterval(width)
        }
        return out
    }

    /// Minutes in each slot covered by samples where `include` holds. Each
    /// sample counts until the next one, up to `UsageLog.maxSpan`.
    func timeBars(_ range: UsageRange, now: Date = .now,
                  include: (UsageSample) -> Bool) -> [TimeBar] {
        let spans: [(Date, Date)] = indices.compactMap { i in
            guard include(self[i]) else { return nil }
            let from = self[i].time
            let next = i + 1 < count ? self[i + 1].time : now
            let to = Swift.min(next, from.addingTimeInterval(UsageLog.maxSpan))
            return to > from ? (from, to) : nil
        }
        return slots(range.timeSlot, range: range, now: now).map { start, end in
            let seconds = spans.reduce(0.0) { sum, span in
                let overlap = Swift.min(span.1, end).timeIntervalSince(Swift.max(span.0, start))
                return sum + Swift.max(0, overlap)
            }
            return TimeBar(start: start, end: end, minutes: seconds / 60)
        }
    }
}
