#if canImport(AVFoundation)
import Accelerate
import AVFoundation
import DedupCore

/// Measures how loud a file is over time, for the player's waveform.
public enum WaveformReader {
    public enum Failure: Error, Hashable, Sendable {
        case noBuffer
    }

    /// Decodes the whole file and measures `slices` equal slices of it: the
    /// peak and root mean square of the samples in every channel. A long file
    /// takes a moment, so this throws `CancellationError` as soon as the task
    /// running it is cancelled.
    public static func read(_ url: URL, slices: Int = 1_000) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, slices > 0 else { return Waveform(peaks: [], levels: []) }
        // Decoded audio is always 32-bit floats, one buffer per channel.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 16),
              let channels = buffer.floatChannelData
        else { throw Failure.noBuffer }
        var meter = SliceMeter(slices: Int(min(Int64(slices), file.length)), frames: file.length)
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            meter.add(channels, count: Int(buffer.format.channelCount), frames: Int(buffer.frameLength))
        }
        return meter.waveform
    }
}

/// Adds up the peak and level of each slice as the audio is decoded, buffer by
/// buffer. Slices don't line up with buffers, so each buffer is split where
/// one slice ends and the next begins.
private struct SliceMeter {
    private let frames: Int64
    private var peaks: [Float]
    private var sumsOfSquares: [Double]
    private var sampleCounts: [Int]
    /// Frames added so far.
    private var position: Int64 = 0

    /// `frames` is the file's length. Slice `i` holds the frames from
    /// ⌈i × frames ÷ slices⌉ up to the next slice's first frame.
    init(slices: Int, frames: Int64) {
        self.frames = frames
        peaks = Array(repeating: 0, count: slices)
        sumsOfSquares = Array(repeating: 0, count: slices)
        sampleCounts = Array(repeating: 0, count: slices)
    }

    mutating func add(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>, count channelCount: Int, frames count: Int) {
        let slices = Int64(peaks.count)
        var offset = 0
        while offset < count {
            let frame = position + Int64(offset)
            // A file can decode to more frames than it said it had; they join the last slice.
            let slice = Int(min(frame * slices / frames, slices - 1))
            let nextSliceStart = slice == peaks.count - 1 ? Int64.max : (Int64(slice + 1) * frames + slices - 1) / slices
            let end = Int(min(Int64(count), nextSliceStart - position))
            let length = vDSP_Length(end - offset)
            for channel in 0..<channelCount {
                let samples = channels[channel] + offset
                var peak: Float = 0
                var sumOfSquares: Float = 0
                vDSP_maxmgv(samples, 1, &peak, length)
                vDSP_svesq(samples, 1, &sumOfSquares, length)
                peaks[slice] = max(peaks[slice], peak)
                sumsOfSquares[slice] += Double(sumOfSquares)
            }
            sampleCounts[slice] += (end - offset) * channelCount
            offset = end
        }
        position += Int64(count)
    }

    var waveform: Waveform {
        let levels = zip(sumsOfSquares, sampleCounts).map { sum, count in
            count > 0 ? Float((sum / Double(count)).squareRoot()) : 0
        }
        return Waveform(peaks: peaks, levels: levels)
    }
}
#endif
