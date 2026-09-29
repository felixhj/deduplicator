import DedupCore
import Foundation
import Synchronization
@testable import DedupScanner

/// Makes a fresh folder for one test and deletes it afterwards.
func withTemporaryFolder<T>(_ body: (URL) async throws -> T) async throws -> T {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "DedupScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    return try await body(folder)
}

extension URL {
    /// Creates the file, and any folders it needs, with the given contents.
    @discardableResult
    func create(_ contents: String = "") throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: self)
        return self
    }

    func setModified(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: filePath)
    }
}

/// Audio files for tests. WAV and MP3 are written by hand, so they work on
/// Linux too; the other formats need Core Audio's encoders.
enum AudioFixtures {
    /// 16-bit PCM silence.
    static func writeWAV(to url: URL, seconds: Double, sampleRate: Int = 44_100, channels: Int = 2) throws {
        let blockAlign = channels * 2
        let dataSize = Int(Double(sampleRate) * seconds) * blockAlign
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channels))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * blockAlign))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(dataSize))
        data.append(Data(count: dataSize))
        try data.write(to: url)
    }

    /// Silent MPEG-1 Layer III frames at 128 kbit/s, 44.1 kHz, stereo. Each
    /// frame is 417 bytes and holds 1,152 samples; zeroed side info decodes as silence.
    static func writeMP3(to url: URL, frames: Int) throws {
        let frame = [0xFF, 0xFB, 0x90, 0x00] + [UInt8](repeating: 0, count: 417 - 4)
        try Data((0..<frames).flatMap { _ in frame }).write(to: url)
    }

    static let mp3FrameDuration = 1152.0 / 44_100
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

#if canImport(AVFoundation)
import AVFoundation

extension AudioFixtures {
    /// Encodes a quiet 440 Hz tone with Core Audio. The container comes from the
    /// extension: AAC or ALAC in ".m4a", FLAC in ".flac", PCM in ".aiff". The
    /// samples are 16-bit, because the FLAC encoder writes 24-bit files from float input.
    static func encode(to url: URL, format: AudioFormat, seconds: Double, sampleRate: Double = 44_100) throws {
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2]
        switch format {
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 128_000
        case .alac:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 16
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVEncoderBitDepthHintKey] = 16
        case .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsBigEndianKey] = true
            settings[AVLinearPCMIsFloatKey] = false
        default:
            preconditionFailure("Core Audio can't encode \(format)")
        }
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = buffer.int16ChannelData![channel]
            for frame in 0..<Int(frames) {
                samples[frame] = Int16(3000 * sin(2 * .pi * 440 * Double(frame) / sampleRate))
            }
        }
        try file.write(from: buffer)
        file.close()
    }
}
#endif

/// A reader that makes tracks from file names, counts reads and can be slowed
/// down, so scanner tests don't depend on real audio.
final class FakeReader: TrackReader {
    private let reads = Mutex<[String: Int]>([:])
    private let inFlight = Mutex<(now: Int, peak: Int)>((0, 0))
    /// Seconds each read blocks for, like a slow disk.
    let delay: TimeInterval
    let problemFiles: Set<String>

    init(delay: TimeInterval = 0, problemFiles: Set<String> = []) {
        self.delay = delay
        self.problemFiles = problemFiles
    }

    func read(_ file: DiscoveredFile) -> TrackReadResult {
        inFlight.withLock { $0.now += 1; $0.peak = max($0.peak, $0.now) }
        defer { inFlight.withLock { $0.now -= 1 } }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        reads.withLock { $0[file.url.lastPathComponent, default: 0] += 1 }
        let track = TrackBuilder.track(
            for: file,
            metadata: FileMetadata(properties: ["TITLE": [file.url.deletingPathExtension().lastPathComponent]]),
            decoded: nil
        )
        let problems = problemFiles.contains(file.url.lastPathComponent) ? ["Couldn't read the tags."] : []
        return TrackReadResult(track: track, problems: problems)
    }

    var readCounts: [String: Int] { reads.withLock { $0 } }
    var totalReads: Int { readCounts.values.reduce(0, +) }
    var peakConcurrency: Int { inFlight.withLock { $0.peak } }
}

/// Collects progress reports from any thread.
final class ProgressLog: Sendable {
    private let reports = Mutex<[ScanProgress]>([])

    func record(_ progress: ScanProgress) {
        reports.withLock { $0.append(progress) }
    }

    var all: [ScanProgress] { reports.withLock { $0 } }
}
