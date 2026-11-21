import Foundation

public struct ScanSession: Codable, Sendable {
    public let version: Int
    public let date: Date
    public let source: String
    public let networks: [Network]

    public init(date: Date = .now, source: String, networks: [Network]) {
        version = 1
        self.date = date
        self.source = source
        self.networks = networks
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func read(from url: URL) throws -> Self {
        guard url.isFileURL, let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 32 * 1024 * 1024 else {
            throw SessionError.tooLarge
        }
        let session = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard session.version == 1 else { throw SessionError.version }
        guard Set(session.networks.map(\.id)).count == session.networks.count,
              session.networks.allSatisfy({ network in
                  !network.id.isEmpty && !network.samples.isEmpty &&
                      zip(network.samples, network.samples.dropFirst()).allSatisfy { $0.time <= $1.time }
              }) else { throw SessionError.invalid }
        return session
    }

    public static func csv(_ networks: [Network]) -> Data {
        let timestamp = ISO8601DateFormatter()
        let header = "SSID,BSSID,Band,Primary Channel,Width (MHz),RSSI (dBm),Noise (dBm),SNR (dB),PHY,Security,Country,Last Seen (UTC),Note"
        let rows = networks.map { network in
            let fields: [String] = [
                escaped(network.ssid ?? ""), escaped(network.bssid ?? ""), escaped(L10n.networkValue(network.band.rawValue)),
                network.channel.map(String.init) ?? "", network.width.map(String.init) ?? "",
                network.latest?.rssi.map(String.init) ?? "", network.latest?.noise.map(String.init) ?? "",
                network.latest?.snr.map(String.init) ?? "", escaped(L10n.networkValue(network.phy)),
                escaped(L10n.networkValue(network.security)),
                escaped(network.country ?? ""), escaped(network.latest.map { timestamp.string(from: $0.time) } ?? ""),
                escaped(network.note)
            ]
            return fields.joined(separator: ",")
        }
        return Data(("\u{FEFF}" + ([header] + rows).joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func escaped(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsPrefix = trimmed.first.map { "=+-@＝＋－＠".contains($0) } == true ||
            value.first.map { "\t\r\n".contains($0) } == true
        let safe = needsPrefix ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private enum SessionError: LocalizedError {
    case tooLarge, version, invalid

    var errorDescription: String? {
        switch self {
        case .tooLarge: return L10n.text("请选择不超过 32 MB 的本地会话文件。")
        case .version: return L10n.text("此版本的 OpenWilo 无法读取该会话格式。")
        case .invalid: return L10n.text("会话中存在重复网络标识或无效的采样记录。")
        }
    }
}
