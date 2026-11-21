import OpenWiloCore
import SwiftUI

struct Inspector: View {
    let network: Network?
    let selectionCount: Int
    let peers: [Network]
    let connection: LiveConnection?
    let note: (String, String) -> Void
    @State private var showElements = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("网络详情", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if let connection { connectionDetails(connection) }
                    if let network {
                        details(network).id(network.id)
                    } else if connection == nil {
                        ContentUnavailableView("选择一个接入点", systemImage: "cursorarrow.click.2")
                    }
                }
                .padding(14)
            }
        }
        .sheet(isPresented: $showElements) {
            if let network { ElementInspector(network: network) }
        }
    }

    private func connectionDetails(_ link: LiveConnection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("当前 Wi-Fi 连接", systemImage: "wifi")
                .font(.subheadline.weight(.semibold))
            if let ssid = link.ssid { Text(ssid).font(.headline).textSelection(.enabled) }
            if let bssid = link.bssid {
                Text(bssid).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Grid(alignment: .leading, horizontalSpacing: 7, verticalSpacing: 6) {
                field("发送链路速率", link.transmitRate.map {
                    $0.formatted(.number.precision(.fractionLength(0...1))) + " Mbps"
                } ?? "—")
                field("连接制式", link.phy ?? "—")
                field("信道", "\(link.band.rawValue) · \(number(link.channel))")
                field("信道带宽", number(link.width, " MHz"))
                field("信号 / 噪声", "\(number(link.sample.rssi)) / \(number(link.sample.noise)) dBm")
                field("SNR", number(link.sample.snr, " dB"))
            }
            .font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func details(_ network: Network) -> some View {
        let overlapping = peers.filter { candidate in
            guard let span = network.span, let other = candidate.span else { return false }
            return candidate.id != network.id && candidate.band == network.band && span.overlaps(other)
        }
        let elements = WiFiElements.decode(network.elements)

        return VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text(network.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                Text(network.bssid ?? "BSSID 未提供")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if selectionCount > 1 {
                    Text("已选 \(selectionCount) 个接入点").font(.caption).foregroundStyle(.secondary)
                }
                if network.connected {
                    Label("当前连接", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            HStack(spacing: 8) {
                reading("RSSI", value: network.latest?.rssi, unit: "dBm", color: network.band.tint)
                reading("SNR", value: network.latest?.snr, unit: "dB", color: .primary)
            }

            Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 8) {
                field("频段", network.band.rawValue)
                field("主信道", number(network.channel))
                field("带宽", elements.hasDiscontiguousVHT && network.width == nil ? "80+80 MHz" : number(network.width, " MHz"))
                field("噪声", number(network.latest?.noise, " dBm"))
                field("标准", network.phy)
                field("安全", network.security)
                field("国家/地区", network.country ?? "—")
                if let load = elements.bssLoad {
                    field("台站数量", String(load.stations))
                    field("信道利用率", load.utilization.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .font(.subheadline)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("信道重叠").font(.subheadline.weight(.semibold))
                if network.span == nil {
                    Text("缺少可用的信道或带宽。").foregroundStyle(.secondary)
                } else if overlapping.isEmpty {
                    Text("本次样本中未发现重叠接入点。").foregroundStyle(.secondary)
                } else {
                    Text("\(overlapping.count) 个接入点 · 按信道范围估算").foregroundStyle(.secondary)
                    Text(overlapping.sorted { $0.rssiOrder > $1.rssiOrder }.prefix(3).map(\.name).joined(separator: "、"))
                        .lineLimit(2)
                }
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: 5) {
                Text("备注").font(.subheadline.weight(.semibold))
                TextField("添加备注", text: Binding(get: { network.note }, set: { note($0, network.id) }))
                    .textFieldStyle(.roundedBorder)
            }
            Button("查看信息元素 (\(elements.items.count))", systemImage: "list.bullet.rectangle") {
                showElements = true
            }
            .disabled(network.elements.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reading(_ label: String, value: Int?, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(number(value)).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.quaternary.opacity(0.40), in: RoundedRectangle(cornerRadius: 7))
    }

    private func field(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
    }
}

private struct ElementInspector: View {
    @Environment(\.dismiss) private var dismiss
    let network: Network

    var body: some View {
        let decoded = WiFiElements.decode(network.elements)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(network.name) · 信息元素").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if decoded.truncated {
                Text("末尾存在截断的信息元素。").foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(decoded.items) { element in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(element.number) · \(element.title)").font(.subheadline.weight(.semibold))
                            ForEach(Array(element.decodedFields.enumerated()), id: \.offset) { item in
                                Text(item.element).font(.subheadline).textSelection(.enabled)
                            }
                            Text(element.hex.isEmpty ? "—" : element.hex)
                                .foregroundStyle(.secondary)
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
        .padding(19)
        .frame(width: 640, height: 430)
    }
}

struct Comparison: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [Network]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("对比 \(rows.count) 个接入点").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("属性").foregroundStyle(.secondary).frame(width: 75, alignment: .leading)
                        ForEach(rows) { network in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(network.name).font(.headline)
                                Text(network.bssid ?? "—").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            .frame(width: 144, alignment: .leading)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    comparisonRow("频段") { $0.band.rawValue }
                    comparisonRow("主信道") { number($0.channel) }
                    comparisonRow("带宽") { number($0.width, " MHz") }
                    comparisonRow("RSSI") { number($0.latest?.rssi, " dBm") }
                    comparisonRow("噪声") { number($0.latest?.noise, " dBm") }
                    comparisonRow("SNR") { number($0.latest?.snr, " dB") }
                    comparisonRow("标准") { $0.phy }
                    comparisonRow("安全") { $0.security }
                    comparisonRow("备注") { $0.note.isEmpty ? "—" : $0.note }
                }
                .padding(10)
            }
        }
        .padding(18)
        .frame(width: 690, height: 420)
    }

    private func comparisonRow(_ name: String, value: @escaping (Network) -> String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            ForEach(rows) { network in
                Text(value(network)).lineLimit(2)
            }
        }
        .font(.subheadline)
    }
}
