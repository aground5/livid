import SwiftUI

struct StyledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let title: String
    let icon: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(String(format: "%.1f", value))\(unit)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
        .padding(Theme.Spacing.medium)
        .background(Material.thin)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
