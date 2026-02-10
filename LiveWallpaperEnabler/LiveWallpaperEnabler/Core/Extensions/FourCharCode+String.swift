import Foundation
import CoreMedia

extension FourCharCode {
    func toString() -> String {
        let n = Int(self)
        var s = ""
        for i in 0..<4 {
            let shift = (3 - i) * 8
            let c = UnicodeScalar((n >> shift) & 0xff)
            if let scalar = c {
                if Character(scalar).isASCII {
                    s.append(Character(scalar))
                }
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
