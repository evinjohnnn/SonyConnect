import SwiftUI

/// Ten-band equaliser editor.
///
/// Band centres are the standard set the headphone reports: 31 Hz to 16 kHz.
/// The device reports a step count (13 for the WH-1000XM6), which gives a range
/// of 0…12 around a centre step of 6, presented here as −6…+6 dB.
///
/// **Mapping is inferred, not yet confirmed on hardware**: step = dB + 6. If a
/// model reports a different step count the range adapts instead of assuming 13.
struct EqualizerEditor: View {
    let presetName: String
    let initialBands: [UInt8]
    let bandStep: UInt8
    let onSave: ([UInt8]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bands: [Double]

    private static let frequencies = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    init(presetName: String, initialBands: [UInt8], bandStep: UInt8, onSave: @escaping ([UInt8]) -> Void) {
        self.presetName = presetName
        self.initialBands = initialBands
        self.bandStep = bandStep
        self.onSave = onSave
        _bands = State(initialValue: initialBands.map(Double.init))
    }

    /// Number of steps the device offers, and the step that means 0 dB.
    private var steps: Int { max(2, Int(bandStep)) }
    private var centre: Int { steps / 2 }
    private var halfRange: Int { centre }

    private func decibels(_ step: Double) -> Double {
        step - Double(centre)
    }

    private var isDirty: Bool {
        bands.map { UInt8($0.rounded()) } != initialBands
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Equalizer")
                        .font(.headline)
                    Text(presetName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("±\(halfRange) dB")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(18)

            Divider()

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(bands.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.0f", decibels(bands[index])))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(decibels(bands[index]) == 0 ? .tertiary : .secondary)
                            .monospacedDigit()

                        // Vertical fader. A Slider rotated is unreliable for hit
                        // testing, so this is a custom drag area.
                        Fader(
                            value: $bands[index],
                            range: 0...Double(steps - 1),
                            height: 150
                        )

                        Text(Self.frequencies[safe: index] ?? "\(index)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            HStack {
                Text("Changes apply on the headphones, not in software.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(bands.map { UInt8($0.rounded()) })
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isDirty)
            }
            .padding(18)
        }
        .frame(width: 620)
    }
}

/// A vertical fader with a track, a fill and a draggable knob.
private struct Fader: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let usable = height - 18
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobY = usable * (1 - t)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                // Centre line at 0 dB.
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 18, height: 1)
                    .offset(y: usable / 2 + 9)

                Circle()
                    .fill(.background)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(y: knobY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let y = min(max(drag.location.y - 9, 0), usable)
                                let nt = 1 - (y / usable)
                                value = (range.lowerBound + nt * (range.upperBound - range.lowerBound)).rounded()
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 26, height: height)
        .accessibilityElement()
        .accessibilityLabel("Band")
        .accessibilityValue(String(format: "%+.0f dB", value - (range.upperBound + range.lowerBound) / 2))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
