import Foundation

/// A Big-Endian Binary Writer for QuickTime/MP4 files.
class QtWriter {
    private var data: Data
    
    init() {
        self.data = Data()
    }
    
    var count: Int {
        return data.count
    }
    
    func getBytes() -> Data {
        return data
    }
    
    func writeBytes(_ value: Data) {
        data.append(value)
    }
    
    func writeUInt8(_ value: UInt8) {
        data.append(value)
    }
    
    func writeUInt16(_ value: UInt16) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    
    func writeInt16(_ value: Int16) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    
    func writeUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    
    func writeInt32(_ value: Int32) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    
    func writeUInt64(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    
    func writeFourCC(_ value: String) {
        guard value.count == 4 else {
            print("Warning: FourCC must be 4 chars: \(value)")
            // Fallback or padding?
            if value.count < 4 {
                let padded = value.padding(toLength: 4, withPad: " ", startingAt: 0)
                if let d = padded.data(using: .isoLatin1) { data.append(d) }
            } else {
                 if let d = String(value.prefix(4)).data(using: .isoLatin1) { data.append(d) }
            }
            return
        }
        if let d = value.data(using: .isoLatin1) {
            data.append(d)
        }
    }
    
    func writeFixedPoint1616(_ value: Double) {
        let rawValue = UInt32(value * 65536.0)
        writeUInt32(rawValue)
    }
    
    func writeFixedPoint88(_ value: Double) {
        let rawValue = UInt16(value * 256.0)
        writeUInt16(rawValue)
    }
    
    func writeMatrix(_ matrix: [Double]) {
        guard matrix.count == 9 else {
            print("Warning: Matrix must have 9 elements")
            return
        }
        // a, b, u (row 1)
        writeFixedPoint1616(matrix[0])
        writeFixedPoint1616(matrix[1])
        // u is 2.30
        writeUInt32(UInt32(matrix[2] * 1073741824.0))
        
        // c, d, v (row 2)
        writeFixedPoint1616(matrix[3])
        writeFixedPoint1616(matrix[4])
        // v is 2.30
        writeUInt32(UInt32(matrix[5] * 1073741824.0))
        
        // tx, ty, w (row 3)
        writeFixedPoint1616(matrix[6])
        writeFixedPoint1616(matrix[7])
        // w is 2.30
        writeUInt32(UInt32(matrix[8] * 1073741824.0))
    }
    
    func writeZeros(_ count: Int) {
        data.append(Data(count: count))
    }
}
