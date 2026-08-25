import SwiftUI

struct MainTabView: View {
    @Binding var isLoggedIn: Bool

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

            SyncLogView()
                .tabItem {
                    Label("Status", systemImage: "chart.bar.doc.horizontal")
                }
        }
    }
}
