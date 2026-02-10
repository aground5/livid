import SwiftUI

struct StyledButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var isPrimary: Bool = true
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isPrimary {
                        Theme.Colors.liquidGradient
                            .overlay(Color.white.opacity(0.1))
                    } else {
                        Color.white.opacity(0.1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}
