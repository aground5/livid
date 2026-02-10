import Foundation
import WebMSupport

@main
struct WebMTestExec {
    static func main() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.count >= 3 else {
            print("Usage: WebMTestExec <input_video> <output_mov> [--quick]")
            return
        }
        
        let inputPath = args[1]
        let outputPath = args[2]
        let quick = args.contains("--quick")
        
        print("--------------------------------------------------")
        print("🚀 FFmpeg-powered Video Transcoder")
        print("📂 Input:  \(inputPath)")
        print("📂 Output: \(outputPath)")
        print("⚡️ Mode:   \(quick ? "Quick (Ultrafast)" : "Quality (Medium)")")
        print("--------------------------------------------------")
        
        do {
            let bridge = try FFmpegBridge(path: inputPath)
            print("[\(Date())] ℹ️ Source Info: \(bridge.width)x\(bridge.height) | \(bridge.codecName) | \(String(format: "%.2f", bridge.duration))s")
            
            let outputURL = URL(fileURLWithPath: outputPath)
            
            if quick {
                try bridge.prepareToMov(outputUrl: outputURL) { progress in
                    let percent = Int(progress * 100)
                    let bar = String(repeating: "█", count: percent / 5) + String(repeating: "░", count: 20 - (percent / 5))
                    print("\r[\(Date())] 🔄 Preparing: [\(bar)] \(percent)%", terminator: "")
                    fflush(stdout)
                }
            } else {
                try bridge.exportToMov(outputUrl: outputURL) { progress in
                    let percent = Int(progress * 100)
                    let bar = String(repeating: "█", count: percent / 5) + String(repeating: "░", count: 20 - (percent / 5))
                    print("\r[\(Date())] 🔄 Exporting: [\(bar)] \(percent)%", terminator: "")
                    fflush(stdout)
                }
            }
            
            print("\n[\(Date())] 🎉 Done! Output saved to: \(outputPath)")
            
        } catch {
            print("\n[\(Date())] ❌ Error: \(error)")
        }
    }
}
