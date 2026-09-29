import Foundation

/// How loud a track is over time, for drawing: the peak and the average level
/// of each of a number of equal slices of the audio, from start to end.
///
/// Values are kept to 1/255 of full scale, finer than a view can show, so a
/// waveform saved to disk reads back exactly as it was.
public struct Waveform: Sendable, Hashable {
    /// The loudest sample in each slice, from 0 (silence) to 1 (full scale).
    public let peaks: [Float]
    /// The root mean square of each slice, on the same scale: how loud it sounds.
    public let levels: [Float]

    /// Values are clamped to 0...1. There must be as many levels as peaks.
    public init(peaks: [Float], levels: [Float]) {
        precondition(peaks.count == levels.count, "Every slice needs a peak and a level")
        self.peaks = peaks.map { Float(Self.byte($0)) / 255 }
        self.levels = levels.map { Float(Self.byte($0)) / 255 }
    }

    public var count: Int { peaks.count }

    /// The waveform stretched or squeezed to `count` slices, such as one per
    /// point of the view drawing it. Squeezing keeps the loudest of the slices
    /// merged into each one, so short peaks don't vanish from a narrow view.
    public func resampled(to count: Int) -> Waveform {
        guard count > 0, !peaks.isEmpty else { return Waveform(peaks: [], levels: []) }
        guard count != self.count else { return self }
        var peaks = [Float](repeating: 0, count: count)
        var levels = peaks
        for index in 0..<count {
            let start = index * self.count / count
            let end = max(start + 1, (index + 1) * self.count / count)
            peaks[index] = self.peaks[start..<end].max() ?? 0
            levels[index] = self.levels[start..<end].max() ?? 0
        }
        return Waveform(peaks: peaks, levels: levels)
    }

    fileprivate static func byte(_ value: Float) -> UInt8 {
        guard !value.isNaN else { return 0 }
        return UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}

extension Waveform: Codable {
    private enum CodingKeys: String, CodingKey {
        case peaks, levels
    }

    /// Each value is stored as one byte, so JSON holds a waveform as two short
    /// Base64 strings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let peaks = try container.decode(Data.self, forKey: .peaks)
        let levels = try container.decode(Data.self, forKey: .levels)
        guard peaks.count == levels.count else {
            throw DecodingError.dataCorruptedError(forKey: .levels, in: container, debugDescription: "Every slice needs a peak and a level")
        }
        self.init(peaks: peaks.map { Float($0) / 255 }, levels: levels.map { Float($0) / 255 })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Data(peaks.map(Self.byte)), forKey: .peaks)
        try container.encode(Data(levels.map(Self.byte)), forKey: .levels)
    }
}
