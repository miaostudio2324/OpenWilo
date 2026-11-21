import Charts
import OpenWiloCore
import SwiftUI

extension Band {
    var tint: Color {
        switch self {
        case .two: Color(red: 0.03, green: 0.52, blue: 0.44)
        case .five: Color(red: 0.17, green: 0.41, blue: 0.85)
        case .six: Color(red: 0.62, green: 0.33, blue: 0.77)
        case .unknown: .secondary
        }
    }

    var ticks: [Int] {
        switch self {
        case .two: [1, 6, 11, 14]
        case .five: [36, 64, 100, 132, 165]
        case .six: [1, 57, 113, 169, 233]
        case .unknown: []
        }
    }

    var plotRange: ClosedRange<Double> {
        switch self {
        case .two: 2397...2497
        case .five: 5150...5895
        case .six: 5925...7125
        case .unknown: 0...1
        }
    }
}

enum PlotMode: String, CaseIterable, Identifiable {
    case channels = "信道分布"
    case history = "信号趋势"

    var title: String { L10n.text(rawValue) }
    var id: Self { self }
}

struct SSIDColors {
    private static let hues: [Double] = [0.58, 0.018, 0.43, 0.77, 0.091, 0.91, 0.29, 0.66, 0.15, 0.51, 0.027, 0.84]
    private var indices: [String: Int] = [:]

    mutating func observe(_ networks: [Network]) {
        for name in Set(networks.compactMap(\.ssid)).sorted() where !name.isEmpty && indices[name] == nil {
            indices[name] = indices.count
        }
    }

    func color(for ssid: String?, scheme: ColorScheme) -> Color {
        guard let ssid, let index = indices[ssid] else { return .gray }
        let dark = scheme == .dark
        if Self.hues.indices.contains(index) {
            return Color(hue: Self.hues[index], saturation: dark ? 0.62 : 0.84, brightness: dark ? 1 : 0.70)
        }
        let hue = (Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: dark ? 0.48 : 0.62, brightness: dark ? 0.94 : 0.61)
    }
}

struct ChannelPlot: View {
    let band: Band
    let networks: [Network]
    let selected: Set<String>
    let colors: SSIDColors
    let choose: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hoverID: String?

    private struct Curve: Identifiable {
        let id: String
        let title: String
        let signal: Int
        let color: Color
        let estimated: Bool
        let peak: CGPoint
        let radius: CGFloat
        let baseline: CGFloat

        var path: Path {
            Path { path in
                path.move(to: CGPoint(x: peak.x - radius, y: baseline))
                path.addCurve(to: peak,
                              control1: CGPoint(x: peak.x - 2 * radius / 3, y: baseline),
                              control2: CGPoint(x: peak.x - radius / 3, y: peak.y))
                path.addCurve(to: CGPoint(x: peak.x + radius, y: baseline),
                              control1: CGPoint(x: peak.x + radius / 3, y: peak.y),
                              control2: CGPoint(x: peak.x + 2 * radius / 3, y: baseline))
            }
        }

        func distance(to point: CGPoint) -> CGFloat {
            let offset = abs(point.x - peak.x)
            let t = min(1, offset / radius)
            let y = peak.y + (baseline - peak.y) * t * t * (3 - 2 * t)
            return hypot(max(0, offset - radius), point.y - y)
        }
    }

    private struct PeakLabel: Identifiable {
        let curve: Curve
        let frame: CGRect
        var id: String { curve.id }
    }

    var body: some View {
        let range = band.plotRange
        let measurements = networks.compactMap { row -> (Network, ChannelSpan, Int)? in
            guard let span = row.span, let signal = row.latest?.rssi,
                  span.lower < range.upperBound, span.upper > range.lowerBound else { return nil }
            return (row, span, signal)
        }
        let axis = RSSIAxis(signals: measurements.map { $0.2 })
        GeometryReader { proxy in
            let size = proxy.size
            let chartHeight = max(1, size.height - 18)
            let plot = CGRect(x: 31, y: 23, width: max(1, size.width - 42), height: max(1, chartHeight - 46))
            let curves = makeCurves(measurements, in: plot, axis: axis)
            let labels = placeLabels(curves, in: plot)
            let hovered = curves.first { $0.id == hoverID }
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(band.tint).frame(width: 7, height: 7)
                    Text(band.rawValue).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(hovered.map { "\($0.title) · \($0.signal) dBm" } ?? L10n.format("%ld 条曲线", curves.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: 18)

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        drawGrid(in: context, plot: plot, axis: axis)
                        var clipped = context
                        clipped.clip(to: Path(plot))
                        for curve in curves {
                            draw(curve, in: clipped)
                        }
                        for label in labels {
                            drawLeader(label, in: context)
                        }
                    }
                    .accessibilityHidden(true)

                    axisLabels(plot, axis: axis)
                    if curves.isEmpty {
                        Text(L10n.text("无可绘制网络")).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    ForEach(labels) { label in
                        Button {
                            choose(label.id)
                        } label: {
                            Text(label.curve.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(label.curve.color)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .frame(width: label.frame.width, height: label.frame.height)
                                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: label.frame.midX, y: label.frame.midY)
                        .help("\(label.curve.title) · \(label.curve.signal) dBm")
                        .accessibilityLabel("\(label.curve.title)，\(label.curve.signal) dBm")
                    }
                }
                .frame(height: chartHeight)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if let id = nearestCurve(at: location, curves: curves, plot: plot)?.id { choose(id) }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverID = nearestCurve(at: location, curves: curves, plot: plot)?.id
                    case .ended:
                        hoverID = nil
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.format("%@ 信道图，%ld 条网络曲线", band.rawValue, curves.count))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    }

    private func makeCurves(_ measurements: [(Network, ChannelSpan, Int)], in plot: CGRect, axis: RSSIAxis) -> [Curve] {
        measurements.map { row, span, signal in
            let title = row.ssid?.isEmpty == false ? row.name : L10n.text("隐藏 SSID")
            let peak = CGPoint(x: x(span.center, in: plot), y: y(signal, in: plot, axis: axis))
            return Curve(id: row.id, title: title, signal: signal,
                         color: colors.color(for: row.ssid, scheme: scheme), estimated: span.estimated,
                         peak: peak, radius: max(1, x(span.upper, in: plot) - peak.x), baseline: plot.maxY)
        }.sorted {
            let firstSelected = selected.contains($0.id)
            let secondSelected = selected.contains($1.id)
            if firstSelected != secondSelected { return secondSelected }
            if $0.signal != $1.signal { return $0.signal < $1.signal }
            return $0.id < $1.id
        }
    }

    private func x(_ frequency: Double, in plot: CGRect) -> CGFloat {
        let range = band.plotRange
        return plot.minX + (frequency - range.lowerBound) / (range.upperBound - range.lowerBound) * plot.width
    }

    private func y(_ signal: Int, in plot: CGRect, axis: RSSIAxis) -> CGFloat {
        plot.minY + axis.fractionFromTop(signal) * plot.height
    }

    private func drawGrid(in context: GraphicsContext, plot: CGRect, axis: RSSIAxis) {
        var grid = Path()
        for level in axis.ticks.dropLast() {
            let tick = y(level, in: plot, axis: axis)
            grid.move(to: CGPoint(x: plot.minX, y: tick))
            grid.addLine(to: CGPoint(x: plot.maxX, y: tick))
        }
        for frequency in band.ticks.compactMap(band.frequency(channel:)) {
            let tick = x(frequency, in: plot)
            grid.move(to: CGPoint(x: tick, y: plot.minY))
            grid.addLine(to: CGPoint(x: tick, y: plot.maxY))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.20)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

        let axes = Path { path in
            path.move(to: CGPoint(x: plot.minX, y: plot.minY))
            path.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        }
        context.stroke(axes, with: .color(.secondary.opacity(0.38)), lineWidth: 1)
    }

    private func axisLabels(_ plot: CGRect, axis: RSSIAxis) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(axis.ticks, id: \.self) { level in
                Text(String(level)).position(x: 14, y: y(level, in: plot, axis: axis))
            }
            ForEach(band.ticks, id: \.self) { channel in
                if let frequency = band.frequency(channel: channel) {
                    Text(String(channel)).position(x: x(frequency, in: plot), y: plot.maxY + 12)
                }
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func draw(_ curve: Curve, in context: GraphicsContext) {
        let strength = min(1, max(0, (Double(curve.signal) + 92) / 46))
        let emphasized = selected.contains(curve.id) || hoverID == curve.id
        let path = curve.path
        var area = path
        area.closeSubpath()
        context.fill(area, with: .linearGradient(
            Gradient(colors: [curve.color.opacity(emphasized ? 0.37 : 0.12 + 0.21 * strength),
                              curve.color.opacity(0.025)]),
            startPoint: curve.peak, endPoint: CGPoint(x: curve.peak.x, y: curve.baseline)
        ))
        context.stroke(path, with: .color(curve.color.opacity(emphasized ? 1 : 0.47 + 0.46 * strength)),
                       style: StrokeStyle(lineWidth: emphasized ? 2.8 : 1.15 + 1.35 * strength,
                                          lineCap: .round, dash: curve.estimated ? [5, 4] : []))
    }

    private func placeLabels(_ curves: [Curve], in plot: CGRect) -> [PeakLabel] {
        let maxWidth = max(1, min(152, plot.width))
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let prioritized = curves.reversed().sorted {
            ($0.id == hoverID ? 0 : 1) < ($1.id == hoverID ? 0 : 1)
        }
        var labels: [PeakLabel] = []
        for curve in prioritized where (plot.minX...plot.maxX).contains(curve.peak.x) {
            let width = min(maxWidth, ceil((curve.title as NSString).size(withAttributes: [.font: font]).width) + 13)
            let center = min(plot.maxX - width / 2, max(plot.minX + width / 2, curve.peak.x))
            let candidates = [-23.0, -43.0, 7.0].map {
                CGRect(x: center - width / 2, y: curve.peak.y + $0, width: width, height: 17)
            }
            if let frame = candidates.first(where: { candidate in
                candidate.minY >= 0 && candidate.maxY <= plot.maxY &&
                    !labels.contains { $0.frame.insetBy(dx: -3, dy: -2).intersects(candidate) }
            }) {
                labels.append(PeakLabel(curve: curve, frame: frame))
            }
        }
        return labels
    }

    private func drawLeader(_ label: PeakLabel, in context: GraphicsContext) {
        let peak = label.curve.peak
        let frame = label.frame
        let end = CGPoint(x: min(frame.maxX, max(frame.minX, peak.x)),
                          y: frame.midY < peak.y ? frame.maxY : frame.minY)
        let leader = Path { path in
            path.move(to: peak)
            path.addLine(to: end)
        }
        context.stroke(leader, with: .color(label.curve.color.opacity(0.60)), lineWidth: 1)
    }

    private func nearestCurve(at location: CGPoint, curves: [Curve], plot: CGRect) -> Curve? {
        guard plot.contains(location) else { return nil }
        let nearest = curves.reversed().min { $0.distance(to: location) < $1.distance(to: location) }
        return nearest.flatMap { $0.distance(to: location) <= 10 ? $0 : nil }
    }
}

struct SignalPlot: View {
    let visible: [Network]
    let selection: Set<String>

    private var displayed: [Network] {
        let available = visible.filter { network in network.samples.contains { $0.rssi != nil } }
        let focused = available.filter { selection.contains($0.id) }
        return Array((focused.isEmpty ? available : focused).prefix(6))
    }

    var body: some View {
        let rows = displayed
        if rows.isEmpty {
            ContentUnavailableView(L10n.text("暂无信号记录"), systemImage: "waveform.path")
        } else {
            let minimum = min(-100, rows.flatMap(\.samples).compactMap(\.rssi).min() ?? -100)
            Chart(rows) { network in
                let label = "\(network.name) · \(network.bssid.map { String($0.suffix(5)) } ?? String(network.id.prefix(5)))"
                ForEach(Array(network.samples.enumerated()), id: \.offset) { entry in
                    if let rssi = entry.element.rssi {
                        if network.samples.count == 1 {
                            PointMark(x: .value(L10n.text("时间"), entry.element.time), y: .value("RSSI", rssi))
                                .foregroundStyle(by: .value(L10n.text("网络"), label))
                        } else {
                            LineMark(x: .value(L10n.text("时间"), entry.element.time), y: .value("RSSI", rssi),
                                     series: .value(L10n.text("网络标识"), network.id))
                                .foregroundStyle(by: .value(L10n.text("网络"), label))
                                .symbol(Circle().strokeBorder(lineWidth: 1))
                                .symbolSize(12)
                        }
                    }
                }
            }
            .chartYScale(domain: minimum ... -15)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
            .padding(10)
        }
    }
}
