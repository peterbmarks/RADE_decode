import CoreLocation

/// Converts between Maidenhead grid locators and geographic coordinates.
enum MaidenheadConverter {

    /// Convert a Maidenhead grid locator (2, 4, or 6 characters) to
    /// the center coordinates of the designated grid cell.
    /// Returns nil if the grid string is invalid.
    static func coordinates(from grid: String) -> CLLocationCoordinate2D? {
        let g = grid.uppercased()
        let chars = Array(g)
        guard chars.count >= 2 else { return nil }

        // Field: 2 uppercase letters A-R
        guard let f1 = chars[0].asciiValue, let f2 = chars[1].asciiValue,
              f1 >= 65, f1 <= 82, f2 >= 65, f2 <= 82 else { return nil }

        var lon = Double(f1 - 65) * 20.0 - 180.0
        var lat = Double(f2 - 65) * 10.0 - 90.0

        var lonSize = 20.0
        var latSize = 10.0

        if chars.count >= 4 {
            // Square: 2 digits 0-9
            guard let s1 = chars[2].wholeNumberValue, let s2 = chars[3].wholeNumberValue,
                  s1 >= 0, s1 <= 9, s2 >= 0, s2 <= 9 else { return nil }
            lon += Double(s1) * 2.0
            lat += Double(s2) * 1.0
            lonSize = 2.0
            latSize = 1.0
        }

        if chars.count >= 6 {
            // Subsquare: 2 letters A-X (case-insensitive, already uppercased)
            guard let sub1 = chars[4].asciiValue, let sub2 = chars[5].asciiValue,
                  sub1 >= 65, sub1 <= 88, sub2 >= 65, sub2 <= 88 else { return nil }
            lon += Double(sub1 - 65) * (2.0 / 24.0)
            lat += Double(sub2 - 65) * (1.0 / 24.0)
            lonSize = 2.0 / 24.0
            latSize = 1.0 / 24.0
        }

        // Return center of the grid cell
        return CLLocationCoordinate2D(
            latitude: lat + latSize / 2.0,
            longitude: lon + lonSize / 2.0
        )
    }
}
