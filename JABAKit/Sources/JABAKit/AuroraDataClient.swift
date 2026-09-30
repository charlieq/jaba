import Foundation

/// Fetches the three feeds JABA needs. None require an API key.
public struct AuroraDataClient: Sendable {
    /// NOAA SWPC 3-day planetary Kp forecast (the source behind gi.alaska.edu's aurora forecast).
    public static let kpForecastURL = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")!
    /// NOAA SWPC OVATION 30-minute aurora model.
    public static let ovationURL = URL(string: "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func kpForecast() async throws -> KpForecast {
        try KpForecast.parseNOAA(await get(Self.kpForecastURL, source: "NOAA Kp forecast"))
    }

    public func weather(latitude: Double, longitude: Double) async throws -> WeatherForecast {
        let url = WeatherForecast.openMeteoURL(latitude: latitude, longitude: longitude)
        return try WeatherForecast.parseOpenMeteo(await get(url, source: "Open-Meteo"))
    }

    public func ovation() async throws -> OvationGrid {
        try OvationGrid.parse(await get(Self.ovationURL, source: "NOAA aurora nowcast"))
    }

    public func searchPlaces(matching query: String) async throws -> [Place] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return try Place.parseOpenMeteo(await get(components.url!, source: "Open-Meteo geocoding"))
    }

    private func get(_ url: URL, source: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("JABA/1.0 (Julie's Aurora Borealis App)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ForecastError.badResponse(source: source, status: http.statusCode)
        }
        return data
    }
}
