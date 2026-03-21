import SwiftUI
import UniformTypeIdentifiers

struct DeveloperHelperView: View {
    @State private var statusMessage: String = "Ready"
    @State private var isCheckingHealth = false
    
    var body: some View {
        Form {
            Section("Developer Tools") {
                Button(isCheckingHealth ? "Checking Helper..." : "Check Helper Connection") {
                    Task {
                        await checkHelperConnection()
                    }
                }
                .disabled(isCheckingHealth)
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
    
    @MainActor
    private func checkHelperConnection() async {
        isCheckingHealth = true
        defer { isCheckingHealth = false }
        
        do {
            statusMessage = try await HelperServiceConnection.shared.checkHealth()
        } catch {
            statusMessage = "Helper check failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DeveloperHelperView()
}
