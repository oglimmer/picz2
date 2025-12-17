import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Photo Uploader")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Use the Share menu in Photos.app to upload photos and videos")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()

            VStack(alignment: .leading, spacing: 10) {
                Label("Select photos in Photos.app", systemImage: "1.circle.fill")
                Label("Click the Share button", systemImage: "2.circle.fill")
                Label("Choose 'Upload Photos'", systemImage: "3.circle.fill")
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
}
