import DedupCore
import SwiftUI

/// A track's waveform, with the part already played in the accent colour and
/// a line at the position. Until the waveform is drawn, a flat line stands in.
struct WaveformView: View {
    let waveform: Waveform?
    /// How far through the track the position is, from 0 to 1.
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            var peaks = Path()
            var levels = Path()
            if let waveform, waveform.count > 0 {
                // One column per point, each at least a hairline so silence still shows.
                let columns = max(1, Int(size.width.rounded()))
                let shown = waveform.resampled(to: columns)
                let width = size.width / CGFloat(columns)
                for column in 0..<columns {
                    let x = CGFloat(column) * width
                    let peak = max(CGFloat(shown.peaks[column]) * middle, 0.5)
                    let level = CGFloat(shown.levels[column]) * middle
                    peaks.addRect(CGRect(x: x, y: middle - peak, width: width, height: peak * 2))
                    levels.addRect(CGRect(x: x, y: middle - level, width: width, height: level * 2))
                }
            } else {
                peaks.addRect(CGRect(x: 0, y: middle - 0.5, width: size.width, height: 1))
            }

            let split = size.width * min(max(progress, 0), 1)
            var played = context
            played.clip(to: Path(CGRect(x: 0, y: 0, width: split, height: size.height)))
            played.fill(peaks, with: .color(.accentColor.opacity(0.45)))
            played.fill(levels, with: .color(.accentColor))
            var unplayed = context
            unplayed.clip(to: Path(CGRect(x: split, y: 0, width: size.width - split, height: size.height)))
            unplayed.fill(peaks, with: .color(.primary.opacity(0.22)))
            unplayed.fill(levels, with: .color(.primary.opacity(0.45)))
            context.fill(Path(CGRect(x: min(split, size.width - 1.5), y: 0, width: 1.5, height: size.height)), with: .color(.primary.opacity(0.75)))
        }
    }
}
