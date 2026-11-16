import SwiftData
import SwiftUI

struct RidesListView: View {
    @Query(sort: \Ride.startedAt, order: .reverse) private var rides: [Ride]
    @Environment(RideRecorder.self) private var recorder
    @State private var path: [Ride] = []

    private var finished: [Ride] {
        rides.filter { $0.id != recorder.active?.id }
    }

    private var byMonth: [(month: Date, rides: [Ride])] {
        let calendar = Calendar.current
        return Dictionary(grouping: finished) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
            .map { ($0.key, $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                    ForEach(byMonth, id: \.month) { group in
                        let meters = group.rides.reduce(0) { $0 + $1.distanceMeters }
                        let distance = Format.distanceParts(meters)
                        RoadHeader(title: group.month.formatted(.dateTime.month(.wide).year()),
                                   trailing: "\(distance.value) \(distance.unit)",
                                   accessibilityText: "\(group.month.formatted(.dateTime.month(.wide).year())), \(Format.distance(meters))")
                        ForEach(group.rides) { ride in
                            NavigationLink(value: ride) { RideCard(ride: ride) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Brand.page)
            .overlay {
                if finished.isEmpty {
                    ContentUnavailableView("No rides yet", systemImage: "road.lanes",
                                           description: Text("Your rides, their spots and photo albums show up here."))
                }
            }
            .navigationTitle("Rides")
            .navigationDestination(for: Ride.self) { RideDetailView(ride: $0) }
            #if DEBUG
            .task {
                if SampleRide.requested, path.isEmpty, let sample = finished.first(where: { $0.name == SampleRide.name }) {
                    path = [sample]
                }
            }
            #endif
            .navigationDestination(for: Spot.self) { SpotDetailView(spot: $0) }
        }
    }
}

/// "NOVEMBER 2026 – – – – 166 KM": a signboard label with the road's dashed centre line.
/// Shared by every journal list (rides by month, spots by area).
struct RoadHeader: View {
    let title: String
    let trailing: String
    var accessibilityText: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Line()
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 6]))
                .foregroundStyle(Brand.accent.opacity(0.6))
                .frame(minWidth: 24, maxHeight: 2)
            Text(trailing.uppercased())
                .lineLimit(1)
                .fixedSize()
        }
        .font(Brand.label)
        .tracking(0.8)
        .foregroundStyle(.secondary)
        // Lines up with the stones inside the cards; closer to its own cards than to the ones above.
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? "\(title), \(trailing)")
        .accessibilityAddTraits(.isHeader)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// A ride as a kilometre stone: the distance on the stone, the ride's own shape beside it.
struct RideCard: View {
    let ride: Ride

    var body: some View {
        // 4 pt grid: 16 padding, 12 between columns; name + date grouped (4), stats apart (8).
        HStack(alignment: .center, spacing: 12) {
            DistanceStone(meters: ride.distanceMeters)
                .frame(width: 56, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ride.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(dateLine)
                        .font(Brand.label)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                if let destination = ride.destinationName, !ride.name.localizedStandardContains(destination) {
                    Label(destination, systemImage: ride.destinationReachedAt == nil ? "flag" : "flag.checkered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Small metadata: standard width and secondary grey so it stays ≥ 12 pt and ≥ 4.5:1.
                Text(stats)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RouteSketch(ride: ride)
                .frame(width: 56, height: 56)
        }
        .padding(16)
        .background(Brand.card, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "SUN 15 NOV · 6:00 AM"
    private var dateLine: String {
        let day = ride.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .replacingOccurrences(of: ",", with: "")
        return "\(day) · \(ride.startedAt.formatted(date: .omitted, time: .shortened))".uppercased()
    }

    /// "4H 07M": signboard-short, so the stats fit on one line.
    private var time: String {
        let minutes = Int((ride.duration / 60).rounded())
        return minutes >= 60 ? String(format: "%dH %02dM", minutes / 60, minutes % 60) : "\(max(1, minutes))M"
    }

    /// "4H 07M · 6 STOPS · 8 PHOTOS": counts that matter, nothing at zero.
    private var stats: String {
        var parts = [time]
        let spots = ride.spots?.count ?? 0, photos = ride.media?.count ?? 0
        if spots > 0 { parts.append("\(spots) \(spots == 1 ? "STOP" : "STOPS")") }
        if photos > 0 { parts.append("\(photos) \(photos == 1 ? "PHOTO" : "PHOTOS")") }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var text = "\(ride.name), \(Format.distance(ride.distanceMeters)), \(ride.startedAt.formatted(date: .abbreviated, time: .shortened))"
        if let destination = ride.destinationName { text += ", to \(destination)" }
        return text + ", " + stats.lowercased()
    }
}

/// The km-stone with a distance on it: yellow cap reading "KM", chalk body, asphalt text.
struct DistanceStone: View {
    let meters: Double

    /// The stone is a real 3D render (design/make-stone-3d.swift → Assets › DistanceStone); the
    /// distance is written on its front face here. These are where that script reports the face
    /// lands in the image (0–1) and how far the stone is turned.
    private enum Face {
        static let left = 0.039, right = 0.708
        static let seam = 0.433, bottom = 0.872
        static let yaw = Angle.radians(-0.42)
    }

    var body: some View {
        let distance = Format.distanceParts(meters)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let centerX = w * (Face.left + Face.right) / 2
            let faceWidth = w * (Face.right - Face.left)
            ZStack(alignment: .topLeading) {
                Image("DistanceStone")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: w, height: h)
                Group {
                    Text(distance.unit)
                        .font(.system(size: h * 0.105, weight: .heavy).width(.expanded))
                        .frame(width: faceWidth)
                        .position(x: centerX, y: h * 0.345)
                    Text(distance.value)
                        .font(.system(size: h * 0.2, weight: .heavy).width(.expanded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(width: faceWidth * 0.88)
                        .position(x: centerX, y: h * (Face.seam + Face.bottom) / 2)
                }
                .foregroundStyle(Brand.asphalt.opacity(0.92))
                // Turned with the stone, so the paint sits on its face rather than floating in front.
                .rotation3DEffect(Face.yaw, axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: Face.left, y: 0.5), perspective: 0.4)
            }
        }
        .aspectRatio(420.0 / 540.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The ride's real shape, drawn small. Tracks are decoded once and shrunk to ~60 points.
private struct RouteSketch: View {
    let ride: Ride
    @State private var points: [CGPoint] = []

    var body: some View {
        ZStack {
            SketchLine(points: points)
                .stroke(Brand.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if let first = points.first {
                GeometryReader { geo in
                    Circle()
                        .fill(Brand.accent)
                        .frame(width: 7, height: 7)
                        .position(x: first.x * geo.size.width, y: first.y * geo.size.height)
                }
            }
        }
        .task(id: ride.id) { points = RouteSketchCache.points(for: ride) }
        .accessibilityHidden(true)
    }

    private struct SketchLine: Shape {
        let points: [CGPoint]
        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard points.count > 1 else { return path }
            path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
            return path
        }
    }
}

@MainActor
private enum RouteSketchCache {
    private static var cache: [UUID: [CGPoint]] = [:]

    /// Points scaled into a unit square, keeping the route's aspect ratio and north up.
    static func points(for ride: Ride) -> [CGPoint] {
        if let cached = cache[ride.id] { return cached }
        let track = ride.decodedTrack()
        guard track.count > 1 else { return [] }
        let step = max(1, track.count / 60)
        let sampled = stride(from: 0, to: track.count, by: step).map { track[$0].coordinate } + [track[track.count - 1].coordinate]
        // Longitude degrees shrink with latitude; scale them so the shape isn't stretched.
        let lonScale = cos((sampled.map(\.latitude).reduce(0, +) / Double(sampled.count)) * .pi / 180)
        let xs = sampled.map { $0.longitude * lonScale }, ys = sampled.map(\.latitude)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let span = max(maxX - minX, maxY - minY, 1e-9)
        let padX = (span - (maxX - minX)) / 2, padY = (span - (maxY - minY)) / 2
        let result = zip(xs, ys).map { x, y in
            CGPoint(x: 0.08 + 0.84 * (x - minX + padX) / span, y: 0.08 + 0.84 * (1 - (y - minY + padY) / span))
        }
        cache[ride.id] = result
        return result
    }
}
