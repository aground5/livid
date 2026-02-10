import Foundation

class DenoTask {
    private let scriptName: String
    private let arguments: [String]
    private let binaryURL: URL
    
    init(scriptName: String, arguments: [String], binaryURL: URL) {
        self.scriptName = scriptName
        self.arguments = arguments
        self.binaryURL = binaryURL
    }
    
    private func getScriptPath() throws -> String {
        // Search for the script in the bundle resources
        // For CLI/Test apps, we might need to look in relative paths
        if let bundlePath = Bundle.main.path(forResource: scriptName, ofType: "ts", inDirectory: "Scripts") {
            return bundlePath
        }
        
        // Fallback for non-bundled environments (e.g. testing via swiftc)
        let currentDirectory = FileManager.default.currentDirectoryPath
        let relativePath = "Resources/Scripts/\(scriptName).ts"
        let fullPath = (currentDirectory as NSString).appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: fullPath) {
            return fullPath
        }
        
        throw NSError(domain: "DenoTask", code: 404, userInfo: [NSLocalizedDescriptionKey: "Script '\(scriptName).ts' not found in bundle or relative path"])
    }
    
    func run() throws -> String {
        let scriptPath = try getScriptPath()
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = binaryURL
        
        // Deno run arguments: allow-net, allow-write are essential
        var processArgs = ["run", "--allow-net", "--allow-write", "--allow-read", "--allow-env"]
        
        // Add the script path
        processArgs.append(scriptPath)
        
        // Add user arguments (URL, output path, etc.)
        processArgs.append(contentsOf: arguments)
        
        process.arguments = processArgs
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        // Pass environment variables, especially HOME and PATH
        process.environment = ProcessInfo.processInfo.environment
        
        print("   [Deno] Executing: \(binaryURL.path) \(processArgs.joined(separator: " "))")
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            print("   [Deno] Error Output: \(errorOutput)")
            throw NSError(domain: "DenoTask", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Deno failed with status \(process.terminationStatus): \(errorOutput)"
            ])
        }
        
        return output
    }
}
