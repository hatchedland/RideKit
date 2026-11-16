import SwiftUI

/// How every map in the app shows what a pin is: a drawer from the bottom, never a new page.
///
/// - Tapping a pin opens it at a short **peek**; the map above stays usable.
/// - Dragging it up, or scrolling its content, takes it **full screen**.
/// - Tapping the header while full slides it back to the peek; tapping it at the peek opens it full.
/// - Tapping empty map (`GoogleMapView.onTapMap`) or swiping it down closes it.
///
/// From a list (no map to keep in view) pass `startsExpanded: true`: it opens full screen straight away.
extension View {
    func mapDrawer<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        startsExpanded: Bool = false,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item) { item in
            MapDrawerContainer(startsExpanded: startsExpanded) { content(item) }
        }
    }
}

/// The peek height: enough for a title, a line of details and one row of actions.
private let peek = PresentationDetent.fraction(0.36)

private struct MapDrawerContainer<Content: View>: View {
    @State private var detent: PresentationDetent
    private let content: Content

    init(startsExpanded: Bool, @ViewBuilder content: () -> Content) {
        _detent = State(initialValue: startsExpanded ? .large : peek)
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.mapDrawerToggle, MapDrawerToggle { detent = detent == .large ? peek : .large })
            .presentationDetents([peek, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            // At the peek the map behind stays live, so a tap on empty map can close the drawer.
            .presentationBackgroundInteraction(.enabled(upThrough: peek))
            // Scrolling the content first grows the drawer to full screen.
            .presentationContentInteraction(.resizes)
    }
}

/// Lets a drawer's header slide it between the peek and full screen.
struct MapDrawerToggle {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var mapDrawerToggle = MapDrawerToggle()
}

/// The standard drawer header: title, a line of details, and an optional trailing control.
/// Tapping it toggles peek ↔ full screen.
struct MapDrawerHeader<Trailing: View>: View {
    let title: String
    /// Makes the title a text field (e.g. a spot's name); `title` is then the placeholder.
    var editableTitle: Binding<String>?
    /// Focus of the editable title, so the drawer's content can react to renaming.
    var titleFocus: FocusState<Bool>.Binding?
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var trailing: Trailing
    @Environment(\.mapDrawerToggle) private var toggle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage {
                Image(icon: systemImage)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let editableTitle {
                    let field = TextField(title, text: editableTitle, axis: .vertical)
                        .font(.title3.bold())
                        .lineLimit(1...2)
                        .submitLabel(.done)
                        .accessibilityLabel("Name")
                    if let titleFocus { field.focused(titleFocus) } else { field }
                } else {
                    Text(title).font(.title3.bold()).lineLimit(2)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .contentShape(.rect)
        .onTapGesture { toggle() }
        .accessibilityAddTraits(.isHeader)
        .accessibilityAction(named: "Expand or collapse") { toggle() }
    }
}

extension MapDrawerHeader where Trailing == EmptyView {
    init(title: String, editableTitle: Binding<String>? = nil, titleFocus: FocusState<Bool>.Binding? = nil,
         subtitle: String? = nil, systemImage: String? = nil) {
        self.init(title: title, editableTitle: editableTitle, titleFocus: titleFocus, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}
