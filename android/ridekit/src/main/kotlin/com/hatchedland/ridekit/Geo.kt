package com.hatchedland.ridekit

import java.util.Locale
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlin.math.sqrt

// Twin of ios/Packages/RideKit/Sources/RideKit/Geo/Coordinate.swift.
// Times in RideKit for Android are Unix seconds (Double), as in spec/fixtures.

/** A WGS-84 latitude/longitude pair. */
data class Coordinate(val latitude: Double, val longitude: Double) {

    val isValid: Boolean
        get() = latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0

    /** Great-circle distance in meters (haversine), exactly as the Swift RideKit. */
    fun distanceTo(other: Coordinate): Double {
        val lat1 = latitude * Math.PI / 180
        val lat2 = other.latitude * Math.PI / 180
        val dLat = lat2 - lat1
        val dLon = (other.longitude - longitude) * Math.PI / 180
        val a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_RADIUS * atan2(sqrt(a), sqrt(1 - a))
    }

    /** Linear interpolation; fine at the scale of consecutive GPS fixes. */
    fun interpolated(to: Coordinate, fraction: Double): Coordinate = Coordinate(
        latitude + (to.latitude - latitude) * fraction,
        longitude + (to.longitude - longitude) * fraction,
    )

    /** "28.613900,77.209000" — 6 decimals is ~0.1 m. */
    val queryString: String get() = "${format(latitude)},${format(longitude)}"

    companion object {
        const val EARTH_RADIUS = 6_371_008.8

        internal fun format(value: Double): String {
            val s = String.format(Locale.ROOT, "%.6f", value)
            return if (s == "-0.000000") "0.000000" else s
        }
    }
}

/** The element nearest to [coordinate] within [radius] meters, if any (the first one on a tie). */
fun <T> Iterable<T>.nearest(coordinate: Coordinate, radius: Double, by: (T) -> Coordinate): Pair<T, Double>? {
    var best: Pair<T, Double>? = null
    for (element in this) {
        val d = by(element).distanceTo(coordinate)
        if (d <= radius && d < (best?.second ?: Double.POSITIVE_INFINITY)) best = element to d
    }
    return best
}

/** Swift's `rounded()`: to nearest, halves away from zero (Kotlin's `round` rounds halves to even). */
internal fun Double.roundedAwayFromZero(): Double = if (this >= 0) floor(this + 0.5) else ceil(this - 0.5)
