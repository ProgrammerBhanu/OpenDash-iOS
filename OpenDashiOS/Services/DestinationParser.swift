import Foundation

enum DestinationParser {
    private static let coordinatePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"@(-?\d+\.\d+),\s*(-?\d+\.\d+)"#),
        try! NSRegularExpression(pattern: #"[?&](?:q|query|ll|daddr|destination)=(-?\d+\.\d+),\s*(-?\d+\.\d+)"#),
        try! NSRegularExpression(pattern: #"geo:(-?\d+\.\d+),\s*(-?\d+\.\d+)"#),
        try! NSRegularExpression(pattern: #"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)"#)
    ]

    static func parse(_ text: String) -> SharedDestination? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = firstCoordinateMatch(in: trimmed) else { return nil }
        let name = inferredName(from: trimmed) ?? "Shared destination"
        return SharedDestination(
            name: name,
            coordinate: Coordinate(latitude: match.latitude, longitude: match.longitude),
            sourceText: trimmed
        )
    }

    private static func firstCoordinateMatch(in text: String) -> (latitude: Double, longitude: Double)? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for regex in coordinatePatterns {
            guard let match = regex.firstMatch(in: text, range: nsRange),
                  match.numberOfRanges >= 3,
                  let latRange = Range(match.range(at: 1), in: text),
                  let lngRange = Range(match.range(at: 2), in: text),
                  let latitude = Double(text[latRange]),
                  let longitude = Double(text[lngRange]),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude),
                  !(latitude == 0 && longitude == 0)
            else { continue }
            return (latitude, longitude)
        }
        return nil
    }

    private static func inferredName(from text: String) -> String? {
        if let url = URL(string: text), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let query = components.queryItems?.first(where: { ["q", "query"].contains($0.name) })?.value,
               !query.contains(",") {
                return query.replacingOccurrences(of: "+", with: " ")
            }
            let pathParts = components.path
                .split(separator: "/")
                .map { String($0).removingPercentEncoding ?? String($0) }
            if let placeIndex = pathParts.firstIndex(of: "place"),
               pathParts.indices.contains(pathParts.index(after: placeIndex)) {
                return pathParts[pathParts.index(after: placeIndex)]
                    .replacingOccurrences(of: "+", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
            }
        }
        let firstLine = text.components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine, !firstLine.lowercased().hasPrefix("http"), !firstLine.lowercased().hasPrefix("geo:") {
            return firstLine
        }
        return nil
    }
}
