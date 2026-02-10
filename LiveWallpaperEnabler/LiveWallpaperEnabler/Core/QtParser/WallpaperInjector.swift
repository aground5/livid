import Foundation

class WallpaperInjector {
    
    enum InjectorError: Error {
        case atomNotFound(String)
        case analysisFailed(String)
    }
    
    static func patch(patcher: AtomPatcher) throws {
        guard let moov = patcher.rootAtoms.first(where: { $0.typeCode == "moov" }) else {
            throw InjectorError.atomNotFound("moov")
        }
        
        guard let trak = moov.children.first(where: { $0.typeCode == "trak" }) else {
            throw InjectorError.atomNotFound("trak")
        }
        
        guard let mdia = trak.children.first(where: { $0.typeCode == "mdia" }) else {
            throw InjectorError.atomNotFound("mdia")
        }
        
        guard let minf = mdia.children.first(where: { $0.typeCode == "minf" }) else {
            throw InjectorError.atomNotFound("minf")
        }
        
        guard let stbl = minf.children.first(where: { $0.typeCode == "stbl" }) else {
            throw InjectorError.atomNotFound("stbl")
        }
        
        // 1. Analyze for Temporal IDs
        // We need stsz, stsc, chunk_offsets (stco/co64)
        
        guard let stsz = stbl.children.first(where: { $0.typeCode == "stsz" }),
              let stsc = stbl.children.first(where: { $0.typeCode == "stsc" }) else {
            throw InjectorError.atomNotFound("stsz or stsc")
        }
        
        let chunkOffsetsAtom = stbl.children.first(where: { $0.typeCode == "stco" }) ?? stbl.children.first(where: { $0.typeCode == "co64" })
        guard let chunkOffsetsAtom = chunkOffsetsAtom else {
             throw InjectorError.atomNotFound("stco/co64")
        }
        
        // Extract values using ParsedAtom fields (PatchableAtom wraps ParsedAtom)
        // Note: PatchableAtom usually has parsed fields if it was parsed.
        // If they were valid atoms, parsed fields should be populated.
        
        // Helper to get field value safely
        func getField(_ atom: PatchableAtom, _ name: String) -> Any? {
            // Check overrides or original
            // PatchableAtom doesn't expose fields map directly usually, it wraps original.
            // But we need to access the ParsedField data.
            // Assuming we haven't modified them yet, use originalAtom
            if let f = atom.originalAtom?.fields.first(where: { $0.name == name }) {
                return f.value
            }
            return nil
        }
        
        // stsz
        var sampleSizes: [Int] = []
        if let size = getField(stsz, "sample_size") as? Int, size > 0 { // size might be UInt32 too check parser
             // Actually most fields are Int or UInt32. Let's handle both or check parser.
             // Usually size 0 is common for mix.
             // Let's assume size is UInt32 or Int.
             if let s = getField(stsz, "sample_size") as? UInt32 {
                 if let count = getField(stsz, "sample_count") as? UInt32 {
                     sampleSizes = Array(repeating: Int(s), count: Int(count))
                 } else if let count = getField(stsz, "sample_count") as? Int {
                     sampleSizes = Array(repeating: Int(s), count: count)
                 }
             } else if let s = getField(stsz, "sample_size") as? Int, s > 0 {
                  if let count = getField(stsz, "sample_count") as? Int {
                      sampleSizes = Array(repeating: s, count: count)
                  }
             }
        } 
        
        if sampleSizes.isEmpty {
             if let entries = getField(stsz, "sample_sizes") as? [UInt32] {
                 sampleSizes = entries.map { Int($0) }
             } else if let entries = getField(stsz, "sample_sizes") as? [Int] {
                 sampleSizes = entries
             }
        }
        
        // stsc
        // entries likely contain UInt32 values if parsed by QtReader.readUInt32
        var stscEntries: [[String: Any]] = []
        if let rawEntries = getField(stsc, "entries") as? [[String: Any]] {
            // Check if we need to convert contents
            stscEntries = rawEntries.map { dict in
                var newDict = dict
                if let v = dict["first_chunk"] as? UInt32 { newDict["first_chunk"] = Int(v) }
                if let v = dict["samples_per_chunk"] as? UInt32 { newDict["samples_per_chunk"] = Int(v) }
                if let v = dict["sample_description_id"] as? UInt32 { newDict["sample_description_id"] = Int(v) }
                return newDict
            }
        }
        
        // stco
        var chunkOffsets: [Int] = []
        if let offsets = getField(chunkOffsetsAtom, "chunk_offsets") as? [UInt32] {
            chunkOffsets = offsets.map { Int($0) }
        } else if let offsets = getField(chunkOffsetsAtom, "chunk_offsets") as? [Int] {
            chunkOffsets = offsets
        }
        
        // Run analysis
        
        var temporalIds: [Int] = []
        if let fileURL = Optional(patcher.fileURL) {
             let readerData = try Data(contentsOf: fileURL)
             let reader = QtReader(data: readerData)
             temporalIds = QtNALUnitParser.extractTemporalIDs(stszSizes: sampleSizes, chunkOffsets: chunkOffsets, stscEntries: stscEntries, reader: reader)
        }
        
        print("Analysis complete. Found \(temporalIds.count) samples.")
        if temporalIds.isEmpty {
            print("Warning: No temporal IDs found (not HEVC or analysis failed). Using default linear/flat structure.")
        }
        
        // 2. Modify Atoms
        
        // TKHD: Patch flags
        if let tkhd = trak.children.first(where: { $0.typeCode == "tkhd" }) {
            tkhd.setField(name: "flags", value: 15)
        }
        
        // VMHD
        if let vmhd = minf.children.first(where: { $0.typeCode == "vmhd" }) {
            vmhd.setField(name: "graphics_mode", value: 64)
            vmhd.setField(name: "opcolor", value: [32768, 32768, 32768])
        }
        
        // HDLR
        if let hdlr = mdia.children.first(where: { $0.typeCode == "hdlr" }) {
             if let subtype = getField(hdlr, "component_subtype") as? String, subtype == "url " {
                 hdlr.setField(name: "component_subtype", value: "alis")
             }
        }
        
        // ELST
        if let edts = trak.children.first(where: { $0.typeCode == "edts" }),
           let elst = edts.children.first(where: { $0.typeCode == "elst" }) {
             if var entries = getField(elst, "entries") as? [[String: Any]] {
                 if !entries.isEmpty {
                     var e0 = entries[0]
                     e0["media_time"] = 0
                     entries[0] = e0
                     elst.setField(name: "entries", value: entries)
                 }
             }
        }
        
        // 3. Generate & Inject
        
        // Helper to strip header (8 bytes)
        func bodyOf(_ data: Data) -> Data {
            guard data.count > 8 else { return Data() }
            return data.subdata(in: 8..<data.count)
        }
        
        // TAPT
        var width = 0.0
        var height = 0.0
        if let tkhd = trak.children.first(where: { $0.typeCode == "tkhd" }) {
            width = getField(tkhd, "track_width") as? Double ?? 0.0
            height = getField(tkhd, "track_height") as? Double ?? 0.0
        }
        
        let taptData = QtAtomGenerator.createTaptAtom(width: width, height: height)
        let taptAtom = PatchableAtom(typeCode: "tapt")
        taptAtom.explicitData = bodyOf(taptData)
        
        // Insert tapt into trak AFTER tkhd
        if let tkhdIndex = trak.children.firstIndex(where: { $0.typeCode == "tkhd" }) {
            trak.children.insert(taptAtom, at: tkhdIndex + 1)
        } else {
            trak.children.append(taptAtom)
        }
        
        // SGPD & CSGM & CSLG
        var baseDuration: UInt32 = 1000
        if let stts = stbl.children.first(where: { $0.typeCode == "stts" }),
           let entries = getField(stts, "entries") as? [[String: Any]],
           !entries.isEmpty {
             if let dur = entries[0]["sample_duration"] as? Int {
                 baseDuration = UInt32(dur)
             } else if let dur = entries[0]["sample_duration"] as? UInt32 {
                 baseDuration = dur
             }
        }
        
        let maxTid = temporalIds.max() ?? 0
        let sgpdDataList = QtAtomGenerator.createSgpdAtoms(maxTemporalId: maxTid, baseDuration: baseDuration)
        let csgmDataList = QtAtomGenerator.createCsgmAtoms(temporalIds: temporalIds)
        
        var cslgData = Data()
        if let ctts = stbl.children.first(where: { $0.typeCode == "ctts" }),
           let entries = getField(ctts, "entries") as? [[String: Any]] {
            cslgData = QtAtomGenerator.createCslgAtom(cttsEntries: entries)
        }
        
        func addAtom(_ data: Data, type: String) {
            let a = PatchableAtom(typeCode: type)
            a.explicitData = bodyOf(data)
            stbl.children.append(a)
        }
        
        for d in sgpdDataList { addAtom(d, type: "sgpd") }
        for d in csgmDataList { addAtom(d, type: "csgm") }
        if !cslgData.isEmpty { addAtom(cslgData, type: "cslg") }
        
        // Reorder STBL children?
        // cli.py enforces: stsd, sgpd, csgm, stts, ctts, cslg, stss, sdtp, stsc, stsz, stco, co64
        let order = ["stsd", "sgpd", "csgm", "stts", "ctts", "cslg", "stss", "sdtp", "stsc", "stsz", "stco", "co64"]
        
        stbl.children.sort { (a, b) -> Bool in
            let idxA = order.firstIndex(of: a.typeCode) ?? 999
            let idxB = order.firstIndex(of: b.typeCode) ?? 999
            if idxA == idxB { return false } // Stable?
            return idxA < idxB
        }
        
        print("Injected atoms into STBL and reordered.")
    }
}
