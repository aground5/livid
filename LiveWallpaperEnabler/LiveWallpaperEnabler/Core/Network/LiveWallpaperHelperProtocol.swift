import Foundation

@objc(LiveWallpaperHelperProtocol)
public protocol LiveWallpaperHelperProtocol {
    func fetchMetadata(url: URL, withReply reply: @escaping (String?, Error?) -> Void)
    func downloadVideo(url: URL, formatID: String?, outputDirectoryURL: URL, withReply reply: @escaping (URL?, Error?) -> Void)
    func checkHealth(withReply reply: @escaping (String) -> Void)
}

