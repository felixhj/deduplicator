import AppKit
import DedupCore
import SwiftUI

/// The player under the table: play and pause, which copy is in the player,
/// and its waveform, which shows the position and can be clicked or dragged
/// to move it.
struct PlayerBar: View {
    let player: PlayerModel
    /// The bar's width, which decides whether there's room for the copy's name.
    @State private var width: CGFloat = 1000

    /// Narrower than this, the copy's name makes way for the waveform, so the
    /// table's column can get narrow. It's wider than the bar needs with the
    /// name, so showing the name never makes the bar too wide for itself.
    static let widthForName: CGFloat = 520

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(player.track == nil)
            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            if width >= Self.widthForName {
                NowPlayingLabel(track: player.track, failure: player.failure)
                    .frame(minWidth: 120, idealWidth: 250, maxWidth: 250, alignment: .leading)
            }

            PlayerTimeline(player: player)

            Button("Show in Finder", systemImage: "folder") {
                if let url = player.track?.url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(player.track == nil)
            .help("Show in Finder")
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color(nsColor: .windowBackgroundColor))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The copy in the player: the track, then what tells copies apart.
private struct NowPlayingLabel: View {
    let track: Track?
    let failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let track {
                Text(track.displayName)
                    .fontWeight(.semibold)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text(track.copySummary)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing in the player")
                    .foregroundStyle(.secondary)
                Text("Select a copy and press Space")
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .help(track?.url.path(percentEncoded: false) ?? "")
    }
}

/// The position, the waveform and the duration. Only this view reads the
/// position, so only it redraws as the copy plays.
private struct PlayerTimeline: View {
    let player: PlayerModel
    /// Where the pointer is while it's dragged along the waveform.
    @State private var scrubbing: Double?
    @State private var width: CGFloat = 1

    var body: some View {
        let duration = player.duration
        let position = scrubbing ?? player.position
        HStack(spacing: 8) {
            // Elapsed time counts whole seconds, like a clock.
            Text(TrackColumn.formatDuration(position.rounded(.down)))
                .frame(minWidth: 40, alignment: .trailing)
            WaveformView(waveform: player.waveform, progress: duration > 0 ? position / duration : 0)
                .overlay {
                    if player.isDrawingWaveform, player.waveform == nil {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(minWidth: 60)
                .frame(height: 34)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
                .gesture(scrub)
                .accessibilityElement()
                .accessibilityLabel("Position")
                .accessibilityValue("\(TrackColumn.formatDuration(position)) of \(TrackColumn.formatDuration(duration))")
                .accessibilityAdjustableAction { direction in
                    let step = max(duration / 20, 5)
                    player.seek(to: player.position + (direction == .increment ? step : -step))
                }
            Text(TrackColumn.formatDuration(duration))
                .frame(minWidth: 40, alignment: .leading)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .disabled(player.track == nil || duration <= 0)
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in scrubbing = time(at: value.location.x) }
            .onEnded { value in
                player.seek(to: time(at: value.location.x))
                scrubbing = nil
            }
    }

    private func time(at x: CGFloat) -> Double {
        Double(min(max(x / width, 0), 1)) * player.duration
    }
}
