import Foundation
import IOBluetooth

/// Errors surfaced to the UI with actionable text.
public enum LinkError: Error, CustomStringConvertible {
    case noDevice(String)
    case serviceNotFound
    case channelIdUnavailable
    case openFailed(IOReturn)
    case connectFailed(IOReturn)
    case writeFailed(IOReturn)

    public var description: String {
        switch self {
        case .noDevice(let a):
            return "No paired device matches “\(a)”. Pair it in System Settings first."
        case .serviceNotFound:
            return "This device does not advertise the Sony control service. It may be a different product line."
        case .channelIdUnavailable:
            return "The device’s service record has no RFCOMM channel."
        case .openFailed(let r):
            return String(format: "Could not open the control channel (0x%X).", r)
        case .connectFailed(let r):
            return String(format: "Could not reach the headphones (0x%X). They may be off or connected to another device.", r)
        case .writeFailed(let r):
            return String(format: "Sending failed (0x%X).", r)
        }
    }
}

/// One entry in the paired-device list.
public struct PairedDevice: Identifiable, Hashable {
    public let address: String
    public let name: String
    public let isConnected: Bool

    public var id: String { address }

    public var displayName: String { name.isEmpty ? address : name }

    /// Heuristic for the models this app can actually control. Bluetooth names
    /// are user-editable, so this only decides the default selection; it never
    /// gates the device list.
    public var isSonyLike: Bool {
        let upper = name.uppercased()
        return ["WH-", "WF-", "WI-", "MDR-", "LINKBUDS", "ULT ", "PULSE"].contains {
            upper.contains($0)
        }
    }
}

/// A live RFCOMM control channel to a set of headphones.
///
/// Owns the IOBluetooth objects and forwards raw bytes. It deliberately does no
/// protocol work: that belongs to the engine, so the transport can be swapped
/// for an Android or Windows implementation without touching protocol code.
public final class BluetoothLink: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?

    /// Called on the Bluetooth callback thread with bytes from the headphones.
    public var onReceive: ((Data) -> Void)?
    /// Called when the channel closes for any reason.
    public var onClose: (() -> Void)?

    /// Sony control-channel service UUIDs, most capable first.
    public static let serviceV2 = "956C7B26-D49A-4BA8-B03F-B17D393CB6E2"
    public static let serviceV1 = "96CC203E-5068-46AD-B32D-E316F5E069BA"

    public override init() { super.init() }

    // MARK: Discovery

    /// This Mac's own Bluetooth address, as the headphones list it.
    public static var hostAddress: String? {
        IOBluetoothHostController.default()?.addressAsString()
    }

    public static var pairedDevices: [PairedDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.compactMap { dev in
            guard let addr = dev.addressString else { return nil }
            return PairedDevice(
                address: addr.replacingOccurrences(of: "-", with: ":"),
                name: dev.name ?? "",
                isConnected: dev.isConnected())
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public static func find(_ address: String, in devices: [PairedDevice]? = nil) -> PairedDevice? {
        let pool = devices ?? pairedDevices
        return pool.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    // MARK: Lifecycle

    /// Open the control channel, trying V2 then V1 service records.
    ///
    /// `progress` is invoked with human-readable milestones so the UI can show
    /// what is actually happening instead of an indeterminate spinner.
    public func open(address: String, progress: ((String) -> Void)? = nil) throws {
        let pool = BluetoothLink.pairedDevices
        guard let entry = BluetoothLink.find(address, in: pool) else {
            throw LinkError.noDevice(address)
        }
        guard let dev = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
            .first(where: { ($0.addressString ?? "").replacingOccurrences(of: "-", with: ":")
                .caseInsensitiveCompare(entry.address) == .orderedSame })
        else {
            throw LinkError.noDevice(address)
        }
        device = dev

        progress?("Bringing up the link")
        try ensureConnected(dev)

        for uuidString in [BluetoothLink.serviceV2, BluetoothLink.serviceV1] {
            progress?("Looking up the control service")
            guard let bytes = BluetoothLink.uuidBytes(uuidString) else { continue }
            let sdp = bytes.withUnsafeBufferPointer { buf in
                IOBluetoothSDPUUID(bytes: buf.baseAddress, length: 16)
            }
            guard let record = dev.getServiceRecord(for: sdp) else { continue }
            var channelID: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
                throw LinkError.channelIdUnavailable
            }

            progress?("Opening the control channel")
            var ch: IOBluetoothRFCOMMChannel?
            let status = dev.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
            guard status == kIOReturnSuccess else { throw LinkError.openFailed(status) }
            channel = ch

            let deadline = Date().addingTimeInterval(10)
            while opened == nil && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            if let err = opened, err != kIOReturnSuccess {
                throw LinkError.openFailed(err)
            }
            guard opened != nil else { throw LinkError.openFailed(kIOReturnTimeout) }

            progress?("Control channel open")
            return
        }
        throw LinkError.serviceNotFound
    }

    public func write(_ data: Data) throws {
        guard let channel else { throw LinkError.openFailed(kIOReturnNotOpen) }
        var mutable = data
        let status = mutable.withUnsafeMutableBytes { raw -> IOReturn in
            guard let base = raw.baseAddress else { return kIOReturnBadArgument }
            return channel.writeAsync(base, length: UInt16(raw.count), refcon: nil)
        }
        if status != kIOReturnSuccess { throw LinkError.writeFailed(status) }
    }

    public func close() {
        channel?.close()
        channel = nil
    }

    public var isOpen: Bool { channel != nil }

    // MARK: Internals

    private var opened: IOReturn?

    private func ensureConnected(_ dev: IOBluetoothDevice) throws {
        if dev.isConnected() { return }
        let status = dev.openConnection()
        guard status == kIOReturnSuccess else { throw LinkError.connectFailed(status) }
        let deadline = Date().addingTimeInterval(20)
        while !dev.isConnected() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !dev.isConnected() { throw LinkError.connectFailed(kIOReturnTimeout) }
    }

    private static func uuidBytes(_ string: String) -> [UInt8]? {
        let hex = string.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 else { return nil }
        var out = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        return out
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    public func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        opened = error
    }

    public func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        onReceive?(Data(bytes: dataPointer, count: dataLength))
    }

    public func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        channel = nil
        onClose?()
    }
}
