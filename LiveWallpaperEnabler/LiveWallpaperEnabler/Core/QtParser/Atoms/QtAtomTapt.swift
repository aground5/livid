import Foundation

class ApertureDimensionsParser: AtomProtocol {
    var atomType: String = ""
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    // Subclasses will set atomType
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let width = reader.readFixedPoint16_16()
        atom.addField(ParsedField(name: "width", offset: width.offset, size: width.size, value: width.value, raw: width.raw, description: "Width"))
        
        let height = reader.readFixedPoint16_16()
        atom.addField(ParsedField(name: "height", offset: height.offset, size: height.size, value: height.value, raw: height.raw, description: "Height"))
    }
}

class ClefParser: ApertureDimensionsParser {
    override init() {
        super.init()
        self.atomType = "clef"
    }
}

class ProfParser: ApertureDimensionsParser {
    override init() {
        super.init()
        self.atomType = "prof"
    }
}

class EnofParser: ApertureDimensionsParser {
    override init() {
        super.init()
        self.atomType = "enof"
    }
}
