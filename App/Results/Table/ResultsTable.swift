import AppKit
import DedupCore
import SwiftUI

/// The results table in SwiftUI. The values passed in are there so SwiftUI
/// calls `updateNSView` when they change; the controller reads the model itself.
struct ResultsTable: NSViewRepresentable {
    let model: ResultsModel
    let player: PlayerModel
    let revision: Int
    let marksRevision: Int
    let columns: [TrackColumn]
    let order: GroupOrder
    let nowPlaying: NowPlaying

    func makeCoordinator() -> ResultsTableController {
        ResultsTableController(model: model, player: player)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update()
    }
}
