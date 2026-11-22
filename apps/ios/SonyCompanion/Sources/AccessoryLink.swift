import Foundation
import ExternalAccessory

/// One connected external accessory that speaks a Sony control protocol.
struct AccessoryDevice: Identifiable, Hashable {
    let id: String          // serial number, stable across reconnects
    let name: String
    let protocolString: String
    let isConnected: Bool
}

enum AccessoryError: Error, CustomStringConvertible {
    case noAccessory(String)
    case noSupportedProtocol
    case sessionRefused
    case streamOpenFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .noAccessory(let n):
            return "No connected accessory matches “\(n)”."
        case .noSupportedProtocol:
            return "This accessory does not expose a Sony control protocol."
        case .sessionRefused:
            return "The accessory refused to open a control session."
        case .streamOpenFailed(let why):
            return "Could not open the control streams: \(why)"
        case .writeFailed(let why):
            return "Sending failed: \(why)"
        }
    }
}

/// A control channel to a Sony headphone over the external-accessory framework.
///
/// iOS does not allow third-party apps to open an RFCOMM socket, so the macOS
/// transport cannot be reused. Sony's own iOS build talks over the accessory
/// protocols declared in its Info.plist, and this class does the same.
///
/// **Unverified.** It has not been exercised against a real accessory; the
/// protocol/session sequence is implemented from Apple's API contract, not from
/// an observed session. Treat it as unproven until it runs on device.
final class AccessoryLink: NSObject, StreamDelegate {

    /// Sony control protocols, most capable first.
    static let protocols = [
        "jp.co.sony.songpal.mdr.link2",
        "jp.co.sony.songpal.mdr.link",
    ]

    private var accessory: EAAccessory?
    private var session: EASession?

    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private var buffer = Data()

    // MARK: Discovery

    /// Accessories currently connected and speaking a Sony control protocol.
    static var connectedDevices: [AccessoryDevice] {
        let manager = EAAccessoryManager.shared()
        return manager.connectedAccessories.compactMap { acc in
            guard let proto = protocols.first(where: { acc.protocolStrings.contains($0) })
            else { return nil }
            return AccessoryDevice(
                id: acc.serialNumber.isEmpty ? acc.name : acc.serialNumber,
                name: acc.name,
                protocolString: proto,
                isConnected: acc.isConnected)
        }
        .sorted { $0.name.localizedCaseInsensitiveContains($1.name) ? false :
                  $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Lifecycle

    func open(matching device: AccessoryDevice) throws {
        EAAccessoryManager.shared().registerForLocalNotifications()
        guard let acc = EAAccessoryManager.shared().connectedAccessories.first(where: {
            ($0.serialNumber.isEmpty ? $0.name : $0.serialNumber) == device.id
        }) else {
            throw AccessoryError.noAccessory(device.name)
        }
        accessory = acc

        guard let proto = Self.protocols.first(where: { acc.protocolStrings.contains($0) }) else {
            throw AccessoryError.noSupportedProtocol
        }
        guard let s = EASession(accessory: acc, forProtocol: proto) else {
            throw AccessoryError.sessionRefused
        }
        session = s
        guard let input = s.inputStream, let output = s.outputStream else {
            throw AccessoryError.streamOpenFailed("accessory exposed no streams")
        }
        for stream in [input, output] {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .common)
            stream.open()
        }
    }

    func write(_ data: Data) throws {
        guard let out = session?.outputStream, out.streamStatus == .open else {
            throw AccessoryError.writeFailed("stream is not open")
        }
        var sent = 0
        while sent < data.count {
            let chunk = data[data.startIndex.advanced(by: sent)...]
            let n = chunk.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return out.write(base, maxLength: raw.count)
            }
            if n <= 0 { throw AccessoryError.writeFailed("stream reported \(n)") }
            sent += n
        }
    }

    func close() {
        session?.inputStream?.close()
        session?.outputStream?.close()
        session = nil
        accessory = nil
        buffer.removeAll()
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }

    var isOpen: Bool { session?.outputStream?.streamStatus == .open }

    // MARK: StreamDelegate

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream else { return }
            var chunk = [UInt8](repeating: 0, count: 4096)
            while input.hasBytesAvailable {
                let n = input.read(&chunk, maxLength: chunk.count)
                if n <= 0 { break }
                buffer.append(contentsOf: chunk[0..<n])
            }
            if !buffer.isEmpty {
                let data = buffer
                buffer.removeAll(keepingCapacity: true)
                onReceive?(data)
            }
        case .endEncountered, .errorOccurred:
            session = nil
            onClose?()
        default:
            break
        }
    }
}
