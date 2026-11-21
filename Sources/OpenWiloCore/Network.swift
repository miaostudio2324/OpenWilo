import Foundation

public enum Band: String, Codable, CaseIterable, Identifiable, Sendable {
    case two = "2.4 GHz"
    case five = "5 GHz"
    case six = "6 GHz"
    case unknown = "未知"

    public var id: Self { self }
    public static let plotted: [Band] = [.two, .five, .six]

    public func frequency(channel: Int) -> Double? {
        guard (1...233).contains(channel) else { return nil }
        switch self {
        case .two where channel == 14: return 2484
        case .two where channel <= 13: return Double(2407 + 5 * channel)
        case .five: return Double(5000 + 5 * channel)
        case .six where channel == 2: return 5935
        case .six: return Double(5950 + 5 * channel)
        default: return nil
        }
    }
}

public struct ChannelSpan: Equatable, Sendable {
    public let center: Double
    public let width: Int
    public let estimated: Bool

    public var lower: Double { center - Double(width) / 2 }
    public var upper: Double { center + Double(width) / 2 }

    public func overlaps(_ other: Self) -> Bool {
        lower < other.upper && other.lower < upper
    }
}

public struct Observation: Codable, Equatable, Sendable {
    public let time: Date
    public let rssi: Int?
    public let noise: Int?

    public init(time: Date, rssi: Int?, noise: Int?) {
        self.time = time
        self.rssi = rssi
        self.noise = noise
    }

    public var snr: Int? {
        guard let rssi, let noise, (-160 ... -1).contains(rssi), (-160 ... -1).contains(noise) else {
            return nil
        }
        return rssi - noise
    }
}

public struct Network: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let ssid: String?
    public let bssid: String?
    public let band: Band
    public let channel: Int?
    public let width: Int?
    public let security: String
    public let phy: String
    public let country: String?
    public let elements: Data
    public let connected: Bool
    public var samples: [Observation]
    public var note: String

    public init(id: String, ssid: String?, bssid: String?, band: Band, channel: Int?, width: Int?,
                security: String, phy: String, country: String? = nil, elements: Data = Data(),
                connected: Bool = false, samples: [Observation], note: String = "") {
        self.id = id
        self.ssid = ssid
        self.bssid = bssid
        self.band = band
        self.channel = channel
        self.width = width
        self.security = security
        self.phy = phy
        self.country = country
        self.elements = elements
        self.connected = connected
        self.samples = samples
        self.note = note
    }

    public var name: String { ssid.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.text("隐藏或未提供的网络") }
    public var latest: Observation? { samples.last }
    public var rssiOrder: Int { latest?.rssi ?? -999 }
    public var snrOrder: Int { latest?.snr ?? -999 }
    public var channelOrder: Int { channel ?? 999 }
    public var widthOrder: Int { width ?? 0 }

    public var span: ChannelSpan? {
        guard let channel, let primary = band.frequency(channel: channel), let width,
              [20, 40, 80, 160, 320].contains(width) else { return nil }
        let center = width == 20 ? primary :
            WiFiElements.decode(elements).centerChannel(band: band, primary: channel, width: width)
                .flatMap { band.frequency(channel: $0) }
        let usableCenter = center.flatMap { abs($0 - primary) < Double(width) / 2 ? $0 : nil }
        return ChannelSpan(center: usableCenter ?? primary, width: width, estimated: usableCenter == nil)
    }
}

public struct WiFiElement: Identifiable, Sendable {
    public let offset: Int
    public let number: UInt8
    public let bytes: [UInt8]
    public var id: Int { offset }

    public var title: String {
        switch (number, bytes.first) {
        case (0, _): return "SSID"
        case (1, _), (50, _): return "Supported Rates"
        case (3, _): return "DS Parameter Set"
        case (7, _): return "Country"
        case (11, _): return "BSS Load"
        case (45, _): return "HT Capabilities"
        case (48, _): return "RSN"
        case (61, _): return "HT Operation"
        case (71, _): return "Multiple BSSID"
        case (127, _): return "Extended Capabilities"
        case (191, _): return "VHT Capabilities"
        case (192, _): return "VHT Operation"
        case (201, _): return "Reduced Neighbor Report"
        case (221, _): return "Vendor Specific"
        case (255, 35): return "HE Capabilities"
        case (255, 36): return "HE Operation"
        case (255, 106): return "EHT Operation"
        case (255, 107): return "Multi-Link"
        case (255, 108): return "EHT Capabilities"
        default: return L10n.text("信息元素")
        }
    }

    public var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

public struct WiFiElements: Sendable {
    public let items: [WiFiElement]
    public let truncated: Bool

    public static func decode(_ data: Data) -> Self {
        let bytes = [UInt8](data)
        var offset = 0
        var items: [WiFiElement] = []
        while offset + 2 <= bytes.count {
            let end = offset + 2 + Int(bytes[offset + 1])
            guard end <= bytes.count else { break }
            items.append(WiFiElement(offset: offset, number: bytes[offset],
                                     bytes: Array(bytes[offset + 2 ..< end])))
            offset = end
        }
        return Self(items: items, truncated: offset != bytes.count)
    }

    public var bssLoad: (stations: Int, utilization: Double)? {
        items.first { $0.number == 11 }?.bssLoad
    }

    public var advertisedPersonalSecurity: String? {
        guard let rsn = element(48) else { return nil }
        let akms = Self.authenticationSuites(rsn, start: 0, oui: [0x00, 0x0f, 0xac])
        let hasPSK = !akms.isDisjoint(with: [2, 4, 6])
        let hasSAE = !akms.isDisjoint(with: [8, 9, 24, 25])
        if hasSAE { return hasPSK ? "WPA2/WPA3" : "WPA3-Personal" }
        guard hasPSK else { return nil }
        let hasLegacyPSK = items.contains { item in
            item.number == 221 && item.bytes.starts(with: [0x00, 0x50, 0xf2, 0x01]) &&
                Self.authenticationSuites(item.bytes, start: 4, oui: [0x00, 0x50, 0xf2]).contains(2)
        }
        return hasLegacyPSK ? "WPA/WPA2-Personal" : "WPA2-Personal"
    }

    static func authenticationSuites(_ bytes: [UInt8], start: Int, oui: [UInt8]) -> Set<UInt8> {
        guard bytes.count >= start + 8, bytes[start] == 1, bytes[start + 1] == 0 else { return [] }
        let pairwise = Int(bytes[start + 6]) | (Int(bytes[start + 7]) << 8)
        let countOffset = start + 8 + 4 * pairwise
        guard bytes.count >= countOffset + 2 else { return [] }
        let count = Int(bytes[countOffset]) | (Int(bytes[countOffset + 1]) << 8)
        let first = countOffset + 2
        guard bytes.count >= first + 4 * count else { return [] }

        var suites = Set<UInt8>()
        for offset in stride(from: first, to: first + 4 * count, by: 4) {
            if bytes[offset ..< offset + 3].elementsEqual(oui) {
                suites.insert(bytes[offset + 3])
            }
        }
        return suites
    }

    public var advertisesEHT: Bool { element(255, 108) != nil || element(255, 106) != nil }

    public var ehtWidth: Int? {
        guard let b = element(255, 106), b.count >= 9, b[1] & 1 != 0 else { return nil }
        let widths = [20, 40, 80, 160, 320]
        let index = Int(b[6] & 7)
        return widths.indices.contains(index) ? widths[index] : nil
    }

    public var hasDiscontiguousVHT: Bool {
        guard let b = element(192), b.count >= 5 else { return false }
        return b[0] == 3 || (b[0] == 1 && b[2] != 0 && abs(Int(b[1]) - Int(b[2])) > 16)
    }

    func centerChannel(band: Band, primary: Int, width: Int) -> Int? {
        if let b = element(255, 106), ehtWidth == width {
            return Int(width >= 160 && b[8] != 0 ? b[8] : b[7])
        }
        if band == .six, let b = element(255, 36), b.count >= 7 {
            let params = Int(b[1]) | Int(b[2]) << 8 | Int(b[3]) << 16
            var start = 7
            if params & (1 << 14) != 0 { start += 3 }
            if params & (1 << 15) != 0 { start += 1 }
            if params & (1 << 17) != 0, b.count >= start + 5 {
                let code = b[start + 1] & 3
                let first = Int(b[start + 2])
                let second = Int(b[start + 3])
                switch (width, code) {
                case (40, 1), (80, 2): return first
                case (160, 3) where abs(first - second) == 8: return second
                default: break
                }
            }
        }
        if band == .five, let b = element(192), b.count >= 5 {
            let first = Int(b[1])
            let second = Int(b[2])
            switch (width, b[0]) {
            case (80, 1) where second == 0: return first
            case (160, 1) where abs(first - second) == 8: return second
            case (160, 2): return first
            default: break
            }
        }
        if width == 40, let b = element(61), b.count >= 22, Int(b[0]) == primary {
            switch b[1] & 3 {
            case 1: return primary + 2
            case 3: return primary - 2
            default: break
            }
        }
        return nil
    }

    private func element(_ id: UInt8, _ extensionID: UInt8? = nil) -> [UInt8]? {
        items.first { $0.number == id && (extensionID == nil || $0.bytes.first == extensionID) }?.bytes
    }
}
