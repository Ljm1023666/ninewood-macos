import SwiftUI

struct PlaceholderFeatureView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWEmptyState(title: title, systemImage: systemImage, message: message)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle(title)
    }
}
