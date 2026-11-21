import CoreWLAN
import Foundation
import OpenWiloCore

struct ScanResult: Sendable {
    let interface: String
    let networks: [Network]
    let time: Date
    let connection: LiveConnection?
}

struct LiveConnection: Sendable {
    let ssid: String?
    let bssid: String?
    let band: Band
    let channel: Int?
    let width: Int?
    let transmitRate: Double?
    let phy: String?
    let sample: Observation
}

enum SystemScanner {
    static func scan() async throws -> ScanResult {
        try await Task.detached(priority: .userInitiated) {
            guard let interface = CWWiFiClient.shared().interface() else { throw ScanError.noInterface }
            guard interface.powerOn() else { throw ScanError.off }
            let networks = try interface.scanForNetworks(withName: nil, includeHidden: true)
            let time = Date()
            let link = connection(interface, time: time)
            let rows = networks.map { makeNetwork($0, connectedBSSID: link?.bssid, time: time) }
            return ScanResult(interface: interface.interfaceName ?? "Wi-Fi", networks: rows, time: time, connection: link)
        }.value
    }

    private static func makeNetwork(_ network: CWNetwork, connectedBSSID: String?, time: Date) -> Network {
        let channel = network.wlanChannel

        let bssid = network.bssid?.lowercased()
        let ssid = network.ssid ?? network.ssidData.flatMap { data -> String? in
            guard !data.isEmpty, data.contains(where: { $0 != 0 }) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        let data = network.informationElementData ?? Data()
        let elements = WiFiElements.decode(data)
        let width = elements.hasDiscontiguousVHT && elements.ehtWidth == nil ? nil : elements.ehtWidth ?? width(of: channel)
        return Network(
            id: bssid ?? UUID().uuidString, ssid: ssid, bssid: bssid, band: band(of: channel),
            channel: channel?.channelNumber, width: width,
            security: elements.advertisedPersonalSecurity ?? security(network),
            phy: phy(network, elements), country: network.countryCode,
            elements: data, connected: bssid != nil && bssid == connectedBSSID,
            samples: [Observation(time: time, rssi: measurement(network.rssiValue),
                                  noise: measurement(network.noiseMeasurement))]
        )
    }

    private static func measurement(_ value: Int) -> Int? {
        (-160 ... -1).contains(value) ? value : nil
    }

    private static func connection(_ interface: CWInterface, time: Date) -> LiveConnection? {
        let bssid = interface.bssid()?.lowercased()
        let rate = interface.transmitRate()
        let mode = interface.activePHYMode()
        guard bssid != nil || (mode.rawValue != 0 && rate.isFinite && rate > 0) else { return nil }
        let ssid = interface.ssid()
        let channel = interface.wlanChannel()
        let sample = Observation(time: time, rssi: measurement(interface.rssiValue()),
                                 noise: measurement(interface.noiseMeasurement()))
        guard interface.bssid()?.lowercased() == bssid else { return nil }
        return LiveConnection(ssid: ssid, bssid: bssid, band: band(of: channel),
                              channel: channel?.channelNumber, width: width(of: channel),
                              transmitRate: rate.isFinite && rate > 0 ? rate : nil,
                              phy: phyModes.first { $0.0 == mode }?.1, sample: sample)
    }

    private static func band(of channel: CWChannel?) -> Band {
        switch channel?.channelBand {
        case .band2GHz: .two
        case .band5GHz: .five
        case .band6GHz: .six
        default: .unknown
        }
    }

    private static func width(of channel: CWChannel?) -> Int? {
        switch channel?.channelWidth {
        case .width20MHz: 20
        case .width40MHz: 40
        case .width80MHz: 80
        case .width160MHz: 160
        default: nil
        }
    }

    private static let phyModes: [(CWPHYMode, String)] = [
        (.mode11ax, "802.11ax"), (.mode11ac, "802.11ac"), (.mode11n, "802.11n"),
        (.mode11a, "802.11a"), (.mode11g, "802.11g"), (.mode11b, "802.11b")
    ]

    private static func phy(_ network: CWNetwork, _ elements: WiFiElements) -> String {
        if elements.advertisesEHT { return "802.11be" }
        return phyModes.first { network.supportsPHYMode($0.0) }?.1 ?? "未知"
    }

    private static func security(_ network: CWNetwork) -> String {
        let suites: [(CWSecurity, String)] = [
            (.wpa3Transition, "WPA2/WPA3"), (.wpa3Personal, "WPA3-Personal"),
            (.wpa3Enterprise, "WPA3-Enterprise"), (.oweTransition, "OWE Transition"), (.OWE, "OWE"),
            (.wpaPersonalMixed, "WPA/WPA2-Personal"), (.wpaEnterpriseMixed, "WPA/WPA2-Enterprise"),
            (.wpa2Personal, "WPA2-Personal"), (.wpa2Enterprise, "WPA2-Enterprise"),
            (.wpaPersonal, "WPA-Personal"), (.wpaEnterprise, "WPA-Enterprise"),
            (.dynamicWEP, "Dynamic WEP"), (.WEP, "WEP"), (.none, "开放")
        ]
        return suites.first { network.supportsSecurity($0.0) }?.1 ?? "未知"
    }
}

enum ScanError: LocalizedError {
    case noInterface, off

    var errorDescription: String? {
        switch self {
        case .noInterface: return "没有找到可用的 Wi-Fi 接口。"
        case .off: return "Wi-Fi 已关闭。启用 Wi-Fi 后重试。"
        }
    }
}
