import SwiftUI
import UniformTypeIdentifiers

struct DeveloperHelperView: View {
    @State private var statusMessage: String = "Ready"
    
    var body: some View {
        Form {
            Section("Developer Tools") {
                Text("Developer helper tools and tests go here.")
            }
            
            Section("Status") {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

#Preview {
    DeveloperHelperView()
}
