import SwiftUI

struct ErrorOverlay: View {
    @Environment(EditorViewModel.self) private var viewModel

    var body: some View {
        if let error = viewModel.errorMessage, viewModel.errorLineNumber > 0 {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: "#dc2626"))
                    .frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(hex: "#fca5a5"))
                        .font(.system(size: 11))
                    Text("Line \(viewModel.errorLineNumber): \(error)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#fca5a5"))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "#3b1515"))
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
