import SwiftUI
import Charts
import MDRKit

// Charts for the detail pages: a few numbers first, then quiet charts with
// hairline guides, values on the trailing axis and no vertical grid.

// MARK: - Battery overview

/// The top of Battery & Power: the level as a ring, the number, and what
/// the headphones are doing.
struct BatteryOverview: View {
    let percent: Int
    let charging: ChargingState
    let worn: Bool?

    var body: some View {
        HStack(spacing: 16) {
            BatteryRing(percent: percent, charging: charging == .charging, diameter: 56, lineWidth: 6)
                .overlay {
                    Image(systemName: charging == .charging ? "bolt.fill" : "headphones")
                        .font(.title3)
                        .foregroundStyle(charging == .charging ? Color.good : .secondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(percent)%")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                Text(chargingText)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let worn {
                Label(worn ? "Worn" : "Not worn", systemImage: worn ? "person.fill" : "person")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .animation(Motion.fast, value: percent)
        .accessibilityElement(children: .combine)
    }

    private var chargingText: String {
        switch charging {
        case .charging: return "Charging"
        case .notCharging: return "On battery"
        default: return "Battery"
        }
    }
}

// MARK: - Battery history

/// Battery level and time worn over the last day or ten days, from what
/// this Mac recorded while connected.
///
/// Three numbers lead (time connected, battery used, time worn), so the
/// card says something useful from the first few minutes. The level is one
/// continuous line with a soft fill, broken where the Mac was not
/// connected. While the record is short the chart zooms to it rather than
/// leaving a sliver at the edge of an empty day.
struct BatteryHistory: View {
    let address: String
    @ObservedObject private var log = UsageLog.shared
    @State private var range: UsageRange = .day

    var body: some View {
        let now = Date.now
        let start = range.start(now)
        let samples = log.history(for: address).filter { $0.time >= start }
        VStack(alignment: .leading, spacing: 18) {
            GlassSegmented(options: UsageRange.allCases, selection: $range) { $0.rawValue }
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)

            if samples.count < 2 {
                empty
            } else {
                let summary = UsageSummary(samples, now: now)
                Group {
                    stats(summary)
                    batteryChart(samples, summary: summary, start: start, now: now)
                    if summary.wornKnown, summary.worn >= 60, !zoomed(summary, start: start, now: now) {
                        timeChart(samples, now: now)
                    }
                }
                .animation(Motion.fast, value: range)
            }
        }
        .padding(.vertical, 6)
        .task(id: address) { log.prepare(address) }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No History Yet")
                .font(.headline)
            Text("Battery level and time worn appear here as you use your headphones with this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    // MARK: Numbers

    private func stats(_ s: UsageSummary) -> some View {
        HStack(alignment: .top, spacing: 0) {
            stat("Connected", duration(s.connected))
            stat("Battery Used", "\(s.used)%")
            if s.wornKnown { stat("Worn", duration(s.worn)) }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    // MARK: Battery level

    /// The record covers too little of the range to read at full width.
    private func zoomed(_ s: UsageSummary, start: Date, now: Date) -> Bool {
        now.timeIntervalSince(s.first) < now.timeIntervalSince(start) * 0.25
    }

    private func batteryChart(_ samples: [UsageSample], summary: UsageSummary,
                              start: Date, now: Date) -> some View {
        let zoom = zoomed(summary, start: start, now: now)
        let from = zoom
            ? summary.first.addingTimeInterval(-max(now.timeIntervalSince(summary.first) * 0.06, 60))
            : start
        // Readings are whole percents, so raw samples step. Fifteen-minute
        // (day) or two-hour (ten days) points read as a smooth line; a
        // short, zoomed record keeps every sample.
        let points = BatteryPoint.make(samples, bucket: zoom ? 0 : (range == .day ? 15 * 60 : 2 * 3600))
        let latest = points.last
        let colour: Color = (latest.map { $0.level <= 20 && !$0.charging } ?? false) ? .signal : .good
        let axis = TimeAxis(from: from, to: now, range: range, zoomed: zoom)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery Level").font(.headline)
                Spacer()
                if zoom {
                    Text("Since \(summary.first.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(summary.charging, id: \.0) { span in
                    ChargingBand(from: span.0, to: span.1)
                }
                ForEach(points) { point in
                    LevelMarks(point: point, colour: colour)
                }
                if let latest {
                    LatestMark(point: latest, colour: colour)
                }
            }
            .chartXScale(domain: from...now)
            .chartYScale(domain: 0...114)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)%") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axis.marks) { _ in
                    AxisValueLabel(format: axis.format, anchor: .top)
                }
            }
            .frame(height: 170)

            if !summary.charging.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.good.opacity(0.18))
                        .frame(width: 14, height: 10)
                    Text("Charging").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(latest.map { "Latest \($0.level) percent" } ?? "No data")
    }

    // MARK: Time worn

    private func timeChart(_ samples: [UsageSample], now: Date) -> some View {
        let hours = range == .tenDays
        let bars = samples.timeBars(range, now: now) { $0.worn == true }
            .filter { $0.minutes >= 1 }
        let top = hours ? max(2, ((bars.map(\.minutes).max() ?? 0) / 60).rounded(.up)) : 60
        let axis = TimeAxis(from: range.start(now), to: now, range: range, zoomed: false)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time Worn").font(.headline)
            Chart(bars) { bar in
                WornBar(bar: bar, value: hours ? bar.minutes / 60 : bar.minutes)
            }
            .chartXScale(domain: range.start(now)...now)
            .chartYScale(domain: 0...top)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, top]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(hours ? "\(Int(v)) h" : "\(Int(v)) min") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axis.marks) { _ in
                    AxisValueLabel(format: axis.format, anchor: .top)
                }
            }
            .frame(height: 90)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time worn")
    }
}

// MARK: - Chart data

/// What the numbers above the chart are made of.
private struct UsageSummary {
    var first: Date
    var connected: TimeInterval = 0
    var worn: TimeInterval = 0
    var wornKnown = false
    /// Percent the battery fell while not charging.
    var used = 0
    /// Spans the headphones were charging.
    var charging: [(Date, Date)] = []

    init(_ samples: [UsageSample], now: Date) {
        first = samples.first?.time ?? now
        wornKnown = samples.contains { $0.worn != nil }
        for (i, s) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].time : now
            let span = max(0, min(next.timeIntervalSince(s.time), UsageLog.maxSpan))
            connected += span
            if s.worn == true { worn += span }
            if s.charging { charging.append((s.time, s.time.addingTimeInterval(span))) }
            if i + 1 < samples.count, !s.charging, next.timeIntervalSince(s.time) <= UsageLog.maxSpan {
                used += max(0, s.battery - samples[i + 1].battery)
            }
        }
    }
}

/// One point of the level line. A new session starts after a gap, so the
/// line breaks where the Mac was not connected.
private struct BatteryPoint: Identifiable {
    let time: Date
    let level: Int
    let charging: Bool
    let session: Int
    var id: Date { time }

    /// `bucket` > 0 keeps the last sample per bucket (ten days of samples
    /// are more points than the chart can show).
    static func make(_ samples: [UsageSample], bucket: TimeInterval) -> [BatteryPoint] {
        var kept: [UsageSample] = []
        if bucket > 0 {
            var lastKey: Int?
            for s in samples {
                let key = Int(s.time.timeIntervalSinceReferenceDate / bucket)
                if key == lastKey { kept[kept.count - 1] = s } else { kept.append(s); lastKey = key }
            }
        } else {
            kept = samples
        }
        let gap = max(UsageLog.maxSpan, bucket * 1.5)
        var session = 0
        return kept.enumerated().map { i, s in
            if i > 0, s.time.timeIntervalSince(kept[i - 1].time) > gap { session += 1 }
            return BatteryPoint(time: s.time, level: s.battery, charging: s.charging, session: session)
        }
    }
}

/// Where the time labels go: on round times for a zoomed record, every six
/// hours for a day, each day for ten days.
private struct TimeAxis {
    let marks: [Date]
    let format: Date.FormatStyle

    init(from: Date, to: Date, range: UsageRange, zoomed: Bool) {
        let span = to.timeIntervalSince(from)
        let step: TimeInterval
        if zoomed {
            let steps: [TimeInterval] = [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440].map { $0 * 60 }
            step = steps.first { span / $0 <= 4 } ?? 86400
            format = step >= 3600 ? .dateTime.hour() : .dateTime.hour().minute()
        } else if range == .day {
            step = 6 * 3600
            format = .dateTime.hour()
        } else {
            step = 2 * 86400
            format = .dateTime.weekday(.abbreviated)
        }
        let cal = Calendar.current
        var t: Date
        if !zoomed && range == .tenDays {
            t = cal.startOfDay(for: from).addingTimeInterval(12 * 3600)
        } else {
            let base = cal.startOfDay(for: from)
            let offset = (from.timeIntervalSince(base) / step).rounded(.up) * step
            t = base.addingTimeInterval(offset)
        }
        var out: [Date] = []
        while t < to.addingTimeInterval(-span * 0.04) {
            if t > from.addingTimeInterval(span * 0.04) { out.append(t) }
            t = t.addingTimeInterval(step)
        }
        marks = out
    }
}

// MARK: - Chart marks

/// The level line and the soft fill under it.
private struct LevelMarks: ChartContent {
    let point: BatteryPoint
    let colour: Color

    var body: some ChartContent {
        AreaMark(x: .value("Time", point.time), y: .value("Level", point.level),
                 series: .value("Session", point.session), stacking: .unstacked)
            .foregroundStyle(LinearGradient(colors: [colour.opacity(0.26), colour.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)
        LineMark(x: .value("Time", point.time), y: .value("Level", point.level),
                 series: .value("Session", point.session))
            .foregroundStyle(colour)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
    }
}

/// The latest reading: a dot with a soft halo and its value.
private struct LatestMark: ChartContent {
    let point: BatteryPoint
    let colour: Color

    var body: some ChartContent {
        PointMark(x: .value("Time", point.time), y: .value("Level", point.level))
            .symbolSize(220)
            .foregroundStyle(colour.opacity(0.18))
        PointMark(x: .value("Time", point.time), y: .value("Level", point.level))
            .symbolSize(50)
            .foregroundStyle(colour)
            .annotation(position: .top, alignment: .center, spacing: 8,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                Text("\(point.level)%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(colour)
            }
    }
}

/// A charging span: a faint green wash behind the line.
private struct ChargingBand: ChartContent {
    let from: Date
    let to: Date

    var body: some ChartContent {
        RectangleMark(xStart: .value("From", from), xEnd: .value("To", to),
                      yStart: .value("Bottom", 0), yEnd: .value("Top", 100))
            .foregroundStyle(Color.good.opacity(0.12))
    }
}

/// One slot of time worn.
private struct WornBar: ChartContent {
    let bar: TimeBar
    let value: Double

    var body: some ChartContent {
        let inset = bar.end.timeIntervalSince(bar.start) * 0.15
        RectangleMark(xStart: .value("From", bar.start.addingTimeInterval(inset)),
                      xEnd: .value("To", bar.end.addingTimeInterval(-inset)),
                      yStart: .value("Base", 0), yEnd: .value("Time", value))
            .foregroundStyle(Color.accentColor.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

// MARK: - Equalizer curve

/// The equaliser's bands as a smooth response curve, filled down to 0 dB.
struct EqualizerResponse: View {
    let bands: [UInt8]
    let bandStep: UInt8
    var isOn = true

    private var steps: Int { max(2, Int(bandStep), Int(bands.max() ?? 0) + 1) }
    private var centre: Double { Double((steps - 1) / 2) }

    private var points: [(index: Int, db: Double)] {
        bands.enumerated().map { ($0.offset, Double($0.element) - centre) }
    }

    var body: some View {
        let limit = max(centre, 1)
        Chart {
            RuleMark(y: .value("Flat", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
            ForEach(points, id: \.index) { p in
                AreaMark(x: .value("Band", p.index), yStart: .value("Flat", 0), yEnd: .value("dB", p.db))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.04)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Band", p.index), y: .value("dB", p.db))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: 0...max(bands.count - 1, 1))
        .chartYScale(domain: -limit...limit)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [-limit, 0, limit]) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(v > 0 ? "+\(Int(v))" : "\(Int(v))") }
                }
            }
        }
        .saturation(isOn ? 1 : 0)
        .opacity(isOn ? 1 : 0.5)
        .frame(height: 96)
        .animation(Motion.medium, value: bands)
        .accessibilityHidden(true)
    }
}
