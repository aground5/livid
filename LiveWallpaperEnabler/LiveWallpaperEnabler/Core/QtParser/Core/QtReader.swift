import Foundation

/// Represents a result from a read operation, including the value, original offset, size, and raw bytes.
struct ReadResult<T> {
    let value: T
    let offset: Int
    let size: Int
    let raw: Data
}

/// A Big-Endian Binary Reader for QuickTime/MP4 files.
class QtReader {
    private let data: Data
    private var _pos: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    var position: Int {
        get { _pos }
        set { _pos = newValue }
    }
    
    var remaining: Int {
        return data.count - _pos
    }
    
    func seek(_ position: Int) {
        self._pos = position
    }
    
    func seekRelative(_ offset: Int) {
        self._pos += offset
    }
    
    func readBytes(_ size: Int) -> ReadResult<Data> {
        let offset = _pos
        guard offset + size <= data.count else {
            // Return empty if OOB
            return ReadResult(value: Data(), offset: offset, size: 0, raw: Data())
        }
        
        let range = offset..<(offset + size)
        let subdata = data.subdata(in: range)
        _pos += size
        return ReadResult(value: subdata, offset: offset, size: size, raw: subdata)
    }
    
    func readUInt8() -> ReadResult<UInt8> {
        let res = readBytes(1)
        let val = res.raw.first ?? 0
        return ReadResult(value: val, offset: res.offset, size: 1, raw: res.raw)
    }
    
    func readUInt16() -> ReadResult<UInt16> {
        let res = readBytes(2)
        guard res.raw.count == 2 else { return ReadResult(value: 0, offset: res.offset, size: res.size, raw: res.raw) }
        let val = UInt16(bigEndian: res.raw.withUnsafeBytes { $0.load(as: UInt16.self) })
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readInt16() -> ReadResult<Int16> {
        let res = readBytes(2)
        guard res.raw.count == 2 else { return ReadResult(value: 0, offset: res.offset, size: res.size, raw: res.raw) }
        let val = Int16(bigEndian: res.raw.withUnsafeBytes { $0.load(as: Int16.self) })
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readUInt32() -> ReadResult<UInt32> {
        let res = readBytes(4)
        guard res.raw.count == 4 else { return ReadResult(value: 0, offset: res.offset, size: res.size, raw: res.raw) }
        let val = UInt32(bigEndian: res.raw.withUnsafeBytes { $0.load(as: UInt32.self) })
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readInt32() -> ReadResult<Int32> {
        let res = readBytes(4)
        guard res.raw.count == 4 else { return ReadResult(value: 0, offset: res.offset, size: res.size, raw: res.raw) }
        let val = Int32(bigEndian: res.raw.withUnsafeBytes { $0.load(as: Int32.self) })
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readUInt64() -> ReadResult<UInt64> {
        let res = readBytes(8)
        guard res.raw.count == 8 else { return ReadResult(value: 0, offset: res.offset, size: res.size, raw: res.raw) }
        let val = UInt64(bigEndian: res.raw.withUnsafeBytes { $0.load(as: UInt64.self) })
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readInt64() -> ReadResult<Int64> {
        let res = readBytes(8)
        guard res.raw.count == 8 else { return ReadResult(value: 0, offset: res.offset, size: res.size, raw: res.raw) }
        let val = Int64(bigEndian: res.raw.withUnsafeBytes { $0.load(as: Int64.self) })
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readFourCC() -> ReadResult<String> {
        let res = readBytes(4)
        if let str = String(data: res.raw, encoding: .isoLatin1) {
            return ReadResult(value: str, offset: res.offset, size: res.size, raw: res.raw)
        } else {
            return ReadResult(value: res.raw.hexString, offset: res.offset, size: res.size, raw: res.raw)
        }
    }
    
    func readFixedPoint16_16() -> ReadResult<Double> {
        let res = readUInt32()
        // 16.16
        let val = Double(res.value) / 65536.0
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readFixedPoint8_8() -> ReadResult<Double> {
        let res = readUInt16()
        // 8.8
        let val = Double(res.value) / 256.0
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readFixedPoint2_30() -> ReadResult<Double> {
        let res = readUInt32()
        // 2.30
        let val = Double(res.value) / 1073741824.0 // 1 << 30
        return ReadResult(value: val, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readString(length: Int) -> ReadResult<String> {
        let res = readBytes(length)
        // Handle null termination if present
        var data = res.raw
        if let nullIndex = data.firstIndex(of: 0) {
            data = data.subdata(in: 0..<nullIndex)
        }
        let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
        return ReadResult(value: str, offset: res.offset, size: res.size, raw: res.raw)
    }
    
    func readPascalString() -> ReadResult<String> {
        let offset = _pos
        let lenRes = readUInt8()
        let len = Int(lenRes.value)
        let strRes = readBytes(len)
        
        let totalRaw = lenRes.raw + strRes.raw
        let str = String(data: strRes.raw, encoding: .utf8) ?? String(data: strRes.raw, encoding: .ascii) ?? ""
        
        return ReadResult(value: str, offset: offset, size: 1 + len, raw: totalRaw)
    }
    
    func readMatrix() -> ReadResult<[Double]> {
        let offset = _pos
        var matrix: [Double] = []
        var raw = Data()
        
        // a, b, u (row 1)
        for _ in 0..<2 {
            let r = readFixedPoint16_16()
            raw.append(r.raw)
            matrix.append(r.value)
        }
        let u = readFixedPoint2_30()
        raw.append(u.raw)
        matrix.append(u.value)
        
        // c, d, v (row 2)
        for _ in 0..<2 {
            let r = readFixedPoint16_16()
            raw.append(r.raw)
            matrix.append(r.value)
        }
        let v = readFixedPoint2_30()
        raw.append(v.raw)
        matrix.append(v.value)
        
        // tx, ty, w (row 3)
        for _ in 0..<2 {
            let r = readFixedPoint16_16()
            raw.append(r.raw)
            matrix.append(r.value)
        }
        let w = readFixedPoint2_30()
        raw.append(w.raw)
        matrix.append(w.value)
        
        return ReadResult(value: matrix, offset: offset, size: 36, raw: raw)
    }
    
    func readColorRGB() -> ReadResult<[String: UInt16]> {
        let offset = _pos
        let r = readUInt16()
        let g = readUInt16()
        let b = readUInt16()
        
        return ReadResult(
            value: ["r": r.value, "g": g.value, "b": b.value],
            offset: offset,
            size: 6,
            raw: r.raw + g.raw + b.raw
        )
    }
}

fileprivate extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
