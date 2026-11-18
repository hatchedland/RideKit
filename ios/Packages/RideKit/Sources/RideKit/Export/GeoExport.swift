import Foundation

/// A spot as it appears in an export file.
public struct ExportSpot: Sendable {
    public var name: String
    public var notes: String
    public var category: String
    public var visited: Bool
    public var coordinate: Coordinate
    public var googleMapsURL: URL

    public init(name: String, notes: String = "", category: String = "", visited: Bool,
                coordinate: Coordinate, googleMapsURL: URL? = nil) {
        self.name = name
        self.notes = notes
        self.category = category
        self.visited = visited
        self.coordinate = coordinate
        self.googleMapsURL = googleMapsURL ?? GoogleMapsLink.url(for: coordinate)
    }
}

public enum GeoExport {

    /// GPX 1.1: the ride's track plus its spots as waypoints. Opens in most riding/navigation apps.
    public static func gpx(name: String, track: [TrackPoint], spots: [ExportSpot]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Ride Tracker" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(name))</name></metadata>

        """
        for spot in spots {
            xml += """
              <wpt lat="\(Coordinate.format(spot.coordinate.latitude))" lon="\(Coordinate.format(spot.coordinate.longitude))">
                <name>\(escape(spot.name))</name>
                <desc>\(escape(spot.notes))</desc>
                <link href="\(escape(spot.googleMapsURL.absoluteString))"/>
                <type>\(escape(spot.category))</type>
              </wpt>

            """
        }
        if !track.isEmpty {
            xml += "  <trk><name>\(escape(name))</name><trkseg>\n"
            let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
            for p in track {
                xml += "    <trkpt lat=\"\(Coordinate.format(p.coordinate.latitude))\" lon=\"\(Coordinate.format(p.coordinate.longitude))\">"
                if let alt = p.altitude { xml += "<ele>\(String(format: "%.1f", alt))</ele>" }
                xml += "<time>\(p.timestamp.formatted(iso))</time></trkpt>\n"
            }
            xml += "  </trkseg></trk>\n"
        }
        xml += "</gpx>\n"
        return xml
    }

    /// KML with one folder per status. Import it at mymaps.google.com to see the spots in Google Maps.
    public static func kml(name: String, spots: [ExportSpot]) -> String {
        func placemarks(_ list: [ExportSpot]) -> String {
            list.map { spot in
                let description = [spot.notes, spot.googleMapsURL.absoluteString]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                return """
                      <Placemark>
                        <name>\(escape(spot.name))</name>
                        <description>\(escape(description))</description>
                        <Point><coordinates>\(Coordinate.format(spot.coordinate.longitude)),\(Coordinate.format(spot.coordinate.latitude)),0</coordinates></Point>
                      </Placemark>

                """
            }.joined()
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>\(escape(name))</name>
            <Folder>
              <name>Visited</name>
        \(placemarks(spots.filter(\.visited)))    </Folder>
            <Folder>
              <name>Want to go</name>
        \(placemarks(spots.filter { !$0.visited }))    </Folder>
          </Document>
        </kml>

        """
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
