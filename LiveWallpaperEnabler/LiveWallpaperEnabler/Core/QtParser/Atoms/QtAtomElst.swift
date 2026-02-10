import Foundation

class ElstParser: AtomProtocol {
    var atomType: String = "elst"
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
            var duration: Any
            var mediaTime: Any
            
            if version == 1 {
                let d = reader.readUInt64()
                let m = reader.readInt64()
                duration = d.value
                mediaTime = m.value
            } else {
                let d = reader.readUInt32()
                let m = reader.readInt32()
                duration = d.value
                mediaTime = m.value
            }
            
            let rate = reader.readFixedPoint16_16()
            
            entries.append([
                "track_duration": duration,
                "media_time": mediaTime,
                "media_rate": rate.value
            ])
        }
        
        let entriesSize = reader.position - tableStart
        atom.addField(ParsedField(name: "entries", offset: tableStart, size: entriesSize, value: entries, raw: Data(), description: "Edit List Entries"))
    }
}
