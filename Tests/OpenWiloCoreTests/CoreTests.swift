import Foundation
import OpenWiloCore
import Testing

struct CoreTests {
    @Test func channelAxisFitsSignalsAndUsesReadableTicks() {
        let empty = RSSIAxis(signals: [])
        let ordinary = RSSIAxis(signals: [-86, -71, -62])
        #expect(empty.upper == -20)
        #expect(ordinary.upper == -50)
        #expect(ordinary.lower == -110)
        #expect(ordinary.ticks == [-50, -60, -70, -80, -90, -100, -110])
        #expect(ordinary.fractionFromTop(-62) < empty.fractionFromTop(-62))

        let weak = RSSIAxis(signals: [-119])
        #expect(weak.ticks == [-110, -115, -120, -125, -130])
        #expect(weak.fractionFromTop(-119) == 0.45)

        let extreme = RSSIAxis(signals: [Int.min, Int.max])
        #expect(extreme.ticks.first == 0)
        #expect(extreme.ticks.last == -170)
        #expect(extreme.fractionFromTop(Int.min) == 1)
        #expect(extreme.fractionFromTop(Int.max) == 0)
    }

    @Test func decodesNamedAndRepeatedElementsBeforeTruncatedTail() {
        let bytes = Data([11, 5, 3, 1, 128, 0, 0, 221, 1, 4, 221, 1, 5, 48, 3, 1])
        let result = WiFiElements.decode(bytes)
        #expect(result.items.map(\.number) == [11, 221, 221])
        #expect(result.items.map(\.id) == [0, 7, 10])
        #expect(result.truncated)
        #expect(result.bssLoad?.stations == 259)
        #expect(result.bssLoad?.utilization == 128.0 / 255)
    }

    @Test func showsDecodedInformationAndKeepsRawBytes() {
        let data = Data([0, 3, 65, 80, 49, 3, 1, 36, 11, 5, 5, 0, 128, 0, 0,
                         221, 3, 0x00, 0x11, 0x22, 192, 2, 1, 42])
        let elements = WiFiElements.decode(data).items
        #expect(elements[0].decodedFields == ["网络名称：AP1"])
        #expect(elements[1].decodedFields == ["主信道：36"])
        #expect(elements[2].decodedFields.first == "台站数量：5")
        #expect(elements[3].decodedFields == ["厂商 OUI：00:11:22"])
        #expect(elements[4].decodedFields.isEmpty)
        #expect(elements[4].hex == "01 2A")
    }

    @Test func decodesVHTHEAndEHTChannelCenters() {
        let vht = Network.fixture(band: .five, channel: 36, width: 160,
                                  elements: Data([192, 5, 1, 42, 50, 0, 0]))
        let he = Network.fixture(band: .six, channel: 37, width: 80,
                                 elements: Data([255, 12, 36, 0, 0, 2, 0, 0, 0, 37, 2, 39, 0, 0]))
        let eht = Network.fixture(band: .six, channel: 5, width: 320,
                                  elements: Data([255, 9, 106, 1, 0, 0, 0, 0, 4, 15, 31]))
        #expect(vht.span?.center == 5250)
        #expect(he.span?.center == 6145)
        #expect(eht.span?.center == 6105)
        #expect(eht.span?.estimated == false)
    }

    @Test func overlappingEdgesAndMissingCenter() throws {
        let first = try #require(Network.fixture().span)
        let adjacent = try #require(Network.fixture(channel: 40).span)
        let estimated = try #require(Network.fixture(channel: 36, width: 40).span)
        #expect(!first.overlaps(adjacent))
        #expect(estimated.overlaps(adjacent))
        #expect(estimated.estimated)
        #expect(Band.two.frequency(channel: 14) == 2484)
        #expect(Band.six.frequency(channel: 2) == 5935)
    }

    @Test func distinguishesPSKFastTransitionFromWPA3Transition() {
        func rsn(_ suiteTypes: [UInt8]) -> [UInt8] {
            let suites: [UInt8] = suiteTypes.flatMap { [0x00, 0x0f, 0xac, $0] }
            let payload: [UInt8] = [1, 0, 0, 0x0f, 0xac, 4, 1, 0, 0, 0x0f, 0xac, 4,
                                     UInt8(suiteTypes.count), 0] + suites
            return [48, UInt8(payload.count)] + payload
        }

        let legacyWPA: [UInt8] = [221, 22, 0, 0x50, 0xf2, 1, 1, 0, 0, 0x50, 0xf2, 2,
                                  1, 0, 0, 0x50, 0xf2, 2, 1, 0, 0, 0x50, 0xf2, 2]
        #expect(WiFiElements.decode(Data(rsn([2, 4]))).advertisedPersonalSecurity == "WPA2-Personal")
        #expect(WiFiElements.decode(Data(rsn([2, 8]))).advertisedPersonalSecurity == "WPA2/WPA3")
        #expect(WiFiElements.decode(Data(rsn([24, 25]))).advertisedPersonalSecurity == "WPA3-Personal")
        #expect(WiFiElements.decode(Data(rsn([2]) + legacyWPA)).advertisedPersonalSecurity == "WPA/WPA2-Personal")
        #expect(WiFiElements.decode(Data(rsn([1]))).advertisedPersonalSecurity == nil)
        #expect(WiFiElements.decode(Data(rsn([2, 4]).dropLast())).advertisedPersonalSecurity == nil)
    }

    @Test func sessionRoundTripsAndRejectsDuplicateIDs() throws {
        let network = Network.fixture()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let session = ScanSession(source: "演示", networks: [network])
        try session.encoded().write(to: file)
        #expect(try ScanSession.read(from: file).networks == [network])
        try ScanSession(source: "演示", networks: [network, network]).encoded().write(to: file)
        #expect(throws: (any Error).self) { try ScanSession.read(from: file) }
    }

    @Test func csvQuotesUserControlledTextAndKeepsMeasurementsNumeric() {
        let network = Network.fixture(ssid: " =42", note: "房间 1,\"临窗\"\n第二行")
        let output = String(decoding: ScanSession.csv([network]), as: UTF8.self)
        #expect(output.hasPrefix("\u{FEFF}SSID,"))
        #expect(output.contains("\"' =42\","))
        #expect(output.contains(",20,-60,-95,35,"))
        #expect(output.contains("\"房间 1,\"\"临窗\"\"\n第二行\""))
    }
}

private extension Network {
    static func fixture(ssid: String = "Studio", band: Band = .five, channel: Int = 36, width: Int = 20,
                        elements: Data = Data(), note: String = "") -> Self {
        Network(id: "02:00:00:00:00:01", ssid: ssid, bssid: "02:00:00:00:00:01", band: band, channel: channel,
                width: width, security: "WPA3-Personal", phy: "802.11ax", elements: elements,
                samples: [Observation(time: Date(timeIntervalSince1970: 1_730_000_000), rssi: -60, noise: -95)],
                note: note)
    }
}
