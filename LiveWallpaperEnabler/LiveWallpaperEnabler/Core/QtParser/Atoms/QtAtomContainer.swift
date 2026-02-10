import Foundation

class ContainerParser: AtomProtocol {
    var atomType: String = "container"
    var isContainer: Bool = true
    var isFullAtom: Bool = false
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        // Container atoms don't have their own data, children are parsed by the loop
        atom.isContainer = true
    }
}

class MetaParser: AtomProtocol {
    var atomType: String = "meta"
    var isContainer: Bool = true
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        atom.isContainer = true
    }
}
