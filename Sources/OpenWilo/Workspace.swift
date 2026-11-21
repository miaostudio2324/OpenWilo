import AppKit
import CoreLocation
import OpenWiloCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Workspace: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Source: String {
        case live = "本机扫描"
        case file = "离线会话"

        var title: String { L10n.text(rawValue) }
    }

    @Published private(set) var source: Source = .live
    @Published private(set) var networks: [Network] = []
    @Published private(set) var lastScan: Date?
    @Published private(set) var interfaceName: String?
    @Published private(set) var busy = false
    @Published private(set) var continuous = false
    @Published var message: String?
    @Published var band: Band?
    @Published var selected: Set<String> = []
    @Published var hiddenFromCharts: Set<String> = []
    @Published private(set) var connection: LiveConnection?
    private(set) var ssidColors = SSIDColors()

    private let location = CLLocationManager()
    private var permissionPending = false
    private var scanAfterAuthorization = false
    private var loop: Task<Void, Never>?
    private var loopID: UUID?
    private var history: [String: [Observation]] = [:]
    private var notes = UserDefaults.standard.dictionary(forKey: "networkNotes") as? [String: String] ?? [:]

    override init() {
        super.init()
        location.delegate = self
    }

    func startScanning() {
        guard !busy, loopID == nil, !permissionPending else { return }
        if source == .file {
            hiddenFromCharts.removeAll()
            resetResults()
        }
        source = .live
        message = nil
        let id = UUID()
        loopID = id
        continuous = true
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard await performScan() else { break }
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
            guard let self, loopID == id else { return }
            continuous = false
            loop = nil
            loopID = nil
        }
    }

    func stop() {
        loop?.cancel()
        continuous = false
    }

    func requestLocation() {
        guard !busy, loopID == nil else { return }
        scanAfterAuthorization = true
        switch location.authorizationStatus {
        case .notDetermined:
            permissionPending = true
            location.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        case .authorizedAlways:
            permissionChanged()
        default:
            scanAfterAuthorization = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.permissionChanged() }
    }

    private func permissionChanged() {
        let status = location.authorizationStatus
        guard status != .notDetermined, scanAfterAuthorization else { return }
        let prompted = permissionPending
        permissionPending = false
        if status == .authorizedAlways {
            scanAfterAuthorization = false
            startScanning()
        } else if prompted {
            scanAfterAuthorization = false
            message = L10n.text("可在系统设置的定位服务中为 OpenWilo 授权。")
        }
    }

    private func performScan() async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let result = try await SystemScanner.scan()
            guard !Task.isCancelled else { return false }
            connection = result.connection
            lastScan = result.time
            interfaceName = result.interface
            let cutoff = result.time.addingTimeInterval(-900)
            history = history.filter { ($0.value.last?.time ?? .distantPast) >= cutoff }
            var unique: [String: Network] = [:]
            for row in result.networks where (unique[row.id]?.rssiOrder ?? Int.min) < row.rssiOrder {
                unique[row.id] = row
            }
            let updated = unique.values.map { row -> Network in
                var entry = row
                if let sample = row.latest, let bssid = row.bssid {
                    let samples = (history[bssid] ?? []).filter { $0.time >= cutoff } + [sample]
                    entry.samples = Array(samples.suffix(180))
                    history[bssid] = entry.samples
                    entry.note = notes[bssid] ?? ""
                }
                return entry
            }
            hiddenFromCharts = hiddenFromCharts.filter { history[$0] != nil || unique[$0] != nil }
            setNetworks(updated)
            selected.formIntersection(updated.map(\.id))
            if !updated.isEmpty && updated.allSatisfy({ $0.bssid == nil }) {
                message = L10n.text("macOS 未提供 BSSID。请检查定位授权后重新扫描。")
            } else if updated.isEmpty &&
                location.authorizationStatus != .authorizedAlways {
                message = L10n.text("没有返回网络。定位授权可能影响扫描结果。")
            } else {
                message = nil
            }
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            connection = nil
            message = L10n.format("扫描失败。%@", error.localizedDescription)
            return false
        }
    }

    func note(_ text: String, for id: String) {
        guard let index = networks.firstIndex(where: { $0.id == id }) else { return }
        networks[index].note = text
        if source == .live, let bssid = networks[index].bssid {
            notes[bssid] = text.isEmpty ? nil : text
            UserDefaults.standard.set(notes, forKey: "networkNotes")
        }
    }

    func openSession() {
        guard !busy, loopID == nil, !permissionPending else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let session = try ScanSession.read(from: url)
            stop()
            resetResults()
            source = .file
            hiddenFromCharts.removeAll()
            setNetworks(session.networks)
            lastScan = session.date
        } catch {
            message = L10n.format("打开失败。%@", error.localizedDescription)
        }
    }

    func saveSession() {
        let snapshot = ScanSession(date: lastScan ?? .now, source: source.rawValue, networks: networks)
        save(L10n.text("OpenWilo-会话.json"), type: .json) { try snapshot.encoded() }
    }

    func exportCSV(_ rows: [Network]) {
        save(L10n.text("OpenWilo-网络.csv"), type: .commaSeparatedText) { ScanSession.csv(rows) }
    }

    private func save(_ filename: String, type: UTType, data: () throws -> Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data().write(to: url, options: .atomic)
        } catch {
            message = L10n.format("保存失败。%@", error.localizedDescription)
        }
    }

    private func setNetworks(_ rows: [Network]) {
        ssidColors.observe(rows)
        networks = rows
    }

    private func resetResults() {
        networks = []
        history = [:]
        connection = nil
        selected = []
        band = nil
        interfaceName = nil
        lastScan = nil
        message = nil
    }
}
