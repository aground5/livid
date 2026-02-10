import SwiftUI

enum Theme {
    enum Colors {
        // macOS Native Materials & Colors
        static let background = Color.clear // Window background should be clear for vibrancy
        static let glassMaterial = Material.ultraThin
        static let cardMaterial = Material.regular
        
        static let accent = Color.blue
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        
        // Liquid Gradient (for that "liquid glass" feel)
        static let liquidStart = Color.blue.opacity(0.6)
        static let liquidEnd = Color.purple.opacity(0.4)
        
        static var liquidGradient: LinearGradient {
            LinearGradient(
                colors: [liquidStart, liquidEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xl: CGFloat = 32
    }
    
    enum Radius {
        static let card: CGFloat = 16
        static let button: CGFloat = 10
    }
}
