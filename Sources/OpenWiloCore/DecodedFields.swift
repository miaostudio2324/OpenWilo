import Foundation

extension WiFiElement {
    var bssLoad: (stations: Int, utilization: Double)? {
        guard bytes.count >= 5 else { return nil }
        return (Int(bytes[0]) | (Int(bytes[1]) << 8), Double(bytes[2]) / 255)
    }

    public var decodedFields: [String] {
        switch number {
        case 0:
            return ["网络名称：\(bytes.allSatisfy { $0 == 0 } ? "隐藏 SSID" : String(decoding: bytes, as: UTF8.self))"]
        case 1, 50:
            let rates = bytes.compactMap { byte -> String? in
                let units = byte & 0x7f
                guard (1...120).contains(units) else { return nil }
                let rate = (Double(units) / 2).formatted(.number.precision(.fractionLength(0...1)))
                return byte & 0x80 == 0 ? rate : "\(rate)（基本）"
            }
            return rates.isEmpty ? [] : ["传统速率 (Mbps)：\(rates.joined(separator: "、"))"]
        case 3 where bytes.count == 1:
            return ["主信道：\(bytes[0])"]
        case 7 where bytes.count >= 3:
            return ["国家/地区代码：\(String(decoding: bytes.prefix(2), as: UTF8.self))"]
        case 11:
            guard let load = bssLoad else { return [] }
            return ["台站数量：\(load.stations)",
                    "信道利用率：\(load.utilization.formatted(.percent.precision(.fractionLength(0))))"]
        case 48:
            let suites = WiFiElements.authenticationSuites(bytes, start: 0, oui: [0x00, 0x0f, 0xac])
            let names: [UInt8: String] = [
                1: "802.1X", 2: "PSK", 3: "FT-802.1X", 4: "FT-PSK", 5: "802.1X-SHA256",
                6: "PSK-SHA256", 8: "SAE", 9: "FT-SAE", 11: "Suite B", 12: "Suite B 192-bit",
                18: "OWE", 24: "SAE Extended Key", 25: "FT-SAE Extended Key"
            ]
            return suites.isEmpty ? [] : ["认证套件 (AKM)：\(suites.sorted().map { names[$0] ?? String($0) }.joined(separator: "、"))"]
        case 61 where bytes.count >= 22:
            let offset = bytes[1] & 3
            let secondary = [0: "无", 1: "上方", 3: "下方"][offset] ?? "保留值"
            return ["主信道：\(bytes[0])", "次信道：\(secondary)"]
        case 192 where bytes.count >= 5:
            return ["中心频率段 0：\(bytes[1] == 0 ? "—" : String(bytes[1]))",
                    "中心频率段 1：\(bytes[2] == 0 ? "—" : String(bytes[2]))"]
        case 221 where bytes.count >= 3:
            return ["厂商 OUI：\(bytes.prefix(3).map { String(format: "%02X", $0) }.joined(separator: ":"))"]
        case 255 where bytes.first == 106 && bytes.count >= 9 && bytes[1] & 1 != 0:
            let widths = [20, 40, 80, 160, 320]
            let index = Int(bytes[6] & 7)
            guard widths.indices.contains(index) else { return [] }
            return ["运行带宽：\(widths[index]) MHz",
                    "中心频率段 0 / 1：\(bytes[7]) / \(bytes[8])"]
        default:
            return []
        }
    }
}
