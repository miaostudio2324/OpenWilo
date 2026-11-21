public struct RSSIAxis {
    public let lower: Int
    public let upper: Int

    public init(signals: [Int]) {
        guard let weakest = signals.min(), let strongest = signals.max() else {
            lower = -110
            upper = -20
            return
        }

        // Round outward to multiples of 10 dBm with at least 5 dB of headroom where possible.
        let paddedWeakest = Self.clamped(weakest) - 5
        let paddedStrongest = min(0, Self.clamped(strongest) + 5)
        lower = min(-110, ((paddedWeakest - 9) / 10) * 10)
        upper = max(lower + 20, (paddedStrongest / 10) * 10)
    }

    public var ticks: [Int] {
        let span = upper - lower
        let step = span > 80 ? 20 : span > 30 ? 10 : 5
        var levels = Array(stride(from: upper, through: lower, by: -step))
        if levels.last != lower { levels.append(lower) }
        return levels
    }

    public func fractionFromTop(_ signal: Int) -> Double {
        let value = min(upper, max(lower, signal))
        return Double(upper - value) / Double(upper - lower)
    }

    private static func clamped(_ signal: Int) -> Int {
        min(0, max(-160, signal))
    }
}
