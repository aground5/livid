import Foundation

class VmhdParser: AtomProtocol {
    var atomType: String = "vmhd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    private let graphicsModes: [UInt16: String] = [
        0x0000: "Copy",
        0x0020: "Blend",
        0x0024: "Transparent",
        0x0040: "Dither copy",
        0x0100: "Straight alpha",
        0x0101: "Premul white alpha",
        0x0102: "Premul black alpha",
        0x0104: "Straight alpha blend",
        0x0103: "Composition (dither copy)",
    ]
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let mode = reader.readUInt16()
        let modeDesc = graphicsModes[mode.value] ?? "Unknown (0x\(String(format: "%04X", mode.value)))"
        atom.addField(ParsedField(name: "graphics_mode", offset: mode.offset, size: mode.size, value: ["code": mode.value, "name": modeDesc], raw: mode.raw, description: "Transfer mode"))
        
        let opcolor = reader.readColorRGB()
        atom.addField(ParsedField(name: "opcolor", offset: opcolor.offset, size: opcolor.size, value: opcolor.value, raw: opcolor.raw, description: "Operation RGB"))
    }
}

class SmhdParser: AtomProtocol {
    var atomType: String = "smhd"
    var isContainer: Bool = false
    var isFullAtom: Bool = true
    
    func parseData(reader: QtReader, atom: ParsedAtom) {
        parseVersionFlags(reader: reader, atom: atom)
        
        let balance = reader.readFixedPoint8_8()
        // Convert to signed -1.0 to 1.0 if need be, but fixed point usually unsigned reader.
        // QuickTime spec says it's signed fixed point 8.8.
        // 0 = center, -1.0 = left, 1.0 = right.
        // My reader reads unsigned 8.8.
        // 0x0100 -> 1.0. 0x0000 -> 0.0. 0xFF00 -> -1.0.
        // If read as unsigned 8.8: 0x0100 is 1.0. 0xFF00 is 255.0?
        // Let's manually handle the signed nature if needed.
        // Python code logic: "value if value <= 1.0 else value - 2.0"
        
        var val = balance.value
        if val > 1.0 {
            val -= 2.0 // Assuming it wraps? Or purely for 8-bit wrap?
            // If 0xFF00 (uint16=65280) -> 255.0. 255-256 = -1.0? 
            // -1.0 in 8.8 signed is 0xFF00.
            // If reader reads UInt16 and divides by 256.0, 0xFF00 -> 255.0.
            // 8-bit signed integer part.
            // Let's implement Python logic
            // Actually, 8.8 signed: top 8 bits are signed int8.
            // If top byte > 127, it's negative.
            // simpler: read UInt16. Int16(bitPattern: val) / 256.0?
        }
        
        // Actually simplest is just copy Python logic if we trust it, or use improved logic.
        // "value if value <= 1.0 else value - 256.0"? No.
        // Let's check python implementation again.
        // "balance.value if balance.value <= 1.0 else balance.value - 2.0"
        // This implies 0xFF00 / 256.0 = 255.0. 255.0 - X = -1.0? No logic there.
        // Wait, 0xFF00 (65280) / 256 = 255.
        // 16-bit signed -1.0 is ??? 
        // In 8.8, 1.0 is 0x0100. -1.0 is -256 -> 0xFF00 (two's complement 16-bit).
        // If we read as Int16, 0xFF00 is -256. -256 / 256.0 = -1.0. Correct.
        // My reader has `readFixedPoint8_8` which uses UInt16 inside.
        // I should just re-read or cast.
        
        // Let's use the raw bytes from `balance` result to cast properly.
        let rawVal = UInt16(bigEndian: balance.raw.withUnsafeBytes { $0.load(as: UInt16.self) })
        let signedVal = Int16(bitPattern: rawVal)
        let finalBal = Double(signedVal) / 256.0
        
        atom.addField(ParsedField(name: "balance", offset: balance.offset, size: balance.size, value: finalBal, raw: balance.raw, description: "Audio Balance"))
        
        let reserved = reader.readBytes(2)
        atom.addField(ParsedField(name: "reserved", offset: reserved.offset, size: reserved.size, value: "<reserved>", raw: reserved.raw, description: "Reserved"))
    }
}
