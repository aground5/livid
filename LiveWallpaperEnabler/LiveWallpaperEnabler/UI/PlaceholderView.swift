import SwiftUI

struct PlaceholderView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            if let actionTitle = actionTitle, let action = action {
                StyledButton(title: actionTitle, icon: nil, action: action, isPrimary: true)
                    .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
