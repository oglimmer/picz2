import SwiftUI

/// Persistent warning while uploads to the site's own storage are refused (507).
///
/// Deliberately has no close button and remembers nothing: it goes away exactly when the server
/// says there is room again, and not before. A dismissed warning would leave the user wondering
/// why their photos stopped arriving. Sits above the tab bar's content in ``RootView`` so it is
/// on screen whichever tab is showing.
struct StorageFullBanner: View {
    let usage: StorageUsage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your storage on this site is full")
                    .font(.subheadline.weight(.semibold))
                Text("New photos cannot be uploaded until you free some space or add your own storage under Options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Hidden while the only evidence is a 507 and the numbers have not arrived yet.
                if let usage, usage.quotaBytes > 0 {
                    Text(usage.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.orange).frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

#Preview {
    VStack(spacing: 0) {
        StorageFullBanner(usage: StorageUsage(
            usedBytes: 104_857_600, quotaBytes: 104_857_600, remainingBytes: 0, full: true,
        ))
        Spacer()
    }
}
