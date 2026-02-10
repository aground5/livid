import SwiftUI

struct TrimView: View {
    @Bindable var viewModel: MainViewModel
    
    var body: some View {
        Group {
            if viewModel.selectedVideoURL != nil {
                VStack(spacing: 24) {
                    // Simulating a video trim timeline
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 60)
                        
                        // Trim selection
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.Colors.liquidGradient, lineWidth: 2)
                            .background(Theme.Colors.liquidGradient.opacity(0.2))
                            .frame(width: 200, height: 60)
                            .offset(x: 50)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(spacing: 16) {
                        StyledSlider(value: $viewModel.startTime, range: 0...10, title: "Start Time", icon: "arrow.right.to.line", unit: "s")
                        StyledSlider(value: $viewModel.endTime, range: 0...10, title: "End Time", icon: "arrow.left.to.line", unit: "s")
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    StyledButton(title: "Go to Render", icon: "cpu", action: { viewModel.selectedTab = .render })
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            } else {
                PlaceholderView(
                    icon: "scissors",
                    title: "Need a Video",
                    message: "Selecting a video is the first step towards your custom wallpaper.",
                    actionTitle: "Go to Prepare",
                    action: { viewModel.selectedTab = .prepare }
                )
            }
        }
    }
}
