import SwiftUI
import AVKit

struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer?
    var controlsStyle: AVPlayerViewControlsStyle = .none
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = controlsStyle
        view.player = player
        view.videoGravity = .resizeAspect
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player != player {
            nsView.player = player
        }
    }
}
