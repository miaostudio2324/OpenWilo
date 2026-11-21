import AppKit
import OpenWiloCore
import SwiftUI

struct Dashboard: View {
    private static let appIcon = Bundle.main.url(forResource: "OpenWilo", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    @ObservedObject var workspace: Workspace
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var security = ""
    @State private var primaryChannel = ""
    @State private var minRSSI = -100
    @State private var plotMode = PlotMode.channels
    @State private var showFilters = false
    @State private var showInspector = true
    @State private var showComparison = false
    @State private var sort = [KeyPathComparator(\Network.rssiOrder, order: .reverse)]

    private var hasFilters: Bool { !security.isEmpty || minRSSI > -100 || !primaryChannel.isEmpty }

    private var displayed: [Network] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspace.networks.filter { network in
            (workspace.band == nil || network.band == workspace.band) &&
            (query.isEmpty || [network.name, network.bssid ?? "", network.note, L10n.networkValue(network.phy)]
                .contains { $0.localizedCaseInsensitiveContains(query) }) &&
            (security.isEmpty || network.security == security) &&
            (primaryChannel.isEmpty || network.channel.map(String.init) == primaryChannel) &&
            (minRSSI == -100 || network.rssiOrder >= minRSSI)
        }.sorted { first, second in
            let firstHidden = workspace.hiddenFromCharts.contains(first.id)
            let secondHidden = workspace.hiddenFromCharts.contains(second.id)
            if firstHidden != secondHidden { return secondHidden }
            for ordering in sort {
                let result = ordering.compare(first, second)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return first.id < second.id
        }
    }

    var body: some View {
        let rows = displayed
        let selected = rows.filter { workspace.selected.contains($0.id) }
        VStack(spacing: 0) {
            header(rows)
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 14) {
                    if let message = workspace.message { statusBanner(message) }
                    overview(rows.filter { !workspace.hiddenFromCharts.contains($0.id) })
                    results(rows, selectedIDs: Set(selected.map(\.id)))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.secondary)
                if showInspector {
                    Divider()
                    Inspector(network: selected.first, selectionCount: selected.count,
                              peers: workspace.networks, connection: workspace.connection, note: workspace.note)
                        .frame(width: 236)
                        .frame(maxHeight: .infinity)
                        .background(.background)
                }
            }
            Divider()
            footer
        }
        .background(.background)
        .sheet(isPresented: $showComparison) { Comparison(rows: selected) }
    }

    private func header(_ rows: [Network]) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .padding(-3)
                        .accessibilityHidden(true)
                }
                Text("OpenWilo")
                    .font(.system(size: 20, weight: .semibold))
            }
            .accessibilityElement(children: .combine)

            Spacer()
            TextField(L10n.text("搜索 SSID、BSSID 或备注"), text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 225)
                .accessibilityIdentifier("networkSearch")

            Menu {
                Button(L10n.text("打开会话…"), action: workspace.openSession)
                    .disabled(workspace.busy || workspace.continuous)
                Button(L10n.text("保存会话…"), action: workspace.saveSession)
                    .disabled(workspace.networks.isEmpty)
                Button(L10n.text("导出当前列表为 CSV…")) { workspace.exportCSV(rows) }
                    .disabled(rows.isEmpty)
                Button(L10n.text("导出所选网络为 CSV…")) {
                    workspace.exportCSV(rows.filter { workspace.selected.contains($0.id) })
                }
                .disabled(!rows.contains { workspace.selected.contains($0.id) })
            } label: {
                Label(L10n.text("文件"), systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                if workspace.continuous { workspace.stop() }
                else { workspace.startScanning() }
            } label: {
                Label(workspace.continuous ? L10n.text("停止扫描") : L10n.text("扫描"),
                      systemImage: workspace.continuous ? "stop.fill" : "wifi")
                    .frame(minWidth: 74)
            }
            .buttonStyle(.borderedProminent)
            .tint(workspace.continuous ? Color.blue : Color.secondary)
            .keyboardShortcut("r")
            .disabled(workspace.busy && !workspace.continuous)

            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right").padding(.horizontal, 2)
            }
            .help(showInspector ? L10n.text("隐藏网络详情") : L10n.text("显示网络详情"))
            .accessibilityLabel(showInspector ? L10n.text("隐藏网络详情") : L10n.text("显示网络详情"))
        }
        .controlSize(.large)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.text("频段")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 8)
            bandRow(nil, title: L10n.text("全部网络"), icon: "point.3.connected.trianglepath.dotted")
            ForEach(Band.plotted) { band in
                bandRow(band, title: band.rawValue, icon: "wave.3.right")
            }
            if workspace.networks.contains(where: { $0.band == .unknown }) {
                bandRow(.unknown, title: L10n.text("未知频段"), icon: "questionmark.circle")
            }
            Spacer()

            Text(L10n.text("数据来源")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 8)
            HStack(spacing: 7) {
                Circle().fill(workspace.source == .live ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(workspace.source.title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 8)
            Button(action: workspace.requestLocation) {
                Label(L10n.text("定位授权"), systemImage: "location")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(workspace.busy || workspace.continuous)
            .padding(.horizontal, 8)
        }
        .padding(13)
        .padding(.vertical, 5)
        .frame(width: 153)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private func bandRow(_ band: Band?, title: String, icon: String) -> some View {
        let count = workspace.networks.count { band == nil || $0.band == band }
        let current = workspace.band == band
        return Button {
            workspace.band = band
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(band?.tint ?? Color.accentColor)
                    .frame(width: 16)
                Text(title).font(.subheadline.weight(current ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 3)
                Text(String(count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(current ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func overview(_ rows: [Network]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(L10n.text("无线环境")).font(.title3.weight(.semibold))
                Spacer()
                Picker(L10n.text("图表"), selection: $plotMode) {
                    ForEach(PlotMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 165)
            }
            if plotMode == .channels {
                HStack(spacing: 9) {
                    let activeBands = channelBands(rows)
                    ForEach(activeBands) { band in
                        ChannelPlot(band: band, networks: rows.filter { $0.band == band },
                                    selected: workspace.selected, colors: workspace.ssidColors) {
                            workspace.selected = [$0]
                        }
                    }
                    if activeBands.isEmpty {
                        ContentUnavailableView(L10n.text("该频段无法绘制"), systemImage: "chart.xyaxis.line")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 300)
                HStack(spacing: 8) {
                    Text(L10n.text("纵轴 RSSI (dBm) · 横轴信道"))
                    Spacer()
                    Text(L10n.text("虚线表示按主信道估算中心"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                SignalPlot(visible: rows, selection: workspace.selected)
                    .frame(height: 196)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
    }

    private func channelBands(_ rows: [Network]) -> [Band] {
        if let band = workspace.band { return band == .unknown ? [] : [band] }
        let hasSixGHz = rows.contains { $0.band == .six }
        return Band.plotted.filter { $0 != .six || hasSixGHz }
    }

    private func results(_ rows: [Network], selectedIDs: Set<String>) -> some View {
        let selectedCount = selectedIDs.count
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(L10n.text("接入点")).font(.title3.weight(.semibold))
                Text("\(rows.count) / \(workspace.networks.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showFilters.toggle()
                } label: {
                    Label(L10n.text("筛选"), systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" :
                            "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showFilters) { filterPanel }
                Button(L10n.text("对比所选") + (selectedCount > 0 ? " · \(selectedCount)" : ""), systemImage: "rectangle.split.2x1") {
                    showComparison = true
                }
                .disabled(selectedCount < 2)
                .help(L10n.text("按住 Command 键选择两个或更多网络"))
                Button(L10n.text("隐藏"), systemImage: "eye.slash") {
                    workspace.hiddenFromCharts.formUnion(selectedIDs)
                }
                .disabled(selectedIDs.isSubset(of: workspace.hiddenFromCharts))
                .help(L10n.text("从图表隐藏所选接入点"))
                Button(L10n.text("显示"), systemImage: "eye") {
                    workspace.hiddenFromCharts.subtract(selectedIDs)
                }
                .disabled(selectedIDs.isDisjoint(with: workspace.hiddenFromCharts))
                .help(L10n.text("在图表中显示所选接入点"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if rows.isEmpty {
                ContentUnavailableView(
                    workspace.networks.isEmpty ? L10n.text("暂无扫描结果") : L10n.text("没有匹配的接入点"),
                    systemImage: workspace.networks.isEmpty ? "wifi" : "magnifyingglass",
                    description: Text(workspace.networks.isEmpty ? L10n.text("使用右上角的扫描按钮查找附近网络。") : L10n.text("调整搜索词、频段或筛选条件。"))
                )
                .frame(maxHeight: .infinity)
            } else {
                Table(rows, selection: $workspace.selected, sortOrder: $sort) {
                    TableColumn(L10n.text("网络 / SSID"), value: \.name) { network in
                        networkCell(network) {
                            HStack(spacing: 7) {
                                let hidden = workspace.hiddenFromCharts.contains(network.id)
                                Image(systemName: hidden ? "eye.slash" : (network.connected ? "checkmark.circle.fill" : "circle.fill"))
                                    .font(.system(size: hidden || network.connected ? 12 : 6))
                                    .foregroundStyle(workspace.ssidColors.color(for: network.ssid, scheme: scheme))
                                    .frame(width: 12)
                                    .accessibilityLabel(hidden ? L10n.text("图表已隐藏") : (network.connected ? L10n.text("当前连接") : L10n.text("可见")))
                                Text(network.name)
                                    .fontWeight(network.connected ? .semibold : .regular)
                                    .lineLimit(1)
                            }
                        }
                    }.width(min: 117, ideal: 160)
                    TableColumn("BSSID") { network in
                        networkCell(network) { Text(network.bssid ?? "—").font(.caption.monospaced()) }
                    }.width(min: 115, ideal: 130)
                    TableColumn(L10n.text("频段")) { network in
                        networkCell(network) { Text(L10n.networkValue(network.band.rawValue)).foregroundStyle(network.band.tint) }
                    }.width(min: 52, ideal: 62)
                    TableColumn(L10n.text("主信道"), value: \.channelOrder) { network in
                        networkCell(network) { Text(number(network.channel)) }
                    }.width(min: 46, ideal: 52)
                    TableColumn("RSSI", value: \.rssiOrder) { network in
                        networkCell(network) {
                            HStack(spacing: 6) {
                                Text(number(network.latest?.rssi)).monospacedDigit()
                                if let rssi = network.latest?.rssi { SignalBars(rssi: rssi) }
                            }
                        }
                    }.width(min: 59, ideal: 75)
                    TableColumn(L10n.text("带宽"), value: \.widthOrder) { network in
                        networkCell(network) { Text(number(network.width, " MHz")) }
                    }.width(min: 52, ideal: 64)
                    TableColumn(L10n.text("安全"), value: \.security) { network in
                        networkCell(network) { Text(L10n.networkValue(network.security)) }
                    }.width(min: 85, ideal: 120)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary).allowsHitTesting(false) }
    }

    private func networkCell<Content: View>(_ network: Network, @ViewBuilder content: () -> Content) -> some View {
        let hidden = workspace.hiddenFromCharts.contains(network.id)
        return content().grayscale(hidden ? 1 : 0).opacity(hidden ? 0.52 : 1)
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(message).font(.subheadline)
            Spacer()
            Button(L10n.text("关闭"), systemImage: "xmark") { workspace.message = nil }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .padding(9)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("筛选接入点")).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    Text(L10n.text("安全类型"))
                    Picker(L10n.text("安全类型"), selection: $security) {
                        Text(L10n.text("全部")).tag("")
                        ForEach(Set(workspace.networks.map(\.security) + [security]).filter { !$0.isEmpty }.sorted(), id: \.self) {
                            Text(L10n.networkValue($0)).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 154)
                }
                GridRow {
                    Text(L10n.text("主信道"))
                    Picker(L10n.text("主信道"), selection: $primaryChannel) {
                        Text(L10n.text("全部")).tag("")
                        let channels = workspace.networks.compactMap(\.channel).map(String.init) + [primaryChannel]
                        ForEach(Set(channels).filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 154)
                }
                GridRow {
                    Text(L10n.text("最低 RSSI"))
                    Stepper(value: $minRSSI, in: -100 ... -20, step: 5) {
                        Text(minRSSI == -100 ? L10n.text("不限") : "\(minRSSI) dBm")
                            .monospacedDigit()
                    }
                    .accessibilityLabel(L10n.text("最低 RSSI"))
                    .frame(width: 154)
                }
            }
            Button(L10n.text("清除筛选")) {
                security = ""
                primaryChannel = ""
                minRSSI = -100
            }
            .disabled(!hasFilters)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if workspace.busy {
                ProgressView().controlSize(.small)
                Text(L10n.text("正在扫描…"))
            } else {
                Image(systemName: workspace.source == .live ? "wifi" : "circle.dotted")
                Text(workspace.continuous ? L10n.text("连续扫描中") : workspace.source.title)
            }
            if let interface = workspace.interfaceName { Text("· \(interface)") }
            Spacer()
            if workspace.source == .live, let time = workspace.lastScan {
                Text(L10n.format("最近扫描 %@", time.formatted(.dateTime.hour().minute().second().locale(L10n.locale))))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

private struct SignalBars: View {
    let rssi: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { position in
                Capsule()
                    .fill(rssi >= [-90, -75, -65, -55][position] ?
                          Color.accentColor.opacity(0.83) : Color.secondary.opacity(0.20))
                    .frame(width: 3, height: CGFloat(4 + position * 2))
            }
        }
        .accessibilityHidden(true)
    }
}

func number(_ value: Int?, _ unit: String = "") -> String {
    value.map { "\($0)\(unit)" } ?? "—"
}
