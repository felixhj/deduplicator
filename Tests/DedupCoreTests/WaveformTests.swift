import Foundation
import Testing
@testable import DedupCore

struct WaveformTests {
    /// A waveform whose levels are half its peaks.
    func waveform(_ peaks: [Float]) -> Waveform {
        Waveform(peaks: peaks, levels: peaks.map { $0 / 2 })
    }

    @Test func valuesAreClampedAndKeptToBytes() {
        let clamped = Waveform(peaks: [-1, 0, 2, .nan, .infinity], levels: [0, 0, 0, 0, 0])
        #expect(clamped.peaks == [0, 0, 1, 0, 1])
        #expect(Waveform(peaks: [0.5], levels: [0.25]).peaks == [128.0 / 255])
        #expect(Waveform(peaks: [0.5], levels: [0.25]).levels == [64.0 / 255])
    }

    @Test func squeezingKeepsTheLoudestSlice() {
        let squeezed = waveform([0.1, 0.9, 0.2, 0.3, 0.8, 0.4]).resampled(to: 2)
        #expect(squeezed == waveform([0.9, 0.8]))
        #expect(waveform([0.1, 0.9, 0.2]).resampled(to: 2) == waveform([0.1, 0.9]))
        #expect(waveform([0.1, 0.9, 0.2]).resampled(to: 1) == waveform([0.9]))
    }

    @Test func stretchingRepeatsSlices() {
        #expect(waveform([0.2, 0.8]).resampled(to: 4) == waveform([0.2, 0.2, 0.8, 0.8]))
        #expect(waveform([0.2, 0.8]).resampled(to: 3) == waveform([0.2, 0.2, 0.8]))
    }

    @Test func resamplingToNothingOrFromNothingIsEmpty() {
        #expect(waveform([0.5]).resampled(to: 0).count == 0)
        #expect(waveform([]).resampled(to: 10).count == 0)
        let same = waveform([0.1, 0.2])
        #expect(same.resampled(to: 2) == same)
    }

    @Test func roundTripsThroughJSONExactly() throws {
        let original = Waveform(peaks: (0..<1_000).map { Float($0 % 97) / 96 }, levels: (0..<1_000).map { Float($0 % 13) / 30 })
        let json = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Waveform.self, from: json) == original)
        #expect(json.count < 3_000, "One byte per value, in Base64")
    }

    @Test func decodingMismatchedSlicesFails() {
        let json = Data(#"{"peaks": "AAE=", "levels": "AA=="}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Waveform.self, from: json) }
    }
}
