import Foundation

public struct SavedLocation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var region: String?
    public var country: String?
    public var latitude: Double
    public var longitude: Double

    public init(id: UUID = UUID(), name: String, region: String? = nil, country: String? = nil, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    public var subtitle: String {
        [region, country].compactMap { $0 }.joined(separator: ", ")
    }

    public var geomagnetic: GeomagneticInfo {
        GeomagneticInfo(latitude: latitude, longitude: longitude)
    }

    /// Starter list for first launch: the places Julie asked about.
    public static let starters: [SavedLocation] = [
        SavedLocation(name: "Canmore", region: "Alberta", country: "Canada", latitude: 51.0884, longitude: -115.3479),
        SavedLocation(name: "Whitehorse", region: "Yukon", country: "Canada", latitude: 60.7212, longitude: -135.0568),
        SavedLocation(name: "Haines", region: "Alaska", country: "United States", latitude: 59.2360, longitude: -135.4453),
    ]
}

/// A geocoding search result from Open-Meteo.
public struct Place: Decodable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let country: String?
    public let countryCode: String?
    public let admin1: String?
    public let timezone: String?

    public var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }

    public func makeSavedLocation() -> SavedLocation {
        SavedLocation(name: name, region: admin1, country: country, latitude: latitude, longitude: longitude)
    }

    public static func parseOpenMeteo(_ data: Data) throws -> [Place] {
        struct Response: Decodable { let results: [Place]? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Response.self, from: data).results ?? []
        } catch {
            throw ForecastError.unexpectedFormat(source: "Open-Meteo geocoding")
        }
    }
}

/// Persists the user's location list as JSON.
public struct LocationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [SavedLocation]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([SavedLocation].self, from: data)
    }

    public func save(_ locations: [SavedLocation]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(locations).write(to: fileURL, options: .atomic)
    }
}
