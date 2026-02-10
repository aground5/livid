import Foundation

class XPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        NSLog("🤝 [com.mitocondria.LiveWallpaperHelper] Incoming connection from PID: %d", newConnection.processIdentifier)
        
        newConnection.exportedInterface = NSXPCInterface(with: LiveWallpaperHelperProtocol.self)
        newConnection.exportedObject = LiveWallpaperHelperService()
        
        newConnection.interruptionHandler = {
            NSLog("⚠️ [com.mitocondria.LiveWallpaperHelper] Connection from PID %d interrupted", newConnection.processIdentifier)
        }
        newConnection.invalidationHandler = {
            NSLog("🛑 [com.mitocondria.LiveWallpaperHelper] Connection from PID %d invalidated", newConnection.processIdentifier)
        }
        
        newConnection.resume()
        NSLog("✅ [com.mitocondria.LiveWallpaperHelper] Connection accepted")
        return true
    }
}
