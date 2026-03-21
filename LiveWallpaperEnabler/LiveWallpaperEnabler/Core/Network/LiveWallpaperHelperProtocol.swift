import Foundation

@objc(LiveWallpaperDownloadObserverProtocol)
public protocol LiveWallpaperDownloadObserverProtocol {
    func downloadDidUpdate(
        taskID: String,
        phase: String,
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64,
        speedBytesPerSecond: Double,
        etaSeconds: Double,
        detail: String
    )
}

@objc(LiveWallpaperHelperProtocol)
public protocol LiveWallpaperHelperProtocol {
    func fetchMetadata(url: URL, withReply reply: @escaping (String?, Error?) -> Void)
    func downloadVideo(
        taskID: String,
        url: URL,
        formatID: String?,
        outputDirectoryURL: URL,
        observer: LiveWallpaperDownloadObserverProtocol,
        withReply reply: @escaping (URL?, Error?) -> Void
    )
    func cancelDownload(taskID: String, withReply reply: @escaping (Bool) -> Void)
    func checkHealth(withReply reply: @escaping (String) -> Void)
}
