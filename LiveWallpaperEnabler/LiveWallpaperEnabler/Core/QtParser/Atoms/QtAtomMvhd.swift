import Foundation

class MvhdParser: AtomProtocol {
    var atomType: String = "mvhd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let versionField = atom.getField(name: "version")
        let version = (versionField?.value as? Int) ?? 0
        
        if version == 1 {
            // 64-bit duration/creation
            let creation = reader.readUInt64()
            atom.addField(ParsedField(name: "creation_time", offset: creation.offset, size: creation.size, value: creation.value, raw: creation.raw, description: "Creation calendar date and time (64-bit)"))
            
            let mod = reader.readUInt64()
            atom.addField(ParsedField(name: "modification_time", offset: mod.offset, size: mod.size, value: mod.value, raw: mod.raw, description: "Last modification date and time (64-bit)"))
            
            let ts = reader.readUInt32()
            atom.addField(ParsedField(name: "time_scale", offset: ts.offset, size: ts.size, value: ts.value, raw: ts.raw, description: "Time units per second"))
            
            let dur = reader.readUInt64()
            atom.addField(ParsedField(name: "duration", offset: dur.offset, size: dur.size, value: dur.value, raw: dur.raw, description: "Duration in time scale units (64-bit)"))
        } else {
            // 32-bit
            let creation = reader.readUInt32()
            atom.addField(ParsedField(name: "creation_time", offset: creation.offset, size: creation.size, value: creation.value, raw: creation.raw, description: "Creation date"))
            
            let mod = reader.readUInt32()
            atom.addField(ParsedField(name: "modification_time", offset: mod.offset, size: mod.size, value: mod.value, raw: mod.raw, description: "Modification date"))
            
            let ts = reader.readUInt32()
            atom.addField(ParsedField(name: "time_scale", offset: ts.offset, size: ts.size, value: ts.value, raw: ts.raw, description: "Time scale"))
            
            let dur = reader.readUInt32()
            atom.addField(ParsedField(name: "duration", offset: dur.offset, size: dur.size, value: dur.value, raw: dur.raw, description: "Duration"))
        }
        
        let rate = reader.readFixedPoint16_16()
        atom.addField(ParsedField(name: "preferred_rate", offset: rate.offset, size: rate.size, value: rate.value, raw: rate.raw, description: "Playback rate"))
        
        let vol = reader.readFixedPoint8_8()
        atom.addField(ParsedField(name: "preferred_volume", offset: vol.offset, size: vol.size, value: vol.value, raw: vol.raw, description: "Volume"))
        
        let reserved = reader.readBytes(10)
        atom.addField(ParsedField(name: "reserved", offset: reserved.offset, size: reserved.size, value: "<reserved>", raw: reserved.raw, description: "Reserved"))
        
        let matrix = reader.readMatrix()
        atom.addField(ParsedField(name: "matrix", offset: matrix.offset, size: matrix.size, value: matrix.value, raw: matrix.raw, description: "Transformation matrix"))
        
        let preTime = reader.readUInt32()
        atom.addField(ParsedField(name: "preview_time", offset: preTime.offset, size: preTime.size, value: preTime.value, raw: preTime.raw, description: "Preview time"))
        
        let preDur = reader.readUInt32()
        atom.addField(ParsedField(name: "preview_duration", offset: preDur.offset, size: preDur.size, value: preDur.value, raw: preDur.raw, description: "Preview duration"))
        
        let posterTime = reader.readUInt32()
        atom.addField(ParsedField(name: "poster_time", offset: posterTime.offset, size: posterTime.size, value: posterTime.value, raw: posterTime.raw, description: "Poster time"))
        
        let selTime = reader.readUInt32()
        atom.addField(ParsedField(name: "selection_time", offset: selTime.offset, size: selTime.size, value: selTime.value, raw: selTime.raw, description: "Selection time"))
        
        let selDur = reader.readUInt32()
        atom.addField(ParsedField(name: "selection_duration", offset: selDur.offset, size: selDur.size, value: selDur.value, raw: selDur.raw, description: "Selection duration"))
        
        let curTime = reader.readUInt32()
        atom.addField(ParsedField(name: "current_time", offset: curTime.offset, size: curTime.size, value: curTime.value, raw: curTime.raw, description: "Current time"))
        
        let nextTrack = reader.readUInt32()
        atom.addField(ParsedField(name: "next_track_id", offset: nextTrack.offset, size: nextTrack.size, value: nextTrack.value, raw: nextTrack.raw, description: "Next Track ID"))
    }
}
