import SwiftUI

/// A grey stand-in for text or a picture that's still loading.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 4
    /// Blocks on the always-dark surfaces (riding screen, dashboard, photo viewer) use chalk.
    var onDark = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(onDark ? Brand.chalk.opacity(0.08) : Color.secondary.opacity(0.15))
            .frame(width: width, height: height)
            .shimmering()
    }
}

extension View {
    /// A soft highlight sweeping across the view while `active`. Still when Reduce Motion is on.
    func shimmering(_ active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}

private struct Shimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let period: TimeInterval = 1.4

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.period) / Self.period
                    GeometryReader { proxy in
                        let band = max(proxy.size.width * 0.6, 40)
                        LinearGradient(
                            colors: [.clear, highlight, .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: -band + phase * (proxy.size.width + band))
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }

    private var highlight: Color {
        colorScheme == .dark ? Brand.chalk.opacity(0.10) : .white.opacity(0.55)
    }
}

/// Placeholder rows for the Friends tab's first load, shaped like `FriendRideRow`.
struct FriendsSkeletonList: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 12) {
                        SkeletonBlock(width: 56, height: 56, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: index.isMultiple(of: 2) ? 170 : 130, height: 16)
                            SkeletonBlock(width: 110, height: 12)
                            SkeletonBlock(width: 80, height: 10)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SkeletonBlock(width: 90, height: 10)
            }
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading friends")
    }
}
