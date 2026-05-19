import Foundation

extension String {
    var ostype: OSType {
        let scalars = unicodeScalars.prefix(4).map { UInt32($0.value) }
        var result: UInt32 = 0
        for scalar in scalars {
            result = (result << 8) + scalar
        }
        return result
    }
}
