import CoreGraphics
import Foundation

/// Math with one fixed meaning. Swift Playgrounds on the iPad stops with
/// "ambiguous use of 'cos'" when a call could be either the Double or the
/// CGFloat version (Xcode quietly picks one). These take and return Double
/// (or CGFloat for `distance`), so every call has a single meaning; convert
/// with CGFloat(...) where a CGFloat is needed. Use these instead of the bare
/// cos, sin, sqrt, hypot, pow, log, atan, floor and ceil.
enum Math {
    static func cosine(_ x: Double) -> Double {
        let result: Double = cos(x)
        return result
    }

    static func sine(_ x: Double) -> Double {
        let result: Double = sin(x)
        return result
    }

    static func arcTangent(_ x: Double) -> Double {
        let result: Double = atan(x)
        return result
    }

    /// The angle of the point (x, y) from the x axis, in -π...π.
    static func angle(y: Double, x: Double) -> Double {
        let result: Double = atan2(y, x)
        return result
    }

    static func root(_ x: Double) -> Double {
        let result: Double = sqrt(x)
        return result
    }

    static func power(_ base: Double, _ exponent: Double) -> Double {
        let result: Double = pow(base, exponent)
        return result
    }

    static func logarithm(_ x: Double) -> Double {
        let result: Double = log(x)
        return result
    }

    static func logarithm10(_ x: Double) -> Double {
        let result: Double = log10(x)
        return result
    }

    static func roundDown(_ x: Double) -> Double {
        let result: Double = floor(x)
        return result
    }

    static func roundUp(_ x: Double) -> Double {
        let result: Double = ceil(x)
        return result
    }

    /// The length of (dx, dy).
    static func distance(_ dx: CGFloat, _ dy: CGFloat) -> CGFloat {
        let x: Double = Double(dx)
        let y: Double = Double(dy)
        let result: Double = hypot(x, y)
        return CGFloat(result)
    }
}
