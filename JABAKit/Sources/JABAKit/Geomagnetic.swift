import Foundation

/// Where a location sits relative to the auroral oval.
public struct GeomagneticInfo: Hashable, Sendable {
    /// Centered-dipole magnetic latitude, degrees.
    public let magneticLatitude: Double
    /// Kp at which aurora reaches this location's northern horizon.
    public let requiredKp: Double

    public init(latitude: Double, longitude: Double) {
        magneticLatitude = Geomagnetic.magneticLatitude(latitude: latitude, longitude: longitude)
        requiredKp = Geomagnetic.requiredKp(magneticLatitude: magneticLatitude)
    }

    /// Even a Kp 9 storm would not bring aurora into view here.
    public var isOutOfReach: Bool { requiredKp > 9 }
}

public enum Geomagnetic {
    /// IGRF-14 geomagnetic (dipole) north pole, epoch 2025. The dipole model is
    /// accurate to about a degree, which is plenty for a visibility call.
    public static let poleLatitude = 80.8
    public static let poleLongitude = -72.7

    /// Magnetic latitude of the equatorward edge of aurora visible on the
    /// northern horizon, indexed by Kp 0...9 (standard NOAA / UAF table).
    public static let visibilityLatitudeByKp: [Double] = [
        66.5, 64.5, 62.4, 60.4, 58.3, 56.3, 54.2, 52.2, 50.1, 48.1,
    ]

    public static func magneticLatitude(latitude: Double, longitude: Double) -> Double {
        let lat = latitude.radians, lon = longitude.radians
        let poleLat = poleLatitude.radians, poleLon = poleLongitude.radians
        let cosColatitude = sin(lat) * sin(poleLat) + cos(lat) * cos(poleLat) * cos(lon - poleLon)
        return 90 - acos(min(1, max(-1, cosColatitude))).degrees
    }

    /// Kp needed for aurora on the horizon, interpolated between whole-Kp rows of
    /// the table. Returns more than 9 when even an extreme storm falls short.
    public static func requiredKp(magneticLatitude: Double) -> Double {
        let lat = abs(magneticLatitude)
        let table = visibilityLatitudeByKp
        if lat >= table[0] { return 0 }
        for kp in 1..<table.count where lat >= table[kp] {
            let upper = table[kp - 1], lower = table[kp]
            return Double(kp - 1) + (upper - lat) / (upper - lower)
        }
        let step = table[table.count - 2] - table[table.count - 1]
        return 9 + (table[table.count - 1] - lat) / step
    }
}
