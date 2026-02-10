import Foundation

class TkhdParser: AtomProtocol {
    var atomType: String = "tkhd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    // Flags
    static let TRACK_ENABLED = 0x0001
    static let TRACK_IN_MOVIE = 0x0002
    static let TRACK_IN_PREVIEW = 0x0004
    static let TRACK_IN_POSTER = 0x0008
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let versionField = atom.getField(name: "version")
        let version = (versionField?.value as? Int) ?? 0
        
        if version == 1 {
            let creation = reader.readUInt64()
            atom.addField(ParsedField(name: "creation_time", offset: creation.offset, size: creation.size, value: creation.value, raw: creation.raw, description: "Creation date and time"))
            
            let mod = reader.readUInt64()
            atom.addField(ParsedField(name: "modification_time", offset: mod.offset, size: mod.size, value: mod.value, raw: mod.raw, description: "Modification date and time"))
            
            let trackId = reader.readUInt32()
            atom.addField(ParsedField(name: "track_id", offset: trackId.offset, size: trackId.size, value: trackId.value, raw: trackId.raw, description: "Track ID"))
            
            let res1 = reader.readUInt32()
            atom.addField(ParsedField(name: "reserved_1", offset: res1.offset, size: res1.size, value: "<reserved>", raw: res1.raw, description: "Reserved"))
            
            let dur = reader.readUInt64()
            atom.addField(ParsedField(name: "duration", offset: dur.offset, size: dur.size, value: dur.value, raw: dur.raw, description: "Duration"))
        } else {
            let creation = reader.readUInt32()
            atom.addField(ParsedField(name: "creation_time", offset: creation.offset, size: creation.size, value: creation.value, raw: creation.raw, description: "Creation date and time"))
            
            let mod = reader.readUInt32()
            atom.addField(ParsedField(name: "modification_time", offset: mod.offset, size: mod.size, value: mod.value, raw: mod.raw, description: "Modification date and time"))
            
            let trackId = reader.readUInt32()
            atom.addField(ParsedField(name: "track_id", offset: trackId.offset, size: trackId.size, value: trackId.value, raw: trackId.raw, description: "Track ID"))
            
            let res1 = reader.readUInt32()
            atom.addField(ParsedField(name: "reserved_1", offset: res1.offset, size: res1.size, value: "<reserved>", raw: res1.raw, description: "Reserved"))
            
            let dur = reader.readUInt32()
            atom.addField(ParsedField(name: "duration", offset: dur.offset, size: dur.size, value: dur.value, raw: dur.raw, description: "Duration"))
        }
        
        // Reserved matches between v0 and v1 here? Actually spec says for V1:
        // reserved is 4 bytes, then duration 8 bytes.
        // for V0: reserved 4 bytes, duration 4 bytes.
        
        // Following are same for both
        let res2 = reader.readBytes(8)
        atom.addField(ParsedField(name: "reserved_2", offset: res2.offset, size: res2.size, value: "<reserved>", raw: res2.raw, description: "Reserved"))
        
        let layer = reader.readInt16()
        atom.addField(ParsedField(name: "layer", offset: layer.offset, size: layer.size, value: layer.value, raw: layer.raw, description: "Layer"))
        
        let alt = reader.readInt16()
        atom.addField(ParsedField(name: "alternate_group", offset: alt.offset, size: alt.size, value: alt.value, raw: alt.raw, description: "Alternate Group"))
        
        let vol = reader.readFixedPoint8_8()
        atom.addField(ParsedField(name: "volume", offset: vol.offset, size: vol.size, value: vol.value, raw: vol.raw, description: "Volume"))
        
        let res3 = reader.readBytes(2)
        atom.addField(ParsedField(name: "reserved_3", offset: res3.offset, size: res3.size, value: "<reserved>", raw: res3.raw, description: "Reserved"))
        
        let matrix = reader.readMatrix()
        atom.addField(ParsedField(name: "matrix", offset: matrix.offset, size: matrix.size, value: matrix.value, raw: matrix.raw, description: "Transformation Matrix"))
        
        let width = reader.readFixedPoint16_16()
        atom.addField(ParsedField(name: "track_width", offset: width.offset, size: width.size, value: width.value, raw: width.raw, description: "Track Width"))
        
        let height = reader.readFixedPoint16_16()
        atom.addField(ParsedField(name: "track_height", offset: height.offset, size: height.size, value: height.value, raw: height.raw, description: "Track Height"))
    }
}
