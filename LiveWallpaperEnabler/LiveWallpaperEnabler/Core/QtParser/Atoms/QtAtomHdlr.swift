import Foundation

class HdlrParser: AtomProtocol {
    var atomType: String = "hdlr"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    private let handlerSubtypes: [String: String] = [
        "vide": "Video",
        "soun": "Sound",
        "text": "Text",
        "sbtl": "Subtitle",
        "subt": "Subtitle",
        "meta": "Metadata",
        "tmcd": "Timecode",
        "hint": "Hint",
        "alis": "Alias Data",
        "url ": "URL Data"
    ]
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let type = reader.readFourCC()
        atom.addField(ParsedField(name: "component_type", offset: type.offset, size: type.size, value: type.value, raw: type.raw, description: "Handler Type"))
        
        let subtype = reader.readFourCC()
        let desc = handlerSubtypes[subtype.value] ?? "Unknown"
        atom.addField(ParsedField(name: "component_subtype", offset: subtype.offset, size: subtype.size, value: subtype.value, raw: subtype.raw, description: "Media Type: \(desc)"))
        
        let manu = reader.readFourCC()
        atom.addField(ParsedField(name: "component_manufacturer", offset: manu.offset, size: manu.size, value: manu.value, raw: manu.raw, description: "Manufacturer"))
        
        let flags = reader.readUInt32()
        atom.addField(ParsedField(name: "component_flags", offset: flags.offset, size: flags.size, value: flags.value, raw: flags.raw, description: "Component Flags"))
        
        let mask = reader.readUInt32()
        atom.addField(ParsedField(name: "component_flags_mask", offset: mask.offset, size: mask.size, value: mask.value, raw: mask.raw, description: "Flags Mask"))
        
        let remaining = atom.endOffset - reader.position
        if remaining > 0 {
            let nameData = reader.readBytes(remaining)
            let name = decodeName(data: nameData.raw)
            atom.addField(ParsedField(name: "component_name", offset: nameData.offset, size: remaining, value: name, raw: nameData.raw, description: "Handler Name"))
        }
    }
    
    private func decodeName(data: Data) -> String {
        guard !data.isEmpty else { return "" }
        
        // Try Pascal string (byte[0] == length)
        let len = Int(data[0])
        if len > 0 && len < data.count {
            if let s = String(data: data.subdata(in: 1..<(1+len)), encoding: .utf8) {
                return s
            }
        }
        
        // Try Null-terminated
        if let nullIndex = data.firstIndex(of: 0) {
            if let s = String(data: data.subdata(in: 0..<nullIndex), encoding: .utf8) {
                return s
            }
        }
        
        // Clean decode
        return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "") ?? ""
    }
}
