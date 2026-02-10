import Foundation

class SbgpParser: AtomProtocol {
    var atomType: String = "sbgp"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let type = reader.readFourCC()
        atom.addField(ParsedField(name: "grouping_type", offset: type.offset, size: type.size, value: type.value, raw: type.raw, description: "Grouping Type"))
        
        let versionField = atom.getField(name: "version")
        let version = (versionField?.value as? Int) ?? 0
        
        if version >= 1 {
            let defLen = reader.readUInt32()
            atom.addField(ParsedField(name: "default_length", offset: defLen.offset, size: defLen.size, value: defLen.value, raw: defLen.raw, description: "Default Length"))
        }
        
        let count = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: count.offset, size: count.size, value: count.value, raw: count.raw, description: "Entry Count"))
        
        if count.value > 0 {
            let tableStart = reader.position
            var entries: [[String: Any]] = []
            
            for _ in 0..<count.value {
                let sCount = reader.readUInt32()
                let gIdx = reader.readUInt32()
                entries.append([
                    "sample_count": sCount.value,
                    "group_description_index": gIdx.value
                ])
            }
            
            let tableSize = reader.position - tableStart
            atom.addField(ParsedField(name: "entries", offset: tableStart, size: tableSize, value: entries, raw: Data(), description: "Sample-to-group Table"))
        }
    }
}

class SgpdParser: AtomProtocol {
    var atomType: String = "sgpd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let type = reader.readFourCC()
        atom.addField(ParsedField(name: "grouping_type", offset: type.offset, size: type.size, value: type.value, raw: type.raw, description: "Grouping Type"))
        
        let versionField = atom.getField(name: "version")
        let version = (versionField?.value as? Int) ?? 0
        
        var defaultLen: UInt32 = 0
        if version >= 1 {
            let dl = reader.readUInt32()
            defaultLen = dl.value
            atom.addField(ParsedField(name: "default_length", offset: dl.offset, size: dl.size, value: dl.value, raw: dl.raw, description: "Default Length"))
        }
        
        let count = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: count.offset, size: count.size, value: count.value, raw: count.raw, description: "Entry Count"))
        
        let payloadStart = reader.position
        let payloadSize = atom.endOffset - reader.position
        
        // This is a complex atom handling variable payloads.
        // Implementing basic logic matching python.
        var entries: Any = []
        
        if payloadSize > 0 {
            if type.value == "roll" && count.value > 0 {
                var rollEntries: [[String: Int16]] = []
                for _ in 0..<count.value {
                    let r = reader.readInt16()
                    rollEntries.append(["roll_distance": r.value])
                }
                entries = rollEntries
            } else if type.value == "tscl" && count.value > 0 {
                 // Simplified TSCL parsing
                 // If defaultLen is 0, read length.
                 var tsclEntries: [[String: Any]] = []
                 for _ in 0..<count.value {
                     var descLen = defaultLen
                     if defaultLen == 0 {
                         let l = reader.readUInt32()
                         descLen = l.value
                     }
                     // Skip reading detailed structure for now, just skip bytes to keep it robust and simple unless needed.
                     // Python code reads fields but mostly just to print.
                     // The critical part is correct pointer movement.
                     // If descLen >= 20: 5 uint32s.
                     // But if defaultLen was 0, we already read 4 bytes for length? 
                     // No, "description_length = reader.read_uint32()".
                     // The description length includes the length field itself? No, usually length is at start.
                     // Wait, in `sgpd.py`:
                     // if default_length_value == 0: description_length = reader.read_uint32().value
                     // This implies the 4 bytes are consumed.
                     // Then read payload of size `description_length`? 
                     // "if description_length >= 20" ...
                     // Actually reader.read_bytes(description_length - 20)
                     // So `description_length` is the *payload* size for this entry?
                     // Verify logic. "short_data = reader.read_bytes(description_length)" if < 20.
                     // So yes, it consumes `description_length` bytes from reader.
                     
                     // Determine bytes to read for this entry
                     var bytesToRead = 0
                     if defaultLen == 0 {
                          bytesToRead = Int(descLen)
                     } else {
                          bytesToRead = Int(defaultLen)
                     }
                     
                     // Safety check
                     if bytesToRead < 0 { bytesToRead = 0 }
                     
                     // Read payload
                     // We consume the bytes to advance the pointer. 
                     // Since we don't fully parse the structure into fields for TSCL yet, we skip.
                     let _ = reader.readBytes(bytesToRead)
                     
                     tsclEntries.append(["size": descLen])
                 }
                 entries = tsclEntries
            } else {
                // Fallback: read as raw data block
                let _ = reader.readBytes(payloadSize)
                entries = "<Raw Payload>"
            }
        }
        
        // Mark whole payload
        // The original parsed field logic puts all entries in one field.
        atom.addField(ParsedField(name: "entries", offset: payloadStart, size: payloadSize, value: entries, raw: Data(), description: "Payload Entries"))
    }
}

class StsdParser: AtomProtocol {
    var atomType: String = "stsd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let count = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: count.offset, size: count.size, value: count.value, raw: count.raw, description: "Entry Count"))
        
        var descriptions: [[String: Any]] = []
        
        for _ in 0..<count.value {
            // let start = reader.position
            let size = reader.readUInt32()
            if size.value < 16 { break } // Sanity check
            
            let format = reader.readFourCC()
            let _ = reader.readBytes(6) // Reserved
            let refIdx = reader.readUInt16()
            
            let headerSize = 16
            let remaining = Int(size.value) - headerSize
            
            var typeSpecificData = Data()
            if remaining > 0 {
                typeSpecificData = reader.readBytes(remaining).raw
            }
            
            descriptions.append([
                "size": size.value,
                "format": format.value,
                "data_ref_index": refIdx.value,
                "type_specific_size": remaining,
                "type_specific_data": typeSpecificData
            ])
        }
        
        // Calculate total size of descriptions
        // For convenience, simply use endOffset of last read
        // Or reader.position - (count.offset + count.size)
        // Let's use logic from python: explicitly summing or just taking the range.
        let tableStart = count.offset + count.size
        let tableSize = reader.position - tableStart
        
        atom.addField(ParsedField(name: "sample_descriptions", offset: tableStart, size: tableSize, value: descriptions, raw: Data(), description: "Sample Description Table"))
    }
}
