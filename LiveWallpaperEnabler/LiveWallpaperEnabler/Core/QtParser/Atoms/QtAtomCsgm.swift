import Foundation

class CsgmParser: AtomProtocol {
    var atomType: String = "csgm"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let subType = reader.readFourCC()
        atom.addField(ParsedField(name: "sub_type", offset: subType.offset, size: subType.size, value: subType.value, raw: subType.raw, description: "Sub-Type"))
        
        for i in 1...6 {
            let fieldName = "custom_field_\(i)"
            let val = reader.readUInt32()
            atom.addField(ParsedField(name: fieldName, offset: val.offset, size: val.size, value: val.value, raw: val.raw, description: "Custom Field \(i)"))
        }
        
        let remaining = atom.endOffset - reader.position
        if remaining > 0 {
            let data = reader.readBytes(remaining)
            // Python uses hex string for value
            let hex = data.raw.map { String(format: "%02x", $0) }.joined()
            atom.addField(ParsedField(name: "custom_data", offset: data.offset, size: data.size, value: hex, raw: data.raw, description: "Custom Data"))
        }
    }
}
