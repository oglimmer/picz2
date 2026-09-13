import SwiftUI

struct MainTabView: View {
    @Binding var isLoggedIn: Bool
    /// Observed directly for the Status tab's switch, the same way `SyncOptionsView` does (§5.5).
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        TabView {
            AlbumListView()
                .tabItem {
                    Label("Albums", systemImage: "photo.on.rectangle.angled")
                }

            SyncOptionsView(isLoggedIn: $isLoggedIn)
                .tabItem {
                    Label("Options", systemImage: "gearshape")
                }

            // Only with Profile → Debug Information on. The switch lives in the Options tab, so
            // turning it off never removes the tab the user is looking at.
            if settings.showsDebugInformation {
                SyncLogView()
                    .tabItem {
                        Label("Status", systemImage: "chart.bar.doc.horizontal")
                    }
            }
        }
    }
}
