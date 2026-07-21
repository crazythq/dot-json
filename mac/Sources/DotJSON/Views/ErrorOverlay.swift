import SwiftUI

struct ErrorOverlay: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    var body: some View {
        if let error = workspace.activeErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "#fca5a5"))
                    .font(.system(size: 11))
                if workspace.activeErrorLineNumber > 0 {
                    Text("Line \(workspace.activeErrorLineNumber): \(error)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#fca5a5"))
                } else {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#fca5a5"))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: "#3b1515"))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
