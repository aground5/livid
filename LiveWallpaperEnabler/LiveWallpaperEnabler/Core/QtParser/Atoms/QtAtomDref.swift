import Foundation

class DrefParser: AtomProtocol {
    var atomType: String = "dref"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let numEntries = reader.readUInt32()
        atom.addField(ParsedField(name: "entry_count", offset: numEntries.offset, size: numEntries.size, value: numEntries.value, raw: numEntries.raw, description: "Entry Count"))
        
        var refs: [[String: Any]] = []
        let entriesStart = reader.position
        
        for _ in 0..<numEntries.value {
            // let refStart = reader.position
            let refSize = reader.readUInt32()
            let refType = reader.readFourCC()
            let refVersion = reader.readUInt8()
            let refFlagsBytes = reader.readBytes(3)
            let refFlags = (UInt32(refFlagsBytes.raw[0]) << 16) | (UInt32(refFlagsBytes.raw[1]) << 8) | UInt32(refFlagsBytes.raw[2])
            
            let dataSize = Int(refSize.value) - 12
            var refData: Data? = nil
            if dataSize > 0 {
                // Should check if we have enough bytes?
                // The QtReader handles bounds check mostly, crashing/erroring maybe.
                // Assuming well-formed for now.
                let rd = reader.readBytes(dataSize)
                refData = rd.raw
            }
            
            refs.append([
                "type": refType.value,
                "version": refVersion.value,
                "flags": refFlags,
                "self_contained": (refFlags & 0x0001) != 0,
                "data": refData ?? Data()
            ])
        }
        
        // This calculates total size of entries
        let entriesSize = reader.position - entriesStart
        atom.addField(ParsedField(name: "references", offset: entriesStart, size: entriesSize, value: refs, raw: Data(), description: "Data References"))
    }
}
