import RideKit
import SwiftUI

/// Before a ride: "can I ride now?" — the weather here as a 3D illustration, one line about the
/// hours ahead (the same words the riding alerts use) and a strip of the next hours.
struct PreRideWeatherCard: View {
    /// `nil` while loading; empty when the forecast couldn't be fetched.
    let forecast: [WeatherHour]?

    var body: some View {
        Group {
            if let forecast, let now = WeatherAlerts.current(forecast, now: .now) ?? forecast.first {
                content(now: now, forecast: forecast)
            } else if forecast == nil {
                placeholder
            } else {
                // Offline or no key: say so quietly instead of leaving a hole.
                Label("Weather unavailable right now", systemImage: "cloud.slash")
                    .font(.subheadline)
                    .foregroundStyle(Brand.chalk.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background {
            ZStack {
                Brand.asphalt
                if let now = forecast.flatMap({ WeatherAlerts.current($0, now: .now) ?? $0.first }) {
                    WeatherAmbience(sky: now.sky, isDaytime: now.isDaytime ?? true)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.chalk.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }

    private func content(now: WeatherHour, forecast: [WeatherHour]) -> some View {
        let time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
        let outlook = WeatherAlerts.outlook(forecast, now: .now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(now.sky.illustration(isDaytime: now.isDaytime ?? true))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(.vertical, -8)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let temperature = now.temperature {
                            Text("\(Int(temperature.rounded()))°").font(Brand.readout(34))
                        }
                        Text(now.sky.word).font(.headline).foregroundStyle(Brand.chalk.opacity(0.8))
                    }
                    Text(outlook.map { $0.text(time: time, distance: { Format.distance($0) }) } ?? "Dry for the next few hours")
                        .font(.subheadline)
                        .foregroundStyle(outlook == nil ? Brand.chalk.opacity(0.6) : Brand.chalk)
                        .lineLimit(2)
                }
                .foregroundStyle(Brand.chalk)
                Spacer(minLength: 0)
            }
            let hours = forecast.filter { $0.end > .now }.prefix(6)
            if hours.count > 1 {
                HStack(spacing: 0) {
                    ForEach(Array(hours), id: \.start) { hour in
                        VStack(spacing: 2) {
                            // Google's hours often run :30 to :30; name each by its middle ("2 PM"
                            // for 1:30–2:30), and the one we're in as "Now".
                            Text(hour.start <= .now ? "Now" : hour.start.addingTimeInterval(1_800).formatted(.dateTime.hour()))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Brand.chalk.opacity(0.6))
                            Image(hour.sky.illustration(isDaytime: hour.isDaytime ?? true))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                            Text(hour.temperature.map { "\(Int($0.rounded()))°" } ?? "–")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.chalk)
                            if hour.rainChance >= 30 {
                                Text("\(hour.rainChance)%").font(.caption2).foregroundStyle(Brand.Sky.drop)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Weather from Google")
                .font(.caption2)
                .foregroundStyle(Brand.chalk.opacity(0.4))
        }
        .accessibilityElement(children: .contain)
    }

    private var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16).fill(Brand.chalk.opacity(0.08)).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Brand.chalk.opacity(0.08)).frame(width: 120, height: 20)
                RoundedRectangle(cornerRadius: 4).fill(Brand.chalk.opacity(0.06)).frame(width: 180, height: 14)
            }
            Spacer()
        }
        .shimmering()
        .accessibilityLabel("Loading the weather")
    }
}

/// "Where should I go?": the nearest wishlist spots as one-tap destinations. Empty wishlist gets a
/// quiet pointer to Spots, never an empty box.
struct NearbyWishlist: View {
    let suggestions: [DestinationSuggestions.Suggestion]
    let categories: [UUID: String]
    var onPick: (RideDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEARBY ON YOUR WISHLIST")
                .font(Brand.label)
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            if suggestions.isEmpty {
                Text("Places you want to ride to show up here. Add them in Spots.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.card, in: .rect(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                        if index > 0 { Divider().padding(.leading, 52) }
                        row(suggestion)
                    }
                }
                .background(Brand.card, in: .rect(cornerRadius: 16))
            }
        }
    }

    private func row(_ suggestion: DestinationSuggestions.Suggestion) -> some View {
        Button { onPick(suggestion.destination) } label: {
            HStack(spacing: 12) {
                Image(icon: suggestion.destination.spotID.flatMap { categories[$0] } ?? "category-other")
                    .foregroundStyle(Brand.asphalt)
                    .frame(width: 28, height: 28)
                    .background(Brand.highwayYellow, in: .circle)
                Text(suggestion.destination.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let distance = suggestion.distance {
                    Text(Format.distance(distance))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.destination.name)\(suggestion.distance.map { ", \(Format.distance($0)) away" } ?? "")")
        .accessibilityHint("Start a ride there")
    }
}
