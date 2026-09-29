import AppKit
import SwiftUI

extension View {
    /// Shows what an update check found: a newer version to download, or,
    /// after a check from the menu, that there's none or the check failed.
    func updateAlert(_ updates: UpdateChecker) -> some View {
        let isShowing = Binding(
            get: { updates.finding != nil },
            set: { if !$0 { updates.finding = nil } }
        )
        return alert(Self.title(of: updates.finding), isPresented: isShowing, presenting: updates.finding) { finding in
            if case .newer(let release) = finding {
                Button("Download…") { NSWorkspace.shared.open(release.pageURL) }
                Button("Skip This Version") { updates.skip(release) }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { finding in
            switch finding {
            case .newer:
                Text("You have version \(updates.currentVersion). Download the new one from GitHub, then put it in your Applications folder in place of this one.")
            case .upToDate:
                Text("Version \(updates.currentVersion) is the latest.")
            case .failed(let reason):
                Text(reason)
            }
        }
    }

    private static func title(of finding: UpdateChecker.Finding?) -> String {
        switch finding {
        case .newer(let release): "Deduplicator \(release.version) Is Available"
        case .upToDate: "You're Up to Date"
        case .failed: "Couldn't Check for Updates"
        case nil: ""
        }
    }
}
