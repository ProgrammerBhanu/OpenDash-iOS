import Foundation
import CoreLocation

enum DestinationParser {
    private struct CoordinatePattern {
        let regex: NSRegularExpression
        let latitudeRangeIndex: Int
        let longitudeRangeIndex: Int

        init(_ pattern: String, latitudeRangeIndex: Int = 1, longitudeRangeIndex: Int = 2) {
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.latitudeRangeIndex = latitudeRangeIndex
            self.longitudeRangeIndex = longitudeRangeIndex
        }
    }

    private static let mapCoordinatePatterns: [CoordinatePattern] = [
        CoordinatePattern(#"@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)"#),
        CoordinatePattern(#"geo:\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)"#),
        CoordinatePattern(#"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#),
        CoordinatePattern(#"!4d(-?\d+(?:\.\d+)?)!3d(-?\d+(?:\.\d+)?)"#, latitudeRangeIndex: 2, longitudeRangeIndex: 1),
        CoordinatePattern(#"!2d(-?\d+(?:\.\d+)?)!3d(-?\d+(?:\.\d+)?)"#, latitudeRangeIndex: 2, longitudeRangeIndex: 1)
    ]
    private static let plainCoordinateRegex = try! NSRegularExpression(
        pattern: #"^\s*(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)\s*$"#,
        options: [.caseInsensitive]
    )

    private static let webURLRegex = try! NSRegularExpression(pattern: #"https?://\S+"#, options: [.caseInsensitive])
    private static let coordinateQueryNames: Set<String> = [
        "q", "query", "ll", "sll", "daddr", "destination", "center"
    ]
    private static let nestedURLQueryNames: Set<String> = ["link", "url", "u"]

    static func parse(_ text: String) -> SharedDestination? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for candidate in coordinateCandidates(from: trimmed) {
            guard let match = firstCoordinateMatch(in: candidate) else { continue }
            let name = inferredName(from: trimmed) ?? inferredName(from: candidate) ?? "Shared destination"
            return SharedDestination(
                name: name,
                coordinate: Coordinate(latitude: match.latitude, longitude: match.longitude),
                sourceText: trimmed
            )
        }

        return nil
    }

    static func geocodableQuery(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let detectedURL = firstURL(in: trimmed) ?? URL(string: trimmed)
        if let url = detectedURL,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let queryItems = components.queryItems {
                for name in ["destination", "daddr", "q", "query", "address"] {
                    if let value = queryItems.first(where: { $0.name.lowercased() == name })?.value,
                       let cleaned = cleanedPlaceName(value) {
                        return cleaned
                    }
                }
            }

            if let placeName = placeName(from: components) {
                return placeName
            }

            return nil
        }

        let firstLine = trimmed.components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedPlaceName(firstLine ?? "")
    }

    static func firstURL(in text: String) -> URL? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = webURLRegex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range, in: text)
        else { return nil }

        var value = String(text[range])
        while let last = value.last, ".,);]}>".contains(last) {
            value.removeLast()
        }
        return URL(string: value)
    }

    private static func coordinateCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func append(_ value: String?) {
            guard let value else { return }
            let variants = [
                value,
                value.removingPercentEncoding ?? value
            ]
            for variant in variants {
                let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                candidates.append(trimmed)
            }
        }

        func appendURLPieces(_ url: URL) {
            append(url.absoluteString)
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            append(components.path)
            append(components.percentEncodedQuery)
            append(components.query)
            append(components.fragment)

            let items = components.queryItems ?? []
            appendCoordinatePairs(from: items, into: &candidates, seen: &seen)

            for item in items where nestedURLQueryNames.contains(item.name.lowercased()) {
                guard let nested = item.value,
                      let nestedURL = URL(string: nested)
                else { continue }
                appendURLPieces(nestedURL)
            }
        }

        if let url = firstURL(in: text) ?? URL(string: text) {
            appendURLPieces(url)
        }
        if shouldScanWholeText(text) {
            append(text)
        }

        return candidates
    }

    private static func shouldScanWholeText(_ text: String) -> Bool {
        let lowercased = text.prefix(4_000).lowercased()
        return text.count <= 4_000 &&
            !lowercased.contains("<html") &&
            !lowercased.contains("<script") &&
            !lowercased.contains("af_initdatacallback")
    }

    private static func appendCoordinatePairs(
        from queryItems: [URLQueryItem],
        into candidates: inout [String],
        seen: inout Set<String>
    ) {
        func append(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            candidates.append(trimmed)
        }

        for item in queryItems where coordinateQueryNames.contains(item.name.lowercased()) {
            append(item.value)
        }

        let latitude = queryItems.first { ["lat", "latitude"].contains($0.name.lowercased()) }?.value
        let longitude = queryItems.first { ["lng", "lon", "longitude"].contains($0.name.lowercased()) }?.value
        if let latitude, let longitude {
            append("\(latitude),\(longitude)")
        }
    }

    private static func firstCoordinateMatch(in text: String) -> (latitude: Double, longitude: Double)? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = plainCoordinateMatch(in: text) {
            return match
        }

        for pattern in mapCoordinatePatterns {
            guard let match = pattern.regex.firstMatch(in: text, range: nsRange),
                  match.numberOfRanges > max(pattern.latitudeRangeIndex, pattern.longitudeRangeIndex),
                  let latRange = Range(match.range(at: pattern.latitudeRangeIndex), in: text),
                  let lngRange = Range(match.range(at: pattern.longitudeRangeIndex), in: text),
                  let latitude = Double(text[latRange]),
                  let longitude = Double(text[lngRange]),
                  isValid(latitude: latitude, longitude: longitude)
            else { continue }
            return (latitude, longitude)
        }
        return nil
    }

    private static func plainCoordinateMatch(in text: String) -> (latitude: Double, longitude: Double)? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = plainCoordinateRegex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 3,
              let latRange = Range(match.range(at: 1), in: text),
              let lngRange = Range(match.range(at: 2), in: text),
              let latitude = Double(text[latRange]),
              let longitude = Double(text[lngRange]),
              isValid(latitude: latitude, longitude: longitude)
        else { return nil }
        return (latitude, longitude)
    }

    private static func isValid(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) &&
            (-180...180).contains(longitude) &&
            !(latitude == 0 && longitude == 0)
    }

    private static func inferredName(from text: String) -> String? {
        if let url = firstURL(in: text) ?? URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let queryItems = components.queryItems {
                for name in ["q", "query", "destination", "daddr", "address"] {
                    if let value = queryItems.first(where: { $0.name.lowercased() == name })?.value,
                       let cleaned = cleanedPlaceName(value) {
                        return cleaned
                    }
                }
            }

            if let placeName = placeName(from: components) {
                return placeName
            }
        }

        let firstLine = text.components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedPlaceName(firstLine ?? "")
    }

    private static func placeName(from components: URLComponents) -> String? {
        let pathParts = components.path
            .split(separator: "/")
            .map { cleanText(String($0)) }

        if let placeIndex = pathParts.firstIndex(of: "place"),
           pathParts.indices.contains(pathParts.index(after: placeIndex)) {
            return cleanedPlaceName(pathParts[pathParts.index(after: placeIndex)])
        }

        return nil
    }

    private static func cleanedPlaceName(_ value: String) -> String? {
        let cleaned = cleanText(value)
        guard cleaned.count >= 2,
              cleaned.count <= 180,
              firstCoordinateMatch(in: cleaned) == nil
        else { return nil }

        let lowercased = cleaned.lowercased()
        guard !lowercased.hasPrefix("http"),
              !lowercased.hasPrefix("geo:"),
              !lowercased.hasPrefix("place_id:") else {
            return nil
        }
        return cleaned
    }

    private static func cleanText(_ text: String) -> String {
        (text.removingPercentEncoding ?? text)
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DestinationResolver {
    static func resolve(_ text: String) async throws -> SharedDestination {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw DestinationResolveError.emptyInput
        }

        var candidates = [sourceText]
        var shortLinkError: Error?

        if let url = DestinationParser.firstURL(in: sourceText),
           shouldExpand(url) {
            do {
                candidates.append(try await expandedText(from: url))
            } catch {
                shortLinkError = error
            }
        }

        for candidate in candidates {
            if var destination = DestinationParser.parse(candidate) {
                destination.sourceText = sourceText
                return destination
            }
        }

        for candidate in candidates {
            guard let query = DestinationParser.geocodableQuery(from: candidate) else { continue }
            if let destination = try await geocode(query, sourceText: sourceText) {
                return destination
            }
        }

        if shortLinkError != nil {
            throw DestinationResolveError.shortLink
        }
        throw DestinationResolveError.noCoordinates
    }

    private static func shouldExpand(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "maps.app.goo.gl" ||
            host == "goo.gl" ||
            host == "g.co" ||
            host.hasSuffix(".page.link")
    }

    private static func expandedText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("OpenDash-iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        var pieces: [String] = []
        if let finalURL = response.url {
            pieces.append(finalURL.absoluteString)
        }
        if !data.isEmpty {
            pieces.append(String(decoding: data.prefix(500_000), as: UTF8.self))
        }
        return pieces.joined(separator: "\n")
    }

    private static func geocode(_ query: String, sourceText: String) async throws -> SharedDestination? {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let placemark = placemarks.first,
              let coordinate = placemark.location?.coordinate
        else { return nil }

        return SharedDestination(
            name: placemark.name ?? query,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            sourceText: sourceText
        )
    }
}

enum DestinationResolveError: LocalizedError {
    case emptyInput
    case shortLink
    case noCoordinates

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Paste a Maps link first"
        case .shortLink:
            return "Could not resolve that short Maps link. Open it once and paste the full link."
        case .noCoordinates:
            return "No destination coordinates found"
        }
    }
}
