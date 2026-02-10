import Foundation

protocol AtomProtocol {
    var atomType: String { get }
    var isContainer: Bool { get }
    var isFullAtom: Bool { get }
    func parseData(reader: QtReader, atom: ParsedAtom)
}

// Default implementation helpers
extension AtomProtocol {
    func parseVersionFlags(reader: QtReader, atom: ParsedAtom) {
        let ver = reader.readUInt8()
        atom.version = Int(ver.value)
        atom.isFullAtom = true
        atom.addField(ParsedField(name: "version", offset: ver.offset, size: ver.size, value: ver.value, raw: ver.raw, description: "Atom version"))
        
        let flagsBytes = reader.readBytes(3)
        if flagsBytes.raw.count == 3 {
            let flagsVal = (Int(flagsBytes.raw[0]) << 16) | (Int(flagsBytes.raw[1]) << 8) | Int(flagsBytes.raw[2])
            atom.flags = flagsVal
            atom.addField(ParsedField(name: "flags", offset: flagsBytes.offset, size: flagsBytes.size, value: flagsVal, raw: flagsBytes.raw, description: "Atom flags"))
        }
    }
}

class GenericLeafParser: AtomProtocol {
    var atomType: String = "*"
    var isContainer: Bool = false
    var isFullAtom: Bool = false
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        let dataSize = atom.dataSize
        if dataSize > 0 {
            let data = reader.readBytes(dataSize)
            atom.addField(ParsedField(name: "raw_data", offset: data.offset, size: data.size, value: "<\(data.size) bytes>", raw: data.raw, description: "Unparsed atom data"))
        }
    }
}

class AtomRegistry {
    private var parsers: [String: AtomProtocol] = [:]
    private let defaultParser = GenericLeafParser()
    
    func register(_ parser: AtomProtocol) {
        parsers[parser.atomType] = parser
    }
    
    func getParser(for type: String) -> AtomProtocol {
        return parsers[type] ?? defaultParser
    }
    
    func isContainer(_ type: String) -> Bool {
        if let parser = parsers[type] {
            return parser.isContainer
        }
        return ["moov", "trak", "mdia", "minf", "stbl", "dinf", "edts", "udta", "meta", "ilst", "sinf", "schi", "mvex", "moof", "traf", "skip", "wide", "tapt"].contains(type)
    }
}

class QtParser {
    let registry: AtomRegistry
    var atoms: [ParsedAtom] = []
    
    init(registry: AtomRegistry? = nil) {
        self.registry = registry ?? createDefaultQtRegistry()
    }
    
    func parse(fileURL: URL) throws -> [ParsedAtom] {
        let data = try Data(contentsOf: fileURL)
        return parse(data: data)
    }
    
    func parse(data: Data) -> [ParsedAtom] {
        let reader = QtReader(data: data)
        self.atoms = parseAtoms(reader: reader, start: 0, end: data.count)
        return self.atoms
    }
    
    private func parseAtoms(reader: QtReader, start: Int, end: Int) -> [ParsedAtom] {
        var atoms: [ParsedAtom] = []
        reader.seek(start)
        
        while reader.position < end - 8 {
            if let atom = parseSingleAtom(reader: reader, containerEnd: end) {
                atoms.append(atom)
            } else {
                break
            }
        }
        return atoms
    }
    
    private func parseSingleAtom(reader: QtReader, containerEnd: Int) -> ParsedAtom? {
        let atomStart = reader.position
        if atomStart + 8 > containerEnd { return nil }
        
        let sizeRes = reader.readUInt32()
        var size = Int(sizeRes.value)
        
        let typeRes = reader.readFourCC()
        let atomType = typeRes.value
        
        var headerSize = 8
        var rawHeader = sizeRes.raw + typeRes.raw
        
        if size == 1 {
            let extSizeRes = reader.readUInt64()
            size = Int(extSizeRes.value)
            headerSize = 16
            rawHeader.append(extSizeRes.raw)
        } else if size == 0 {
            size = containerEnd - atomStart
        }
        
        if size < headerSize || atomStart + size > containerEnd {
            reader.seek(atomStart)
            return nil
        }
        
        let atom = ParsedAtom(fileOffset: atomStart, size: size, typeCode: atomType, headerSize: headerSize, rawHeader: rawHeader)
        
        let isContainer = registry.isContainer(atomType)
        let parser = registry.getParser(for: atomType)
        
        if isContainer {
            atom.isContainer = true
            var childStart = reader.position
            
            if parser.isFullAtom {
                parser.parseVersionFlags(reader: reader, atom: atom)
                childStart = reader.position
            }
            
            let children = parseAtoms(reader: reader, start: childStart, end: atom.endOffset)
            for child in children {
                atom.addChild(child)
            }
            
            reader.seek(atom.endOffset)
        } else {
            // Leaf
            parser.parseData(reader: reader, atom: atom)
            
            if reader.position != atom.endOffset {
                if reader.position < atom.endOffset {
                   let remaining = atom.endOffset - reader.position
                   let skip = reader.readBytes(remaining)
                   atom.addField(ParsedField(name: "_trailing_data", offset: skip.offset, size: skip.size, value: "<\(skip.size) trailing bytes>", raw: skip.raw, description: "Unparsed trailing data"))
                }
                reader.seek(atom.endOffset)
            }
        }
        
        return atom
    }
}
