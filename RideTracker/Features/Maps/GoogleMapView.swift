@preconcurrency import GoogleMaps
import RideKit
import SwiftUI

/// A line on the map (a route, or one speed-coloured piece of it). Later lines draw on top.
struct MapLine: Equatable {
    var id: String
    var coordinates: [Coordinate]
    var color: Color
    var width: CGFloat
}

/// A marker on the map, drawn by `MapPinRenderer` so it matches the app's look on every screen.
struct MapPin: Equatable, Identifiable {
    enum Style: Equatable {
        /// A balloon with a symbol, like a place pin. Used for spots, stops, start and end.
        case balloon
        /// A small round badge, e.g. a photo taken away from any spot.
        case badge
        /// A round marker with a dark ring, e.g. a friend riding live.
        case rider
    }

    var id: String
    var coordinate: Coordinate
    var title: String
    var systemImage: String
    var tint: Color
    var style: Style = .balloon
    /// Draws the title under the marker (Google Maps only shows titles on tap otherwise).
    var showsLabel: Bool = true
}

/// Where the map looks.
enum MapCameraMode: Equatable {
    /// Fit every line and marker once the map has a size; the rider's location if there's nothing to show.
    case fitContent
    /// A fixed place at a Google zoom level (15 ≈ a few streets, 10 ≈ a city).
    case center(Coordinate, zoom: Float)
    /// Centre on the rider's location once it's known.
    case userLocation
    /// Keep following `coordinate` (the newest GPS fix), turned to `bearing`. Pauses for a few
    /// seconds after the rider pans the map.
    case follow(Coordinate?, bearing: Double?)
}

/// The two looks used in the app. Points of interest are always hidden: the rider's own spots
/// are what matters on these maps.
enum MapLook: Equatable {
    case standard
    /// Desaturated, so the route and the yellow pins carry the colour.
    case muted
}

/// Google Maps for SwiftUI. Every map in the app is one of these.
/// Without an API key (see `Config/Secrets.example.xcconfig`) it shows a placeholder instead,
/// because the SDK stops the app if a map is created without one.
struct GoogleMapView: View {
    var lines: [MapLine] = []
    var pins: [MapPin] = []
    var camera: MapCameraMode = .fitContent
    var look: MapLook = .standard
    var showsUserLocation = false
    var showsLocationButton = false
    var showsCompass = false
    var isInteractive = true
    /// Room for overlays (cards, badges) so the controls and the Google logo stay visible.
    var padding = UIEdgeInsets()
    var onTapPin: ((String) -> Void)?
    var onLongPress: ((Coordinate) -> Void)?
    /// A tap on the map itself, not on a pin; closes a peeking `mapDrawer`.
    var onTapMap: (() -> Void)?

    var body: some View {
        if GoogleMapsSetup.hasKey {
            GoogleMapCanvas(map: self)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Label("Add a Google Maps API key to Config/Secrets.xcconfig to show the map.", systemImage: "map")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

private struct GoogleMapCanvas: UIViewRepresentable {
    let map: GoogleMapView

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        GoogleMapsSetup.configureIfNeeded()
        let options = GMSMapViewOptions()
        options.backgroundColor = UIColor(colorScheme == .dark ? Brand.asphalt : Brand.chalk)
        if case .center(let coordinate, let zoom) = map.camera {
            options.camera = GMSCameraPosition(target: coordinate.clCoordinate, zoom: zoom)
        }
        let view = GMSMapView(options: options)
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = map
        // Only touch what changed: setting padding or the controls again (even to the same value)
        // makes the map lay itself out, which makes SwiftUI update it again, forever.
        let dark = colorScheme == .dark
        let settings = Coordinator.Settings(dark: dark, look: map.look, showsUserLocation: map.showsUserLocation,
                                            showsLocationButton: map.showsLocationButton, showsCompass: map.showsCompass,
                                            isInteractive: map.isInteractive, padding: map.padding)
        if coordinator.appliedSettings != settings {
            let previous = coordinator.appliedSettings
            coordinator.appliedSettings = settings
            if previous?.dark != dark { view.overrideUserInterfaceStyle = dark ? .dark : .light }
            if previous?.dark != dark || previous?.look != map.look {
                view.mapStyle = MapStyles.style(look: map.look, dark: dark)
            }
            if previous?.showsUserLocation != map.showsUserLocation { view.isMyLocationEnabled = map.showsUserLocation }
            if previous?.showsLocationButton != map.showsLocationButton { view.settings.myLocationButton = map.showsLocationButton }
            if previous?.showsCompass != map.showsCompass { view.settings.compassButton = map.showsCompass }
            if previous?.isInteractive != map.isInteractive { view.settings.setAllGesturesEnabled(map.isInteractive) }
            if previous == nil {
                view.settings.indoorPicker = false
                view.isIndoorEnabled = false
            }
            if previous?.padding != map.padding { view.padding = map.padding }
        }
        coordinator.update(lines: map.lines, in: view)
        coordinator.update(pins: map.pins, in: view)
        coordinator.applyCamera(map.camera, in: view)
    }

    static func dismantleUIView(_ view: GMSMapView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency GMSMapViewDelegate {
        struct Settings: Equatable {
            var dark: Bool
            var look: MapLook
            var showsUserLocation: Bool
            var showsLocationButton: Bool
            var showsCompass: Bool
            var isInteractive: Bool
            var padding: UIEdgeInsets
        }

        var parent: GoogleMapView?
        var appliedSettings: Settings?
        private var lines: [String: (line: MapLine, polylines: GMSPolyline)] = [:]
        private var markers: [String: (pin: MapPin, marker: GMSMarker)] = [:]
        private var hasPlacedCamera = false
        private var lastFollowGesture: Date = .distantPast
        private var locationObservation: NSKeyValueObservation?
        private weak var view: GMSMapView?

        /// After the rider pans a following map, wait this long before following again.
        private let followPause: TimeInterval = 8

        func attach(to view: GMSMapView) {
            self.view = view
            // The map's own location fix places a `.userLocation` / `.fitContent` camera that has nothing else to show.
            locationObservation = view.observe(\.myLocation, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let view = self.view, let parent = self.parent else { return }
                    self.applyCamera(parent.camera, in: view)
                }
            }
        }

        func detach() {
            locationObservation?.invalidate()
            locationObservation = nil
        }

        // MARK: Lines

        func update(lines newLines: [MapLine], in view: GMSMapView) {
            let wanted = Set(newLines.map(\.id))
            for (id, entry) in lines where !wanted.contains(id) {
                entry.polylines.map = nil
                lines[id] = nil
            }
            for (index, line) in newLines.enumerated() {
                if let existing = lines[line.id] {
                    guard existing.line != line else { continue }
                    let polyline = existing.polylines
                    // The live route only grows: append the new fixes instead of rebuilding the path.
                    if let path = polyline.path as? GMSMutablePath,
                       line.coordinates.count > existing.line.coordinates.count,
                       line.coordinates.starts(with: existing.line.coordinates),
                       line.color == existing.line.color, line.width == existing.line.width {
                        for coordinate in line.coordinates.dropFirst(existing.line.coordinates.count) {
                            path.add(coordinate.clCoordinate)
                        }
                        polyline.path = path
                    } else {
                        style(polyline, as: line, index: index)
                    }
                    lines[line.id] = (line, polyline)
                } else {
                    let polyline = GMSPolyline()
                    style(polyline, as: line, index: index)
                    polyline.map = view
                    lines[line.id] = (line, polyline)
                }
            }
        }

        private func style(_ polyline: GMSPolyline, as line: MapLine, index: Int) {
            let path = GMSMutablePath()
            line.coordinates.forEach { path.add($0.clCoordinate) }
            polyline.path = path
            polyline.strokeColor = UIColor(line.color)
            polyline.strokeWidth = line.width
            polyline.zIndex = Int32(index)
            polyline.isTappable = false
        }

        // MARK: Pins

        func update(pins newPins: [MapPin], in view: GMSMapView) {
            let wanted = Set(newPins.map(\.id))
            for (id, entry) in markers where !wanted.contains(id) {
                entry.marker.map = nil
                markers[id] = nil
            }
            let dark = view.overrideUserInterfaceStyle == .dark
            for (index, pin) in newPins.enumerated() {
                let marker = markers[pin.id]?.marker ?? GMSMarker()
                if markers[pin.id]?.pin != pin || marker.map == nil {
                    let rendered = MapPinRenderer.image(for: pin, dark: dark)
                    marker.position = pin.coordinate.clCoordinate
                    marker.icon = rendered.image
                    marker.groundAnchor = rendered.anchor
                    // The title is read by VoiceOver; taps are handled in `didTap`, so no info window opens.
                    marker.title = pin.title
                    marker.zIndex = Int32(1_000 + index)
                    marker.tracksViewChanges = false
                    marker.map = view
                }
                markers[pin.id] = (pin, marker)
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = markers.first(where: { $0.value.marker === marker })?.key {
                parent?.onTapPin?(id)
            }
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent?.onTapMap?()
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            parent?.onLongPress?(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { lastFollowGesture = .now }
        }

        // MARK: Camera

        func applyCamera(_ mode: MapCameraMode, in view: GMSMapView) {
            switch mode {
            case .center:
                hasPlacedCamera = true   // set in makeUIView
            case .fitContent:
                guard !hasPlacedCamera else { return }
                let points = lines.values.flatMap(\.line.coordinates) + markers.values.map(\.pin.coordinate)
                if points.isEmpty {
                    placeOnUser(view)
                    return
                }
                guard view.bounds.width > 0 else {
                    // Not laid out yet: SwiftUI calls update again once it has a size.
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view, let parent = self.parent else { return }
                        self.applyCamera(parent.camera, in: view)
                    }
                    return
                }
                hasPlacedCamera = true
                if points.count == 1 || Set(points).count == 1 {
                    view.camera = GMSCameraPosition(target: points[0].clCoordinate, zoom: 15)
                } else {
                    var bounds = GMSCoordinateBounds()
                    points.forEach { bounds = bounds.includingCoordinate($0.clCoordinate) }
                    view.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 48))
                }
            case .userLocation:
                guard !hasPlacedCamera else { return }
                placeOnUser(view)
            case .follow(let coordinate, let bearing):
                guard Date.now.timeIntervalSince(lastFollowGesture) > followPause else { return }
                guard let target = coordinate?.clCoordinate ?? view.myLocation?.coordinate else { return }
                // Placing the camera before the map has a size leaves it at world zoom for good.
                guard view.bounds.width > 0, view.bounds.height > 0 else { return }
                // Continent scale is never what a rider wants while being followed (it happens if the
                // first placement was made mid-layout); come back to street level.
                let zoom = hasPlacedCamera && view.camera.zoom >= 10 ? view.camera.zoom : 16
                let position = GMSCameraPosition(target: target, zoom: zoom, bearing: bearing ?? view.camera.bearing, viewingAngle: 0)
                if hasPlacedCamera { view.animate(to: position) } else { view.camera = position }
                hasPlacedCamera = true
            }
        }

        private func placeOnUser(_ view: GMSMapView) {
            guard let location = view.myLocation else { return }
            hasPlacedCamera = true
            view.camera = GMSCameraPosition(target: location.coordinate, zoom: 13)
        }
    }
}
