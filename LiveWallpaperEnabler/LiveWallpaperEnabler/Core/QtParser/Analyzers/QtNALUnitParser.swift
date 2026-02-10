import Foundation

class QtNALUnitParser {
    
    /// Extract temporal IDs from HEVC NAL units in the media data.
    /// - Parameters:
    ///   - stszSizes: Array of sample sizes.
    ///   - chunkOffsets: Array of chunk offsets.
    ///   - stscEntries: Array of Sample-to-Chunk entries.
    ///   - reader: QtReader instance providing access to the media data.
    /// - Returns: Array of temporal IDs (0-based, or -1 if invalid).
    static func extractTemporalIDs(stszSizes: [Int], chunkOffsets: [Int], stscEntries: [[String: Any]], reader: QtReader) -> [Int] {
        // 1. Expand Chunks to Samples mapping
        var chunkSampleCounts: [Int] = []
        
        if stscEntries.isEmpty {
            return []
        }
        
        let totalChunks = chunkOffsets.count
        
        for i in 0..<stscEntries.count {
            let entry = stscEntries[i]
            guard let firstChunk = entry["first_chunk"] as? Int,
                  let samplesPerChunk = entry["samples_per_chunk"] as? Int else {
                continue
            }
            
            // Standard says STSC covers range from first_chunk to next entry's first_chunk
            let startChunk = firstChunk
            let endChunk: Int
            if i < stscEntries.count - 1 {
                let nextEntry = stscEntries[i+1]
                if let nextFirst = nextEntry["first_chunk"] as? Int {
                    endChunk = nextFirst
                } else {
                    endChunk = totalChunks + 1
                }
            } else {
                endChunk = totalChunks + 1
            }
            
            let length = max(0, endChunk - startChunk)
            chunkSampleCounts.append(contentsOf: Array(repeating: samplesPerChunk, count: length))
        }
        
        // Truncate if needed to match actual chunk count
        if chunkSampleCounts.count > totalChunks {
            chunkSampleCounts = Array(chunkSampleCounts.prefix(totalChunks))
        }
        
        // 2. Iterate Samples
        var temporalIds: [Int] = []
        var sampleIdx = 0
        
        for (i, chunkOffset) in chunkOffsets.enumerated() {
            if i >= chunkSampleCounts.count { break }
            let numSamples = chunkSampleCounts[i]
            
            var currentPos = chunkOffset
            
            for _ in 0..<numSamples {
                if sampleIdx >= stszSizes.count { break }
                let size = stszSizes[sampleIdx]
                
                // Read NAL (Assuming 4-byte length prefix usually in MOV)
                
                let _ = reader.position // Keep if needed, but we seek anyway
                reader.seek(currentPos)
                
                // Read 6 bytes: 4 len + 2 header
                if reader.remaining >= 6 {
                    let res = reader.readBytes(6)
                    let blob = res.value
                    if blob.count >= 6 {
                        // HEVC NAL Header parsing
                        // Byte 4 is F(1) Type(6) LayerIdHigh(1)
                        // Byte 5 is LayerIdLow(5) Tid(3)
                        let b5 = blob[5] // 0-indexed
                        
                        let tidPlus1 = b5 & 0x07
                        if tidPlus1 > 0 {
                            temporalIds.append(Int(tidPlus1) - 1)
                        } else {
                            temporalIds.append(-1)
                        }
                    } else {
                         temporalIds.append(-1)
                    }
                } else {
                    temporalIds.append(-1)
                }
                
                currentPos += size
                sampleIdx += 1
            }
            // For next chunk, loop continues with next chunkOffset
        }
        
        return temporalIds
    }
    
    /// Compress Temporal IDs into Nibble-Packed CSGM Payload.
    static func generateCsgmPayload(temporalIds: [Int]) -> Data {
        if temporalIds.isEmpty { return Data() }
        
        // 1. Detect Pattern
        // Find indices of ID 0
        let baseIndices = temporalIds.enumerated().compactMap { $0.element == 0 ? $0.offset : nil }
        
        var pattern: [Int] = []
        
        if baseIndices.count >= 2 {
            let interval = baseIndices[1] - baseIndices[0]
            
            if interval > 0 && (baseIndices[0] + interval) <= temporalIds.count {
                let candidatePattern = Array(temporalIds[baseIndices[0]..<(baseIndices[0] + interval)])
                
                var isConsistent = true
                let checkLimit = min(temporalIds.count, baseIndices[0] + interval * 5)
                
                // Swift stride
                for i in stride(from: baseIndices[0], to: checkLimit, by: interval) {
                    let chunkLen = min(interval, temporalIds.count - i)
                    let chunk = Array(temporalIds[i..<(i + chunkLen)])
                    if chunk != Array(candidatePattern.prefix(chunkLen)) {
                        isConsistent = false
                        break
                    }
                }
                
                if isConsistent {
                    pattern = candidatePattern
                } else {
                    pattern = temporalIds
                }
            } else {
                pattern = temporalIds
            }
        } else {
            pattern = temporalIds
        }
        
        print("Detected Temporal Pattern Length: \(pattern.count)")
        // print("Pattern: \(pattern.prefix(20))...")
        
        // 2. Pack into Nibbles
        // Each byte = (HighNibble, LowNibble)
        // Nibble = ID + 1
        
        var packed = Data()
        
        for i in stride(from: 0, to: pattern.count, by: 2) {
            let v1 = pattern[i] + 1
            
            var v2 = 0
            if i + 1 < pattern.count {
                v2 = pattern[i+1] + 1
            }
            
            // Bounds check (4-bit max 15)
            let n1 = UInt8(min(v1, 15))
            let n2 = UInt8(min(v2, 15))
            
            let byteVal = (n1 << 4) | n2
            packed.append(byteVal)
        }
        
        return packed
    }
}
