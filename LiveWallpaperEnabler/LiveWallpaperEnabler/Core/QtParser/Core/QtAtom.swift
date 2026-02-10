import Foundation

struct ParsedField {
    let name: String
    let offset: Int
    let size: Int
    let value: Any
    let raw: Data
    let description: String
    
    init(name: String, offset: Int, size: Int, value: Any, raw: Data, description: String = "") {
        self.name = name
        self.offset = offset
        self.size = size
        self.value = value
        self.raw = raw
        self.description = description
    }
    
    // Helper to get dictionary representation
    func toDictionary(slim: Bool = false) -> [String: Any] {
        var val = value
        if let dataVal = val as? Data {
            if slim && dataVal.count > 32 {
                val = "<\(dataVal.count) bytes>"
            } else {
                val = dataVal.map { String(format: "%02x", $0) }.joined()
            }
        }
        // Handle list logic if needed
        
        var dict: [String: Any] = [
            "name": name,
            "offset": offset,
            "offset_hex": String(format: "0x%08X", offset),
            "size": size,
            "value": val,
            "description": description
        ]
        
        if !slim {
            if raw.count > 32 {
                dict["raw_hex"] = raw.prefix(32).map { String(format: "%02x", $0) }.joined() + "..."
            } else {
                dict["raw_hex"] = raw.map { String(format: "%02x", $0) }.joined()
            }
        }
        return dict
    }
}

class ParsedAtom {
    let fileOffset: Int
    let size: Int
    let typeCode: String
    let headerSize: Int
    let rawHeader: Data
    
    var children: [ParsedAtom] = []
    var fields: [ParsedField] = []
    var rawData: Data = Data()
    
    var unparsedRanges: [(Int, Int)] = []
    
    var isContainer: Bool = false
    var isFullAtom: Bool = false
    var version: Int?
    var flags: Int?
    
    init(fileOffset: Int, size: Int, typeCode: String, headerSize: Int, rawHeader: Data) {
        self.fileOffset = fileOffset
        self.size = size
        self.typeCode = typeCode
        self.headerSize = headerSize
        self.rawHeader = rawHeader
    }
    
    var dataOffset: Int {
        return fileOffset + headerSize
    }
    
    var dataSize: Int {
        return size - headerSize
    }
    
    var endOffset: Int {
        return fileOffset + size
    }
    
    func addField(_ field: ParsedField) {
        self.fields.append(field)
    }
    
    func addChild(_ child: ParsedAtom) {
        self.children.append(child)
        self.isContainer = true
    }
    
    func getField(name: String) -> ParsedField? {
        return fields.first { $0.name == name }
    }
    
    func getFieldValue(name: String) -> Any? {
        return getField(name: name)?.value
    }
    
    func find(typeCode: String) -> ParsedAtom? {
        if self.typeCode == typeCode {
            return self
        }
        for child in children {
            if let found = child.find(typeCode: typeCode) {
                return found
            }
        }
        return nil
    }
    
    func findAll(typeCode: String) -> [ParsedAtom] {
        var results: [ParsedAtom] = []
        if self.typeCode == typeCode {
            results.append(self)
        }
        for child in children {
            results.append(contentsOf: child.findAll(typeCode: typeCode))
        }
        return results
    }
    
    func calculateUnparsed() -> [(Int, Int)] {
        var ranges: [(Int, Int)] = []
        
        if isContainer {
            var parsedRanges = [(fileOffset, fileOffset + headerSize)]
            for child in children.sorted(by: { $0.fileOffset < $1.fileOffset }) {
                parsedRanges.append((child.fileOffset, child.endOffset))
            }
            
            let sortedRanges = parsedRanges.sorted(by: { $0.0 < $1.0 })
            for i in 0..<sortedRanges.count - 1 {
                let endCurrent = sortedRanges[i].1
                let startNext = sortedRanges[i+1].0
                if endCurrent < startNext {
                    ranges.append((endCurrent, startNext))
                }
            }
            
            if let lastEnd = sortedRanges.last?.1, lastEnd < endOffset {
                ranges.append((lastEnd, endOffset))
            }
        } else {
             var parsedRanges = [(fileOffset, fileOffset + headerSize)]
             for field in fields {
                 parsedRanges.append((field.offset, field.offset + field.size))
             }
             
             let sortedRanges = parsedRanges.sorted(by: { $0.0 < $1.0 })
             for i in 0..<sortedRanges.count - 1 {
                 let endCurrent = sortedRanges[i].1
                 let startNext = sortedRanges[i+1].0
                 if endCurrent < startNext {
                     ranges.append((endCurrent, startNext))
                 }
             }
             
             if let lastEnd = sortedRanges.last?.1, lastEnd < endOffset {
                 ranges.append((lastEnd, endOffset))
             }
        }
        
        self.unparsedRanges = ranges
        return ranges
    }
    
    func toDictionary(includeRaw: Bool = false, includeUnparsed: Bool = true, slim: Bool = false) -> [String: Any] {
        var dict: [String: Any] = [
            "type": typeCode,
            "offset": fileOffset,
            "offset_hex": String(format: "0x%08X", fileOffset),
            "size": size,
            "header_size": headerSize,
            "is_container": isContainer
        ]
        
        if isFullAtom {
            dict["version"] = version
            dict["flags"] = flags
        }
        
        if !slim && includeRaw && !rawHeader.isEmpty {
            dict["raw_header_hex"] = rawHeader.map { String(format: "%02x", $0) }.joined()
        }
        
        if !children.isEmpty {
            dict["children"] = children.map { $0.toDictionary(includeRaw: includeRaw, includeUnparsed: includeUnparsed, slim: slim) }
        }
        
        if !fields.isEmpty {
            var fieldsDict: [String: Any] = [:]
            for f in fields {
                fieldsDict[f.name] = f.toDictionary(slim: slim)
            }
            dict["fields"] = fieldsDict
        }
        
        if includeUnparsed && !slim {
            let unparsed = calculateUnparsed()
            if !unparsed.isEmpty {
                dict["unparsed_ranges"] = unparsed.map { (s, e) in
                    [
                        "start": s,
                        "end": e,
                        "size": e - s,
                        "start_hex": String(format: "0x%08X", s)
                    ]
                }
            }
        }
        
        return dict
    }
}
