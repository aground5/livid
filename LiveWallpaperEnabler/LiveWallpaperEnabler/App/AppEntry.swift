import SwiftUI

@available(macOS 26.0, *)
@main
struct LiveWallpaperEnablerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .background(VisualEffectView().ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// Native macOS Vibrancy View
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground // This gives the liquid glass feel
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
