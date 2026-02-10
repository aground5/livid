import Foundation

class PatchableAtom: Identifiable {
    let id = UUID()
    
    var originalAtom: ParsedAtom?
    var typeCode: String
    var children: [PatchableAtom] = []
    var fields: [String: Any] = [:]
    
    // Explicit data for leaf body (excluding header)
    var explicitData: Data?
    
    var isModified: Bool = false
    var isContainer: Bool = false
    
    init(originalAtom: ParsedAtom? = nil, typeCode: String = "") {
        self.originalAtom = originalAtom
        if let atom = originalAtom {
            self.typeCode = atom.typeCode
            self.isContainer = atom.isContainer
            // Load fields
            for field in atom.fields {
                self.fields[field.name] = field.value
            }
        } else {
            self.typeCode = typeCode
        }
    }
    
    static func fromParsed(atom: ParsedAtom) -> PatchableAtom {
        let pa = PatchableAtom(originalAtom: atom)
        if !atom.children.isEmpty {
            pa.children = atom.children.map { fromParsed(atom: $0) }
            pa.isContainer = true // Enforce container if children exist
        }
        return pa
    }
    
    func addChild(_ child: PatchableAtom, index: Int = -1) {
        if index == -1 || index >= children.count {
            children.append(child)
        } else {
            children.insert(child, at: index)
        }
        self.isContainer = true
        self.markModified()
    }
    
    func findChild(typeCode: String) -> PatchableAtom? {
        return children.first { $0.typeCode == typeCode }
    }
    
    func markModified() {
        self.isModified = true
    }
    
    func setField(name: String, value: Any) {
        self.fields[name] = value
        self.markModified()
    }
}

class AtomPatcher {
    let fileURL: URL
    var data: Data
    var parser: QtParser
    var rootAtoms: [PatchableAtom] = []
    
    // Convenience accessors
    var moovAtom: PatchableAtom?
    var mdatAtom: PatchableAtom?
    var ftypAtom: PatchableAtom?
    var wideAtom: PatchableAtom?
    
    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.data = try Data(contentsOf: fileURL)
        
        self.parser = QtParser()
        let parsedAtoms = try parser.parse(fileURL: fileURL)
        
        self.rootAtoms = parsedAtoms.map { PatchableAtom.fromParsed(atom: $0) }
        
        self.moovAtom = rootAtoms.first { $0.typeCode == "moov" }
        self.mdatAtom = rootAtoms.first { $0.typeCode == "mdat" }
        self.ftypAtom = rootAtoms.first { $0.typeCode == "ftyp" }
        self.wideAtom = rootAtoms.first { $0.typeCode == "wide" }
    }
    
    func needsRebuild(atom: PatchableAtom) -> Bool {
        if atom.isModified { return true }
        if atom.isContainer {
            for child in atom.children {
                if needsRebuild(atom: child) {
                    return true
                }
            }
        }
        return false
    }
    
    func writeAtom(writer: QtWriter, atom: PatchableAtom) {
        // 1. Determine if we can copy directly
        var canCopy = (!atom.isModified) && (atom.originalAtom != nil)
        if canCopy && atom.isContainer {
            if needsRebuild(atom: atom) {
                canCopy = false
            }
        }
        
        if canCopy, let orig = atom.originalAtom {
            let start = orig.fileOffset
            let end = orig.endOffset
            if start < data.count && end <= data.count {
                writer.writeBytes(data.subdata(in: start..<end))
            } else {
                // Formatting error or partial?
                print("Error: Atom range out of bounds for copy")
            }
            return
        }
        
        // 2. Rebuild
        let bodyWriter = QtWriter()
        
        if atom.isContainer {
            for child in atom.children {
                writeAtom(writer: bodyWriter, atom: child)
            }
        } else if let explicit = atom.explicitData {
            bodyWriter.writeBytes(explicit)
        } else {
            // Need specific serializer
            serializeLeaf(writer: bodyWriter, atom: atom)
        }
        
        let bodyBytes = bodyWriter.getBytes()
        let size = 8 + bodyBytes.count
        
        writer.writeUInt32(UInt32(size)) // Size
        writer.writeFourCC(atom.typeCode) // Type
        writer.writeBytes(bodyBytes) // Data
    }
    
    func serializeLeaf(writer: QtWriter, atom: PatchableAtom) {
        switch atom.typeCode {
        case "tkhd": writeTkhd(writer: writer, atom: atom)
        case "mvhd": writeMvhd(writer: writer, atom: atom)
        case "mdhd": writeMdhd(writer: writer, atom: atom)
        case "hdlr": writeHdlr(writer: writer, atom: atom)
        case "vmhd": writeVmhd(writer: writer, atom: atom)
        case "smhd": writeSmhd(writer: writer, atom: atom)
        case "dref": writeDref(writer: writer, atom: atom) // Special handling for children
        case "elst": writeElst(writer: writer, atom: atom)
        case "stco": writeStco(writer: writer, atom: atom)
        case "stsc": writeStsc(writer: writer, atom: atom)
        case "stsz": writeStsz(writer: writer, atom: atom)
        case "stts": writeStts(writer: writer, atom: atom)
        case "ctts": writeCtts(writer: writer, atom: atom)
        case "stss": writeStss(writer: writer, atom: atom)
        case "cslg": writeCslg(writer: writer, atom: atom)
        case "sdtp": writeSdtp(writer: writer, atom: atom)
        case "sbgp": writeSbgp(writer: writer, atom: atom) // Check if needed?
        case "sgpd": writeSgpd(writer: writer, atom: atom)
        case "stsd": writeStsd(writer: writer, atom: atom)
        case "csgm": writeCsgm(writer: writer, atom: atom)
        case "clef", "prof", "enof": writeDimAtom(writer: writer, atom: atom)
        default:
            print("Warning: No serializer for modified atom type: \(atom.typeCode). Writing 0 bytes body.")
            // Or raise error if strict
        }
    }
    
    // MARK: - Serializers
    
    func writeMvhd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        let version = (f["version"] as? Int) ?? 0
        writer.writeUInt8(UInt8(version))
        writer.writeBytes(Data([0,0,0]))
        
        if version == 1 {
            writer.writeUInt64(f["creation_time"] as? UInt64 ?? 0)
            writer.writeUInt64(f["modification_time"] as? UInt64 ?? 0)
            writer.writeUInt32(f["time_scale"] as? UInt32 ?? 1000)
            writer.writeUInt64(f["duration"] as? UInt64 ?? 0)
        } else {
            writer.writeUInt32(f["creation_time"] as? UInt32 ?? 0)
            writer.writeUInt32(f["modification_time"] as? UInt32 ?? 0)
            writer.writeUInt32(f["time_scale"] as? UInt32 ?? 1000)
            writer.writeUInt32(f["duration"] as? UInt32 ?? 0)
        }
        
        writer.writeUInt32(0x00010000) // Rate
        writer.writeUInt16(0x0100) // Volume (8.8)
        writer.writeUInt16(0) // Reserved
        writer.writeUInt32(0); writer.writeUInt32(0) // Reserved
        
        // Matrix
        let matrix = f["matrix"] as? [Double] ?? [1,0,0,0,1,0,0,0,1]
        writer.writeMatrix(matrix) // QtWriter has writeMatrix? Check or implement
        
        for _ in 0..<6 { writer.writeUInt32(0) } // Pre-defined
        writer.writeUInt32(f["next_track_id"] as? UInt32 ?? 2)
    }
    
    func writeTkhd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        let flags = f["flags"] as? Int ?? 0
        writer.writeUInt8(UInt8((flags >> 16) & 0xFF))
        writer.writeUInt8(UInt8((flags >> 8) & 0xFF))
        writer.writeUInt8(UInt8(flags & 0xFF))
        
        writer.writeUInt32(f["creation_time"] as? UInt32 ?? 0)
        writer.writeUInt32(f["modification_time"] as? UInt32 ?? 0)
        writer.writeUInt32(f["track_id"] as? UInt32 ?? 1)
        writer.writeUInt32(0)
        writer.writeUInt32(f["duration"] as? UInt32 ?? 0)
        writer.writeUInt32(0); writer.writeUInt32(0)
        
        writer.writeInt16(f["layer"] as? Int16 ?? 0)
        writer.writeInt16(f["alternate_group"] as? Int16 ?? 0)
        writer.writeFixedPoint88(f["volume"] as? Double ?? 0.0)
        writer.writeUInt16(0)
        
        let matrix = f["matrix"] as? [Double] ?? [1,0,0,0,1,0,0,0,1]
        writer.writeMatrix(matrix)
            
        writer.writeFixedPoint1616(f["track_width"] as? Double ?? 0.0)
        writer.writeFixedPoint1616(f["track_height"] as? Double ?? 0.0)
    }
    
    func writeMdhd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        let version = (f["version"] as? Int) ?? 0
        writer.writeUInt8(UInt8(version))
        writer.writeBytes(Data([0,0,0]))
        
        if version == 1 {
            writer.writeUInt64(f["creation_time"] as? UInt64 ?? 0)
            writer.writeUInt64(f["modification_time"] as? UInt64 ?? 0)
            writer.writeUInt32(f["time_scale"] as? UInt32 ?? 0)
            writer.writeUInt64(f["duration"] as? UInt64 ?? 0)
        } else {
            writer.writeUInt32(f["creation_time"] as? UInt32 ?? 0)
            writer.writeUInt32(f["modification_time"] as? UInt32 ?? 0)
            writer.writeUInt32(f["time_scale"] as? UInt32 ?? 0)
            writer.writeUInt32(f["duration"] as? UInt32 ?? 0)
        }
        
        // Language: handle String vs Int
        var langInt: UInt16 = 0
        if let lStr = f["language"] as? String {
             // Basic inverse mapping or 0
             // TODO: implement proper map
             langInt = 0 
        } else if let lInt = f["language"] as? Int {
             langInt = UInt16(lInt)
        }
        writer.writeUInt16(langInt)
        writer.writeUInt16(f["quality"] as? UInt16 ?? 0)
    }
    
    func writeHdlr(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        
        writer.writeFourCC(f["component_type"] as? String ?? "mhlr")
        writer.writeFourCC(f["component_subtype"] as? String ?? "vide")
        writer.writeFourCC(f["component_manufacturer"] as? String ?? "appl")
        
        writer.writeUInt32(f["component_flags"] as? UInt32 ?? 0)
        writer.writeUInt32(f["component_flags_mask"] as? UInt32 ?? 0)
        
        let name = "Core Media Video" 
        if let nameData = name.data(using: .utf8) {
            writer.writeUInt8(UInt8(nameData.count))
            writer.writeBytes(nameData)
        } else {
            writer.writeUInt8(0)
        }
    }
    
    func writeVmhd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,1])) // Flags=1
        
        if let mode = f["graphics_mode"] as? Int {
             writer.writeUInt16(UInt16(mode))
        } else {
             writer.writeUInt16(0)
        }
        
        let op = f["opcolor"] as? [Int] ?? [0,0,0]
        for c in op { writer.writeUInt16(UInt16(c)) }
    }
    
    func writeSmhd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        writer.writeFixedPoint88(f["balance"] as? Double ?? 0.0)
        writer.writeUInt16(0)
    }
    
    func writeDref(writer: QtWriter, atom: PatchableAtom) {
        // dref is container of 'url ' or 'alis'.
        // logic in patcher.py manually constructs generic alis atoms.
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        
        let refs = f["references"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(refs.count))
        
        for ref in refs {
            let aw = QtWriter()
            aw.writeUInt8(UInt8(ref["version"] as? Int ?? 0))
            aw.writeBytes(Data([0,0]))
            aw.writeUInt8(UInt8(ref["flags"] as? Int ?? 1))
            
            let data = aw.getBytes()
            writer.writeUInt32(UInt32(8 + data.count))
            writer.writeFourCC(ref["type"] as? String ?? "alis")
            writer.writeBytes(data)
        }
    }
    
    func writeElst(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        let version = (f["version"] as? Int) ?? 0
        writer.writeUInt8(UInt8(version))
        writer.writeBytes(Data([0,0,0]))
        
        let entries = f["entries"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(entries.count))
        
        for e in entries {
             writer.writeUInt32(e["track_duration"] as? UInt32 ?? 0)
             writer.writeInt32(e["media_time"] as? Int32 ?? 0)
             writer.writeFixedPoint1616(e["media_rate"] as? Double ?? 1.0)
        }
    }
    
    func writeStco(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let offsets = f["chunk_offsets"] as? [UInt32] ?? []
        writer.writeUInt32(UInt32(offsets.count))
        for o in offsets { writer.writeUInt32(o) }
    }
    
    func writeStsc(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let entries = f["entries"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(entries.count))
        for e in entries {
            writer.writeUInt32(e["first_chunk"] as? UInt32 ?? 0)
            writer.writeUInt32(e["samples_per_chunk"] as? UInt32 ?? 0)
            writer.writeUInt32(e["sample_description_id"] as? UInt32 ?? 0)
        }
    }
    
    func writeStsz(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let sz = f["sample_size"] as? UInt32 ?? 0
        writer.writeUInt32(sz)
        
        let entries = f["sample_sizes"] as? [UInt32] ?? []
        if sz == 0 {
            writer.writeUInt32(UInt32(entries.count))
            for s in entries { writer.writeUInt32(s) }
        } else {
            writer.writeUInt32(UInt32(entries.count)) 
        }
    }
    
    func writeStts(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let entries = f["entries"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(entries.count))
        for e in entries {
            writer.writeUInt32(e["sample_count"] as? UInt32 ?? 0)
            writer.writeUInt32(e["sample_duration"] as? UInt32 ?? 0)
        }
    }
    
    func writeCtts(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        let version = (f["version"] as? Int) ?? 0
        writer.writeUInt8(UInt8(version))
        writer.writeBytes(Data([0,0,0]))
        let entries = f["entries"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(entries.count))
        for e in entries {
            writer.writeUInt32(e["sample_count"] as? UInt32 ?? 0)
            if version == 1 {
                writer.writeInt32(e["composition_offset"] as? Int32 ?? 0)
            } else {
                writer.writeUInt32(UInt32(bitPattern: Int32(e["composition_offset"] as? Int ?? 0)))
            }
        }
    }
    
    func writeStss(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let kf = f["keyframes"] as? [UInt32] ?? []
        writer.writeUInt32(UInt32(kf.count))
        for k in kf { writer.writeUInt32(k) }
    }
    
    func writeCslg(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        writer.writeInt32(f["composition_offset_shift"] as? Int32 ?? 0)
        writer.writeInt32(f["least_display_offset"] as? Int32 ?? 0)
        writer.writeInt32(f["greatest_display_offset"] as? Int32 ?? 0)
        writer.writeInt32(f["display_start_time"] as? Int32 ?? 0)
        writer.writeInt32(f["display_end_time"] as? Int32 ?? 0)
    }
    
    func writeSdtp(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let samples = f["samples"] as? [UInt8] ?? []
        writer.writeBytes(Data(samples))
    }
    
    func writeSbgp(writer: QtWriter, atom: PatchableAtom) {
        // Implementation based on fields
        let f = atom.fields
        let v = f["version"] as? Int ?? 0
        writer.writeUInt8(UInt8(v))
        writer.writeBytes(Data([0,0,0]))
        writer.writeFourCC(f["grouping_type"] as? String ?? "roll")
        if v >= 1 {
            writer.writeUInt32(f["default_length"] as? UInt32 ?? 0)
        }
        let entries = f["entries"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(entries.count))
        for e in entries {
            writer.writeUInt32(e["sample_count"] as? UInt32 ?? 0)
            writer.writeUInt32(e["group_description_index"] as? UInt32 ?? 0)
        }
    }
    
    func writeSgpd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        let v = f["version"] as? Int ?? 1
        writer.writeUInt8(UInt8(v))
        writer.writeBytes(Data([0,0,0]))
        
        let gType = f["grouping_type"] as? String ?? "tscl"
        writer.writeFourCC(gType)
        
        let defLen = f["default_length"] as? UInt32 ?? 0
        if v >= 1 { writer.writeUInt32(defLen) }
        
        let entries = f["entries"] as? [Any] ?? []
        writer.writeUInt32(UInt32(entries.count))
        
        // Simplified writing assuming fields match structure
        if gType == "roll", let rollEntries = entries as? [[String: Int16]] {
             for e in rollEntries { writer.writeInt16(e["roll_distance"] ?? 0) }
        } else if gType == "tscl" {
             for e in entries {
                 if defLen == 0 { writer.writeUInt32(20) }
                 if let d = e as? [String: Any] {
                     // Write fields
                     // TODO: Ensure validation
                     writer.writeBytes(Data(count: 20)) // Placeholder if data missing, or look at dict
                 } else {
                     writer.writeBytes(Data(count: 20))
                 }
             }
        }
        // ... more types if needed
    }
    
    func writeStsd(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        let descs = f["sample_descriptions"] as? [[String: Any]] ?? []
        writer.writeUInt32(UInt32(descs.count))
        
        // This is tricky: stsd has variable children which are often parsed as blobs or complex atoms.
        // If modified, we need robust reconstruction.
        // For now, if we don't modify stsd, we should be copying it in writeAtom.
        // If we implement this, we need to handle the specific codecs (avc1 etc).
        // Since we likely copy stsd, I will leave this basic.
    }
    
    func writeCsgm(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        writer.writeFourCC(f["sub_type"] as? String ?? "tscl")
        for i in 1...6 {
            writer.writeUInt32(f["custom_field_\(i)"] as? UInt32 ?? 0)
        }
        // Custom data
        // ...
    }
    
    func writeDimAtom(writer: QtWriter, atom: PatchableAtom) {
        let f = atom.fields
        writer.writeUInt8(UInt8(f["version"] as? Int ?? 0))
        writer.writeBytes(Data([0,0,0]))
        writer.writeFixedPoint1616(f["width"] as? Double ?? 0.0)
        writer.writeFixedPoint1616(f["height"] as? Double ?? 0.0)
    }
    
    // MARK: - Patching Logic
    
    func patchStco(offsetDelta: Int) {
        guard let moov = moovAtom else { return }
        // DFS to find all stco
        func findStco(atom: PatchableAtom) {
            if atom.typeCode == "stco" {
                var offsets = atom.fields["chunk_offsets"] as? [UInt32] ?? []
                offsets = offsets.map { UInt32(Int($0) + offsetDelta) }
                atom.setField(name: "chunk_offsets", value: offsets)
                atom.markModified()
            } else if atom.isContainer {
                for child in atom.children {
                    findStco(atom: child)
                }
            }
        }
        findStco(atom: moov)
        // Note: markModified propogation is handled by recursively checking isModified in writeAtom/needsRebuild 
        // BUT we need to mark parents modified if we modify child?
        // My needsRebuild function checks children recursively. 
        // So we just need to ensure the stco atom itself is marked modified.
        // And `atom.setField` calls `markModified` on itself.
        // So `needsRebuild(moov)` will traverse down and see `stco` is modified, returning true.
    }
    
    func save(outputURL: URL) throws {
        // Unlikely to remove udta in Swift port? Python did it.
        // if let udta = moovAtom.findChild("udta") { moovAtom.children.removeAll(udta) ... }
        
        let ftypSize = ftypAtom?.originalAtom?.size ?? 20
        let wideSize = 8
        let mdatHeaderSize = 8
        let newMdatContentStart = ftypSize + wideSize + mdatHeaderSize
        
        guard let mdat = mdatAtom, let origMdat = mdat.originalAtom else { return }
        let origMdatContentStart = origMdat.fileOffset + 8 
        
        let delta = newMdatContentStart - origMdatContentStart
        print("Shift delta: \(delta)")
        patchStco(offsetDelta: delta)
        
        let writer = QtWriter()
        
        // 1. ftyp
        if let ftyp = ftypAtom { writeAtom(writer: writer, atom: ftyp) }
        
        // 2. wide
        writer.writeUInt32(8)
        writer.writeFourCC("wide")
        
        // 3. mdat
        writeAtom(writer: writer, atom: mdat)
        
        // 4. moov
        if let moov = moovAtom { writeAtom(writer: writer, atom: moov) }
        
        try writer.getBytes().write(to: outputURL)
    }
    func getPatchedData() throws -> Data {
        let ftypSize = ftypAtom?.originalAtom?.size ?? 20
        let wideSize = 8
        let mdatHeaderSize = 8
        let newMdatContentStart = ftypSize + wideSize + mdatHeaderSize
        
        guard let mdat = mdatAtom, let origMdat = mdat.originalAtom else { return Data() }
        let origMdatContentStart = origMdat.fileOffset + 8 
        
        let delta = newMdatContentStart - origMdatContentStart
        // print("Shift delta: \(delta)") 
        patchStco(offsetDelta: delta)
        
        let writer = QtWriter()
        
        // 1. ftyp
        if let ftyp = ftypAtom { writeAtom(writer: writer, atom: ftyp) }
        
        // 2. wide
        writer.writeUInt32(8)
        writer.writeFourCC("wide")
        
        // 3. mdat
        writeAtom(writer: writer, atom: mdat)
        
        // 4. moov
        if let moov = moovAtom { writeAtom(writer: writer, atom: moov) }
        
        return writer.getBytes()
    }
}

