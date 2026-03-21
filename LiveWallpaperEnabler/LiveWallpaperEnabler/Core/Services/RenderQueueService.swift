import Foundation
import AppKit
import Observation
import os

@MainActor
@Observable
class RenderQueueService {
    static let shared = RenderQueueService()
    
    // The Queue
    private(set) var jobs: [RenderJob] = []
    
    // Internal State
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?
    private let exporter = LiveWallpaperExporter()
    
    private init() {}
    
    // MARK: - Public API
    
    func addToQueue(config: LiveWallpaperExportConfiguration, originalFilename: String, thumbnail: NSImage?) {
        let job = RenderJob(
            id: UUID(),
            config: config,
            createdAt: Date(),
            originalFilename: originalFilename,
            thumbnail: thumbnail,
            status: .pending
        )
        
        // Add to list
        jobs.append(job)
        Logger.video.info("Job added to queue: \(originalFilename)")
        
        // Trigger processing loop if idle
        processQueue()
    }
    
    func cancel(_ jobID: UUID) {
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index].status = .cancelled
            
            // If this is the current job, cancel the task
            // The exporter/converter will detect Task.isCancelled and stop the FFmpeg loop
            if let current = currentTask, !current.isCancelled {
                current.cancel()
                currentTask = nil
            }
            
            Logger.video.info("Job cancelled: \(self.jobs[index].originalFilename)")
        }
    }
    
    func clearCompleted() {
        jobs.removeAll { $0.status == .completed || $0.status == .cancelled }
    }

    // MARK: - Queue Processing Logic
    
    private func processQueue() {
        guard !isProcessing else { return }
        
        currentTask = Task(priority: .userInitiated) { 
            await self.runExecutionLoop()
        }
    }
    
    private func runExecutionLoop() async {
        isProcessing = true
        defer { isProcessing = false }
        
        while let nextIndex = jobs.firstIndex(where: { $0.status == .pending }) {
            // 1. Prepare Job
            var job = jobs[nextIndex]
            job.status = .rendering
            jobs[nextIndex] = job
            
            Logger.video.info("Starting job: \(job.originalFilename)")
            
            // 2. Metrics Tracking
            let startTime = Date()
            let sourceFps = 30.0 // ideally passed from config, but good estimate for calc
            let totalDuration = job.config.endTime - job.config.startTime
            let totalFrames = Int(totalDuration * sourceFps)
            
            // 3. Execute
            do {
                try await exporter.export(config: job.config) { [weak self] progress in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // Update Job State Live
                        if let currentIndex = self.jobs.firstIndex(where: { $0.id == job.id }) {
                            var updatingJob = self.jobs[currentIndex]
                            updatingJob.progress = progress
                            
                            // Calc Metrics
                            let elapsed = Date().timeIntervalSince(startTime)
                            if elapsed > 0.5 {
                                let currentFrame = Double(totalFrames) * progress
                                let currentFps = currentFrame / elapsed
                                updatingJob.fps = currentFps
                                updatingJob.speed = currentFps / sourceFps
                                if progress > 0.01 {
                                    updatingJob.timeRemaining = (elapsed / progress) - elapsed
                                }
                            }
                            
                            self.jobs[currentIndex] = updatingJob
                        }
                    }
                }
                
                // 4. Success
                if let finishIndex = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[finishIndex].status = .completed
                    jobs[finishIndex].progress = 1.0
                    
                    // Register to Wallpaper Store
                    let config = jobs[finishIndex].config
                    WallpaperStore.shared.add(
                        fileURL: config.outputURL,
                        originalName: jobs[finishIndex].originalFilename,
                        duration: config.endTime - config.startTime
                    )
                }
                
            } catch {
                // 5. Failure
                Logger.video.error("Job failed: \(error.localizedDescription)")
                if let failIndex = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[failIndex].status = .failed(error.localizedDescription)
                }
            }
            
            // Double check if Task was cancelled between jobs
            if Task.isCancelled {
                break
            }
        }
        currentTask = nil
    }
}
