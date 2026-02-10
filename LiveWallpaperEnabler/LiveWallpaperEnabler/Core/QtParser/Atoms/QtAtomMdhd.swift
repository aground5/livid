import Foundation

class MdhdParser: AtomProtocol {
    var atomType: String = "mdhd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let versionField = atom.getField(name: "version")
        let version = (versionField?.value as? Int) ?? 0
        
        if version == 1 {
            let creation = reader.readUInt64()
            atom.addField(ParsedField(name: "creation_time", offset: creation.offset, size: creation.size, value: creation.value, raw: creation.raw, description: "Creation date and time (64-bit)"))
            
            let mod = reader.readUInt64()
            atom.addField(ParsedField(name: "modification_time", offset: mod.offset, size: mod.size, value: mod.value, raw: mod.raw, description: "Modification date and time (64-bit)"))
            
            let ts = reader.readUInt32()
            atom.addField(ParsedField(name: "time_scale", offset: ts.offset, size: ts.size, value: ts.value, raw: ts.raw, description: "Time Scale"))
            
            let dur = reader.readUInt64()
            atom.addField(ParsedField(name: "duration", offset: dur.offset, size: dur.size, value: dur.value, raw: dur.raw, description: "Duration (64-bit)"))
        } else {
            let creation = reader.readUInt32()
            atom.addField(ParsedField(name: "creation_time", offset: creation.offset, size: creation.size, value: creation.value, raw: creation.raw, description: "Creation date and time"))
            
            let mod = reader.readUInt32()
            atom.addField(ParsedField(name: "modification_time", offset: mod.offset, size: mod.size, value: mod.value, raw: mod.raw, description: "Modification date and time"))
            
            let ts = reader.readUInt32()
            atom.addField(ParsedField(name: "time_scale", offset: ts.offset, size: ts.size, value: ts.value, raw: ts.raw, description: "Time Scale"))
            
            let dur = reader.readUInt32()
            atom.addField(ParsedField(name: "duration", offset: dur.offset, size: dur.size, value: dur.value, raw: dur.raw, description: "Duration"))
        }
        
        let lang = reader.readUInt16()
        let langCode = decodeLanguage(packed: Int(lang.value))
        atom.addField(ParsedField(name: "language", offset: lang.offset, size: lang.size, value: ["raw": lang.value, "decoded": langCode], raw: lang.raw, description: "Language Code (ISO-639-2/T)"))
        
        let qual = reader.readUInt16()
        atom.addField(ParsedField(name: "quality", offset: qual.offset, size: qual.size, value: qual.value, raw: qual.raw, description: "Quality"))
    }
    
    private func decodeLanguage(packed: Int) -> String {
        guard packed != 0 else { return "und" }
        // 5 bits per char, + 0x60
        // packed = (c1 << 10) | (c2 << 5) | c3
        let c1 = ((packed >> 10) & 0x1F) + 0x60
        let c2 = ((packed >> 5) & 0x1F) + 0x60
        let c3 = (packed & 0x1F) + 0x60
        
        if let s1 = UnicodeScalar(c1), let s2 = UnicodeScalar(c2), let s3 = UnicodeScalar(c3) {
            return String(s1) + String(s2) + String(s3)
        }
        return String(format: "0x%04X", packed)
    }
}
