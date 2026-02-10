import Foundation

class CttsParser: AtomProtocol {
    var atomType: String = "ctts"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        let versionField = atom.getField(name: "version")
        let version = (versionField?.value as? Int) ?? 0
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Entry Count"))
        
        var entries: [[String: Any]] = []
        let tableStart = reader.position
        
        for _ in 0..<numEntries.value {
            let count = reader.readUInt32()
            var offsetVal: Int
            
            if version == 1 {
                let off = reader.readInt32()
                offsetVal = Int(off.value)
            } else {
                let off = reader.readUInt32()
                // Version 0 treats as unsigned, but docs mention sometimes used as signed? 
                // Py impl: if > 0x7FFFFFFF, subtract 0x100000000. Essentially treating as signed 32-bit.
                if off.value > 0x7FFFFFFF {
                    offsetVal = Int(bitPattern: UInt(off.value)) - Int(bitPattern: 0x100000000)
                    // Wait, standard Swift Int(bitPattern: UInt32) -> Int32 then cast to Int
                    let i32 = Int32(bitPattern: off.value)
                    offsetVal = Int(i32)
                } else {
                    offsetVal = Int(off.value)
                }
            }
            
            entries.append([
                "sample_count": count.value,
                "composition_offset": offsetVal
            ])
        }
        
        let tableSize = reader.position - tableStart
        atom.addField(ParsedField(name: "entries", offset: tableStart, size: tableSize, value: entries, raw: Data(), description: "Composition Offset Table"))
    }
}

class StssParser: AtomProtocol {
    var atomType: String = "stss"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Keyframe Count"))
        
        var keyframes: [UInt32] = []
        let tableStart = reader.position
        
        for _ in 0..<numEntries.value {
            let sn = reader.readUInt32()
            keyframes.append(sn.value)
        }
        
        let tableSize = reader.position - tableStart
        atom.addField(ParsedField(name: "keyframes", offset: tableStart, size: tableSize, value: keyframes, raw: Data(), description: "Keyframe Sample Numbers"))
    }
}

class CslgParser: AtomProtocol {
    var atomType: String = "cslg"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let shift = reader.readInt32()
        atom.addField(ParsedField(name: "composition_offset_shift", offset: shift.offset, size: shift.size, value: shift.value, raw: shift.raw, description: "Composition Offset Shift"))
        
        let least = reader.readInt32()
        atom.addField(ParsedField(name: "least_display_offset", offset: least.offset, size: least.size, value: least.value, raw: least.raw, description: "Least Display Offset"))
        
        let greatest = reader.readInt32()
        atom.addField(ParsedField(name: "greatest_display_offset", offset: greatest.offset, size: greatest.size, value: greatest.value, raw: greatest.raw, description: "Greatest Display Offset"))
        
        let start = reader.readInt32()
        atom.addField(ParsedField(name: "display_start_time", offset: start.offset, size: start.size, value: start.value, raw: start.raw, description: "Display Start Time"))
        
        let end = reader.readInt32()
        atom.addField(ParsedField(name: "display_end_time", offset: end.offset, size: end.size, value: end.value, raw: end.raw, description: "Display End Time"))
    }
}

class SdtpParser: AtomProtocol {
    var atomType: String = "sdtp"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        // table size = atom size - header(8) - version/flags(4)
        // Or simply iterate until end of atom.
        // atom.size includes header.
        // ParsedAtom doesn't expose remaining bytes easily via size-math unless we trust it perfectly?
        // reader is at start of table now.
        // atom.endOffset is known.
        
        let remaining = atom.endOffset - reader.position
        let tableStart = reader.position
        
        if remaining > 0 {
            let data = reader.readBytes(remaining)
            // Storing bytes as [UInt8]
            var samples: [UInt8] = []
            samples.append(contentsOf: data.raw)
            
            atom.addField(ParsedField(name: "samples", offset: tableStart, size: remaining, value: samples, raw: Data(), description: "Sample Dependency Flags"))
        }
    }
}
