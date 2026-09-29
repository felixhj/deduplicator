import DedupCore
import Foundation

/// What Core Audio reports when it opens a file for decoding.
public struct DecodedAudioInfo: Sendable, Hashable {
    /// Decoded sample frames ÷ sample rate, in seconds.
    public var duration: Double
    /// Nil for PCM, where the container (AIFF or WAV) decides the format.
    public var format: AudioFormat?
    public var sampleRate: Int
    public var channels: Int

    public init(duration: Double, format: AudioFormat? = nil, sampleRate: Int, channels: Int) {
        self.duration = duration
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

#if canImport(AVFoundation)
import AVFoundation

public enum DecodedAudio {
    public enum Failure: Error, Hashable, Sendable {
        case noSampleRate
    }

    /// Opens the file with `AVAudioFile` and measures its length in decoded
    /// frames. This is the only source of `Track.duration`: tags and stream
    /// headers can be wrong.
    public static func read(_ url: URL) throws -> DecodedAudioInfo {
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        guard format.sampleRate > 0 else { throw Failure.noSampleRate }
        return DecodedAudioInfo(
            duration: Double(file.length) / format.sampleRate,
            format: AudioFormat(coreAudioFormatID: format.streamDescription.pointee.mFormatID),
            sampleRate: Int(format.sampleRate.rounded()),
            channels: Int(format.channelCount)
        )
    }
}

extension AudioFormat {
    init?(coreAudioFormatID id: AudioFormatID) {
        switch id {
        case kAudioFormatMPEGLayer3:
            self = .mp3
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC_ELD_SBR,
             kAudioFormatMPEG4AAC_ELD_V2:
            self = .aac
        case kAudioFormatAppleLossless:
            self = .alac
        case kAudioFormatFLAC:
            self = .flac
        default:
            return nil
        }
    }
}
#endif
