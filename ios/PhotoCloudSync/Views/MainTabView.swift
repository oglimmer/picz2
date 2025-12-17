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
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }

            SyncLogView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet.rectangle")
                }
        }
    }
}
