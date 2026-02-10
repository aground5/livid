import Foundation

class SttsParser: AtomProtocol {
    var atomType: String = "stts"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Entry Count"))
        
        var entries: [[String: Any]] = []
        let tableStart = reader.position
        
        for _ in 0..<numEntries.value {
            let count = reader.readUInt32()
            let duration = reader.readUInt32()
            entries.append([
                "sample_count": count.value,
                "sample_duration": duration.value
            ])
        }
        
        let tableSize = reader.position - tableStart
        atom.addField(ParsedField(name: "entries", offset: tableStart, size: tableSize, value: entries, raw: Data(), description: "Time-to-Sample Table"))
    }
}

class StscParser: AtomProtocol {
    var atomType: String = "stsc"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Entry Count"))
        
        var entries: [[String: Any]] = []
        let tableStart = reader.position
        
        for _ in 0..<numEntries.value {
            let first = reader.readUInt32()
            let count = reader.readUInt32()
            let id = reader.readUInt32()
            entries.append([
                "first_chunk": first.value,
                "samples_per_chunk": count.value,
                "sample_description_id": id.value
            ])
        }
        
        let tableSize = reader.position - tableStart
        atom.addField(ParsedField(name: "entries", offset: tableStart, size: tableSize, value: entries, raw: Data(), description: "Sample-to-Chunk Table"))
    }
}

class StszParser: AtomProtocol {
    var atomType: String = "stsz"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let sampleSize = reader.readUInt32()
        atom.addField(ParsedField(name: "sample_size", offset: sampleSize.offset, size: sampleSize.size, value: sampleSize.value, raw: sampleSize.raw, description: "Default Sample Size"))
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Sample Count"))
        
        if sampleSize.value == 0 && numEntries.value > 0 {
            let tableStart = reader.position
            var sizes: [UInt32] = []
            // Optimization: if extremely large, maybe don't store individual Int objects in array just for parsing?
            // But ParsedField expects 'value'.
            // For now, match python implementation.
            for _ in 0..<numEntries.value {
                let sz = reader.readUInt32()
                sizes.append(sz.value)
            }
            
            let tableSize = reader.position - tableStart
            atom.addField(ParsedField(name: "sample_sizes", offset: tableStart, size: tableSize, value: sizes, raw: Data(), description: "Sample Size Table"))
        }
    }
}

class StcoParser: AtomProtocol {
    var atomType: String = "stco"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Entry Count"))
        
        var offsets: [UInt32] = []
        let tableStart = reader.position
        
        for _ in 0..<numEntries.value {
            let off = reader.readUInt32()
            offsets.append(off.value)
        }
        
        let tableSize = reader.position - tableStart
        atom.addField(ParsedField(name: "chunk_offsets", offset: tableStart, size: tableSize, value: offsets, raw: Data(), description: "Chunk Offset Table"))
    }
}
