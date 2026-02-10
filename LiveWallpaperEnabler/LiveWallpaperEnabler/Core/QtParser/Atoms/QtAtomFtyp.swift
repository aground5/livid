import Foundation

class FtypParser: AtomProtocol {
    var atomType: String = "ftyp"
    var isContainer: Bool = false
    var isFullAtom: Bool = false
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        // Major brand (4 bytes)
        let major = reader.readFourCC()
        atom.addField(ParsedField(
            name: "major_brand",
            offset: major.offset,
            size: major.size,
            value: major.value,
            raw: major.raw,
            description: "Primary file type identifier"
        ))
        
        // Minor version (4 bytes)
        let minor = reader.readUInt32()
        atom.addField(ParsedField(
            name: "minor_version",
            offset: minor.offset,
            size: minor.size,
            value: minor.value,
            raw: minor.raw,
            description: "File format specification version"
        ))
        
        // Compatible brands (4 bytes each, to end of atom)
        var brands: [String] = []
        let brandsStart = reader.position
        var brandsRaw = Data()
        
        while reader.position < atom.endOffset {
            let brand = reader.readFourCC()
            brands.append(brand.value)
            brandsRaw.append(brand.raw)
        }
        
        if !brands.isEmpty {
            atom.addField(ParsedField(
                name: "compatible_brands",
                offset: brandsStart,
                size: brands.count * 4,
                value: brands,
                raw: brandsRaw,
                description: "List of compatible file formats"
            ))
        }
    }
}
