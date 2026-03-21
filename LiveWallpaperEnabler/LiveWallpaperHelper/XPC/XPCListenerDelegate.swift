import Foundation

class XPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        NSLog("🤝 [com.mitocondria.LiveWallpaperHelper] Incoming connection from PID: %d", newConnection.processIdentifier)
        
        let helperInterface = NSXPCInterface(with: LiveWallpaperHelperProtocol.self)
        helperInterface.setInterface(
            NSXPCInterface(with: LiveWallpaperDownloadObserverProtocol.self),
            for: #selector(LiveWallpaperHelperProtocol.downloadVideo(taskID:url:formatID:outputDirectoryURL:observer:withReply:)),
            argumentIndex: 4,
            ofReply: false
        )
        
        newConnection.exportedInterface = helperInterface
        newConnection.exportedObject = LiveWallpaperHelperService()
        newConnection.remoteObjectInterface = NSXPCInterface(with: LiveWallpaperDownloadObserverProtocol.self)
        
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
