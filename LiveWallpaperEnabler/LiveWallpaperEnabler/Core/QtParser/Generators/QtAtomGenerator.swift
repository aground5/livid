import Foundation

class QtAtomGenerator {
    
    // MARK: - Dimensions (tapt)
    
    /// Create tapt atom with clef, prof, enof children
    static func createTaptAtom(width: Double, height: Double) -> Data {
        let clef = writeDimAtom(tag: "clef", width: width, height: height)
        let prof = writeDimAtom(tag: "prof", width: width, height: height)
        let enof = writeDimAtom(tag: "enof", width: width, height: height)
        
        var body = Data()
        body.append(clef)
        body.append(prof)
        body.append(enof)
        
        let writer = QtWriter()
        writer.writeUInt32(UInt32(8 + body.count))
        writer.writeFourCC("tapt")
        writer.writeBytes(body)
        
        return writer.getBytes()
    }
    
    private static func writeDimAtom(tag: String, width: Double, height: Double) -> Data {
        let writer = QtWriter()
        // Header placeholder
        writer.writeUInt32(0)
        writer.writeFourCC(tag)
        
        // Version(0) + Flags(0)
        writer.writeUInt32(0)
        
        // Width (16.16), Height (16.16)
        writer.writeFixedPoint1616(width)
        writer.writeFixedPoint1616(height)
        
        // Update size
        var data = writer.getBytes()
        let size = UInt32(data.count)
        
        // Patch size at index 0 (Big Endian)
        let sizeBytes = withUnsafeBytes(of: size.bigEndian) { Data($0) }
        data.replaceSubrange(0..<4, with: sizeBytes)
        
        return data
    }
    
    // MARK: - Sample Group Descriptions (sgpd)
    
    /// Create sgpd (tscl) and sgpd (tsas) atoms.
    static func createSgpdAtoms(maxTemporalId: Int, baseDuration: UInt32 = 1000) -> [Data] {
        // 1. TSCL (Temporal Level)
        let tsclData = createSingleSgpd(groupingType: "tscl", entryCount: 5) { payloadWriter in
            payloadWriter.writeUInt32(0)              // Field 1: 0
            payloadWriter.writeUInt32(baseDuration)   // Field 2: Duration
            payloadWriter.writeUInt32(1)              // Field 3: 1
            payloadWriter.writeUInt32(0)              // Field 4: 0
            payloadWriter.writeUInt32(128)            // Field 5: 128 (0x80)
        }
        
        // 2. TSAS (Action State) - Entry Count 1, Payload 0
        let tsasData = createSingleSgpd(groupingType: "tsas", entryCount: 1, defaultLength: 4) { payloadWriter in
             payloadWriter.writeUInt32(0)
        }
        
        return [tsclData, tsasData]
    }
    
    private static func createSingleSgpd(groupingType: String, entryCount: Int, defaultLength: UInt32 = 20, payloadGenerator: (QtWriter) -> Void) -> Data {
        let writer = QtWriter()
        writer.writeUInt32(0) // Placeholder
        writer.writeFourCC("sgpd")
        writer.writeUInt32(0x01000000) // Ver 1, Flags 0
        writer.writeFourCC(groupingType)
        writer.writeUInt32(defaultLength)
        writer.writeUInt32(UInt32(entryCount))
        
        let payloadWriter = QtWriter()
        payloadGenerator(payloadWriter)
        let payload = payloadWriter.getBytes()
        
        // Repeat payload for each entry
        // NOTE: The python logic for TSCL repeats the SAME payload for all entries.
        // For TSAS, it writes it once (since entry count is 1).
        
        for _ in 0..<entryCount {
            writer.writeBytes(payload)
        }
        
        var data = writer.getBytes()
        let size = UInt32(data.count)
        let sizeBytes = withUnsafeBytes(of: size.bigEndian) { Data($0) }
        data.replaceSubrange(0..<4, with: sizeBytes)
        
        return data
    }
    
    // MARK: - Custom Segment Map (csgm)
    
    static func createCsgmAtoms(temporalIds: [Int]) -> [Data] {
        let payloadBytes = QtNALUnitParser.generateCsgmPayload(temporalIds: temporalIds)
        let sampleCount = temporalIds.count
        
        let csgmTscl = writeCsgm(gtype: "tscl", payload: payloadBytes, sampleCount: sampleCount)
        let csgmTsas = writeCsgm(gtype: "tsas", payload: payloadBytes, sampleCount: sampleCount)
        
        return [csgmTscl, csgmTsas]
    }
    
    private static func writeCsgm(gtype: String, payload: Data, sampleCount: Int) -> Data {
        let writer = QtWriter()
        writer.writeUInt32(0) // Placeholder
        writer.writeFourCC("csgm")
        writer.writeUInt32(0) // Ver 0 Flags 0
        writer.writeFourCC(gtype)
        
        // Custom fields: 0, 4, 2, 1, 1, 16
        for v: UInt32 in [0, 4, 2, 1, 1, 16] {
            writer.writeUInt32(v)
        }
        
        // Sample count - 1
        writer.writeUInt32(UInt32(max(0, sampleCount - 1)))
        
        writer.writeBytes(payload)
        
        var data = writer.getBytes()
        let size = UInt32(data.count)
        let sizeBytes = withUnsafeBytes(of: size.bigEndian) { Data($0) }
        data.replaceSubrange(0..<4, with: sizeBytes)
        
        return data
    }
    
    // MARK: - Composition Shift (cslg)
    
    static func createCslgAtom(cttsEntries: [[String: Any]]) -> Data {
         if cttsEntries.isEmpty {
             return Data()
         }
        
        var maxOffset: Int = 0
        let offsets = cttsEntries.compactMap { $0["composition_offset"] as? Int }
        if !offsets.isEmpty {
            maxOffset = offsets.max() ?? 0
        }
        
        // Min offset is 0 for v0 ctts (unsigned).
        
        let writer = QtWriter()
        writer.writeUInt32(0)
        writer.writeFourCC("cslg")
        writer.writeUInt32(0) // Ver 0 Flags 0
        
        writer.writeUInt32(0) // composition_offset_shift
        writer.writeUInt32(0) // least_display_offset
        writer.writeUInt32(UInt32(maxOffset)) // greatest_display_offset
        writer.writeUInt32(0) // display_start_time
        writer.writeUInt32(0) // display_end_time
        
        var data = writer.getBytes()
        let size = UInt32(data.count)
        let sizeBytes = withUnsafeBytes(of: size.bigEndian) { Data($0) }
        data.replaceSubrange(0..<4, with: sizeBytes)
        
        return data
    }
}
