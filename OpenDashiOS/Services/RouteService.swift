import Foundation

enum RouteServiceError: LocalizedError {
    case invalidURL
    case noRoute
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build route request"
        case .noRoute: return "No route found"
        case .badResponse: return "Routing server returned an unexpected response"
        }
    }
}

struct RouteService {
    static let shared = RouteService()

    func route(from origin: Coordinate, to destination: Coordinate) async throws -> RoutePreview {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "router.project-osrm.org"
        components.path = "/route/v1/driving/\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
        components.queryItems = [
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "geometries", value: "polyline"),
            URLQueryItem(name: "steps", value: "true")
        ]
        guard let url = components.url else { throw RouteServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("OpenDash-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RouteServiceError.badResponse
        }
        let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard decoded.code == "Ok", let route = decoded.routes.first else {
            throw RouteServiceError.noRoute
        }
        return RoutePreview(
            points: PolylineDecoder.decode(route.geometry),
            distanceMeters: route.distance,
            durationSeconds: route.duration
        )
    }
}

private struct OSRMResponse: Decodable {
    var code: String
    var routes: [OSRMRoute]
}

private struct OSRMRoute: Decodable {
    var geometry: String
    var distance: Double
    var duration: Double
}

enum PolylineDecoder {
    static func decode(_ encoded: String) -> [Coordinate] {
        var coordinates: [Coordinate] = []
        let scalars = Array(encoded.unicodeScalars.map { Int($0.value) })
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < scalars.count {
            guard let latDelta = nextValue(scalars, index: &index),
                  let lngDelta = nextValue(scalars, index: &index)
            else { break }
            latitude += latDelta
            longitude += lngDelta
            coordinates.append(
                Coordinate(
                    latitude: Double(latitude) / 100_000.0,
                    longitude: Double(longitude) / 100_000.0
                )
            )
        }

        return coordinates
    }

    private static func nextValue(_ scalars: [Int], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        var byte = 0
        repeat {
            guard index < scalars.count else { return nil }
            byte = scalars[index] - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}
