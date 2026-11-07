import Foundation

/// GPX 1.1 编解码。写入/回读均走真实文件 IO，输出固定顺序且与系统 locale / 时区无关。
public enum GPXCodec {
    public static let gpxNamespace = "http://www.topografix.com/GPX/1/1"
    public static let trackPointNamespace = "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"

    private static let creator = "PurePace RunCore"

    // MARK: - Public API

    public static func encode(_ track: GPXTrack) throws -> String {
        guard let firstPoint = track.points.first else {
            throw GPXCodecError.invalidDocument("track has no points")
        }
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append(
            "<gpx version=\"1.1\" creator=\"\(escapeXML(creator))\" "
                + "xmlns=\"\(gpxNamespace)\" xmlns:gpxtpx=\"\(trackPointNamespace)\">"
        )
        lines.append("  <metadata>")
        lines.append("    <name>\(escapeXML(track.name))</name>")
        if let description = track.description, !description.isEmpty {
            lines.append("    <desc>\(escapeXML(description))</desc>")
        }
        lines.append("    <time>\(formatTimestamp(firstPoint.timestamp))</time>")
        lines.append("  </metadata>")
        lines.append("  <trk>")
        lines.append("    <name>\(escapeXML(track.name))</name>")
        lines.append("    <type>\(escapeXML(track.activityType))</type>")
        lines.append("    <trkseg>")
        for point in track.points {
            lines.append(
                "      <trkpt lat=\"\(formatDecimal(point.latitude))\" "
                    + "lon=\"\(formatDecimal(point.longitude))\">"
            )
            if let altitude = point.altitude {
                lines.append("        <ele>\(formatDecimal(altitude))</ele>")
            }
            lines.append("        <time>\(formatTimestamp(point.timestamp))</time>")
            if point.heartRate != nil || point.cadence != nil {
                lines.append("        <extensions>")
                lines.append("          <gpxtpx:TrackPointExtension>")
                if let heartRate = point.heartRate {
                    lines.append("            <gpxtpx:hr>\(heartRate)</gpxtpx:hr>")
                }
                if let cadence = point.cadence {
                    lines.append("            <gpxtpx:cad>\(cadence)</gpxtpx:cad>")
                }
                lines.append("          </gpxtpx:TrackPointExtension>")
                lines.append("        </extensions>")
            }
            lines.append("      </trkpt>")
        }
        lines.append("    </trkseg>")
        lines.append("  </trk>")
        lines.append("</gpx>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func decode(_ data: Data) throws -> GPXTrack {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        let parsed = parser.parse()
        if let failure = delegate.failure {
            throw failure
        }
        guard parsed else {
            throw GPXCodecError.invalidDocument(
                parser.parserError?.localizedDescription ?? "unparsable XML"
            )
        }
        return try delegate.makeTrack()
    }

    public static func write(_ track: GPXTrack, to url: URL) throws {
        let document = try encode(track)
        guard let data = document.data(using: .utf8) else {
            throw GPXCodecError.ioFailure("unable to encode UTF-8 document")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw GPXCodecError.ioFailure(String(describing: error))
        }
    }

    public static func read(from url: URL) throws -> GPXTrack {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GPXCodecError.ioFailure(String(describing: error))
        }
        return try decode(data)
    }
}

// MARK: - Formatting helpers

private func escapeXML(_ value: String) -> String {
    var escaped = value.replacingOccurrences(of: "&", with: "&amp;")
    escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
    escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
    escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
    escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
    return escaped
}

private func formatDecimal(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func iso8601Formatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}

private func formatTimestamp(_ date: Date) -> String {
    iso8601Formatter().string(from: date)
}

private func parseTimestamp(_ text: String) -> Date? {
    iso8601Formatter().date(from: text)
}

// MARK: - Parser delegate

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var failure: GPXCodecError?

    private(set) var points: [RunSample] = []

    private var sawRoot = false
    private var sawTrack = false
    private var sawSegment = false
    private var inMetadata = false
    private var inTrack = false
    private var inSegment = false
    private var metadataName: String?
    private var metadataDescription: String?
    private var metadataTime: Date?
    private var trackName: String?
    private var activityType: String?
    private var pendingLatitude: Double?
    private var pendingLongitude: Double?
    private var pendingAltitude: Double?
    private var pendingTimestamp: Date?
    private var pendingHeartRate: Int?
    private var pendingCadence: Int?
    private var capture: Capture?
    private var captureText = ""

    private enum Capture {
        case metadataName
        case metadataDescription
        case trackName
        case trackType
        case elevation
        case timestamp
        case heartRate
        case cadence
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard failure == nil else {
            return
        }
        capture = nil
        captureText = ""
        switch elementName {
        case "gpx":
            guard !sawRoot else {
                reject(.invalidDocument("multiple gpx roots"), parser)
                return
            }
            guard namespaceURI == GPXCodec.gpxNamespace else {
                reject(
                    .unsupportedNamespace("default namespace is \(namespaceURI ?? "none")"),
                    parser
                )
                return
            }
            guard attributeDict["version"] == "1.1" else {
                reject(
                    .unsupportedNamespace("gpx version is \(attributeDict["version"] ?? "none")"),
                    parser
                )
                return
            }
            sawRoot = true
        case "metadata":
            guard sawRoot else {
                reject(.invalidDocument("metadata outside gpx"), parser)
                return
            }
            inMetadata = true
        case "trk":
            guard sawRoot else {
                reject(.invalidDocument("trk outside gpx"), parser)
                return
            }
            sawTrack = true
            inTrack = true
        case "trkseg":
            guard inTrack else {
                reject(.invalidDocument("trkseg outside trk"), parser)
                return
            }
            sawSegment = true
            inSegment = true
        case "trkpt":
            guard inSegment else {
                reject(.invalidDocument("trkpt outside trkseg"), parser)
                return
            }
            guard
                let latitudeText = attributeDict["lat"],
                let longitudeText = attributeDict["lon"],
                let latitude = Double(latitudeText),
                let longitude = Double(longitudeText)
            else {
                reject(
                    .invalidPoint(index: points.count, reason: "missing or unparsable lat/lon"),
                    parser
                )
                return
            }
            pendingLatitude = latitude
            pendingLongitude = longitude
            pendingAltitude = nil
            pendingTimestamp = nil
            pendingHeartRate = nil
            pendingCadence = nil
        case "name":
            if inMetadata {
                capture = .metadataName
            } else if inTrack {
                capture = .trackName
            }
        case "desc":
            if inMetadata {
                capture = .metadataDescription
            }
        case "type":
            if inTrack {
                capture = .trackType
            }
        case "ele":
            if pendingLatitude != nil {
                capture = .elevation
            }
        case "time":
            capture = .timestamp
        case "hr":
            if namespaceURI == GPXCodec.trackPointNamespace, pendingLatitude != nil {
                capture = .heartRate
            }
        case "cad":
            if namespaceURI == GPXCodec.trackPointNamespace, pendingLatitude != nil {
                capture = .cadence
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capture != nil else {
            return
        }
        captureText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard failure == nil else {
            return
        }
        if let capture {
            finishCapture(capture, parser: parser)
            self.capture = nil
            captureText = ""
        }
        switch elementName {
        case "metadata":
            inMetadata = false
        case "trkseg":
            inSegment = false
        case "trk":
            inTrack = false
        case "trkpt":
            finishPoint(parser: parser)
        default:
            break
        }
    }

    // MARK: Result

    func makeTrack() throws -> GPXTrack {
        guard sawRoot else {
            throw GPXCodecError.invalidDocument("missing gpx root")
        }
        guard sawTrack, sawSegment else {
            throw GPXCodecError.missingTrack("missing trk/trkseg")
        }
        guard !points.isEmpty else {
            throw GPXCodecError.missingTrack("missing trkpt")
        }
        var name = trackName ?? ""
        if name.isEmpty {
            name = metadataName ?? ""
        }
        guard !name.isEmpty else {
            throw GPXCodecError.invalidDocument("missing track name")
        }
        guard
            let track = GPXTrack(
                name: name,
                description: metadataDescription,
                createdAt: metadataTime ?? points[0].timestamp,
                activityType: activityType ?? "",
                points: points
            )
        else {
            throw GPXCodecError.invalidDocument("invalid track")
        }
        return track
    }

    // MARK: Internals

    private func finishCapture(_ capture: Capture, parser: XMLParser) {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch capture {
        case .metadataName:
            metadataName = text
        case .metadataDescription:
            metadataDescription = text
        case .trackName:
            trackName = text
        case .trackType:
            activityType = text
        case .elevation:
            guard let altitude = Double(text) else {
                reject(
                    .invalidPoint(index: points.count, reason: "unparsable ele"),
                    parser
                )
                return
            }
            pendingAltitude = altitude
        case .timestamp:
            guard let timestamp = parseTimestamp(text) else {
                if pendingLatitude != nil {
                    reject(
                        .invalidPoint(index: points.count, reason: "unparsable time"),
                        parser
                    )
                }
                return
            }
            if pendingLatitude != nil {
                pendingTimestamp = timestamp
            } else {
                metadataTime = timestamp
            }
        case .heartRate:
            guard let heartRate = Int(text) else {
                reject(
                    .invalidPoint(index: points.count, reason: "unparsable hr"),
                    parser
                )
                return
            }
            pendingHeartRate = heartRate
        case .cadence:
            guard let cadence = Int(text) else {
                reject(
                    .invalidPoint(index: points.count, reason: "unparsable cad"),
                    parser
                )
                return
            }
            pendingCadence = cadence
        }
    }

    private func finishPoint(parser: XMLParser) {
        guard let latitude = pendingLatitude, let longitude = pendingLongitude else {
            reject(.invalidPoint(index: points.count, reason: "missing lat/lon"), parser)
            return
        }
        guard let timestamp = pendingTimestamp else {
            reject(.invalidPoint(index: points.count, reason: "missing time"), parser)
            return
        }
        guard
            let sample = RunSample(
                latitude: latitude,
                longitude: longitude,
                altitude: pendingAltitude,
                timestamp: timestamp,
                heartRate: pendingHeartRate,
                cadence: pendingCadence
            )
        else {
            reject(.invalidPoint(index: points.count, reason: "values out of range"), parser)
            return
        }
        if let last = points.last, sample.timestamp < last.timestamp {
            reject(.invalidPoint(index: points.count, reason: "timestamp decreases"), parser)
            return
        }
        points.append(sample)
        pendingLatitude = nil
        pendingLongitude = nil
        pendingAltitude = nil
        pendingTimestamp = nil
        pendingHeartRate = nil
        pendingCadence = nil
    }

    private func reject(_ error: GPXCodecError, _ parser: XMLParser) {
        if failure == nil {
            failure = error
        }
        parser.abortParsing()
    }
}
