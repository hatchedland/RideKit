package com.hatchedland.ridekit

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

// Twin of Spots/FamousPlaces.swift (and the Place type of Spots/GooglePlaces.swift).

/** A place from Google Places, reduced to what the app uses. */
data class Place(
    val name: String,
    val coordinate: Coordinate,
    val primaryType: String? = null,
    val types: List<String> = emptyList(),
    val address: String? = null,
    /** Google's place id; only requested by the famous-places search. */
    val id: String? = null,
    val rating: Double? = null,
    val ratingCount: Int? = null,
)

/** Well-reviewed sights within 2 km and not behind the rider, announced passively, 3 at a time. */
object FamousPlaces {
    const val ALERT_DISTANCE = 2_000.0
    const val ANNOUNCE_LIMIT = 3
    const val MINIMUM_REVIEWS = 500
    const val MINIMUM_RATING = 4.0
    const val SEARCH_RADIUS = 5_000.0
    const val SEARCH_SPACING = 3_000.0
    const val AHEAD_ANGLE = 90.0

    fun isFamous(place: Place): Boolean = (place.ratingCount ?: 0) >= MINIMUM_REVIEWS && (place.rating ?: 0.0) >= MINIMUM_RATING

    /** One identity per place across overlapping searches: Google's id, else name + position. */
    fun key(place: Place): String = place.id ?: "${place.name}@${place.coordinate.queryString}"

    /** Ask Google again: first fix of the ride, or [SEARCH_SPACING] from the last search. */
    fun needsSearch(position: Coordinate, lastSearch: Coordinate?): Boolean =
        lastSearch == null || position.distanceTo(lastSearch) >= SEARCH_SPACING

    /** The nearest famous places to announce now, nearest first, at most [limit]. */
    fun ahead(
        position: Coordinate,
        course: Double?,
        candidates: List<Place>,
        alreadyAnnounced: Set<String>,
        savedSpots: List<Coordinate> = emptyList(),
        distance: Double = ALERT_DISTANCE,
        limit: Int = ANNOUNCE_LIMIT,
    ): List<Pair<Place, Double>> {
        val seen = mutableSetOf<String>()
        return candidates
            .filter { place ->
                val key = key(place)
                if (!isFamous(place) || key in alreadyAnnounced || !seen.add(key)) return@filter false
                savedSpots.nearest(place.coordinate, MediaPlacer.DEFAULT_SPOT_RADIUS) { it } == null
            }
            .map { it to it.coordinate.distanceTo(position) }
            .filter { it.second <= distance }
            .filter { (place, d) ->
                if (course == null || course < 0 || d <= MediaPlacer.DEFAULT_SPOT_RADIUS) true
                else angleBetween(course, bearing(position, place.coordinate)) <= AHEAD_ANGLE
            }
            .sortedBy { it.second }
            .take(maxOf(0, limit))
    }

    /** Direction of travel: the GPS course while moving, else the bearing over the last [meters]. */
    fun heading(track: List<TrackPoint>, meters: Double = 50.0, minimumSpeed: Double = 3.0): Double? {
        val last = track.lastOrNull() ?: return null
        val course = last.course
        if (course != null && course >= 0 && (last.speed ?: 0.0) >= minimumSpeed) return course
        for (point in track.dropLast(1).asReversed().take(200)) {
            if (point.coordinate.distanceTo(last.coordinate) >= meters) return bearing(point.coordinate, last.coordinate)
        }
        return null
    }

    /** Initial great-circle bearing in degrees from north (0 until 360). */
    fun bearing(from: Coordinate, to: Coordinate): Double {
        val lat1 = from.latitude * Math.PI / 180
        val lat2 = to.latitude * Math.PI / 180
        val dLon = (to.longitude - from.longitude) * Math.PI / 180
        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        val degrees = atan2(y, x) * 180 / Math.PI
        return (degrees + 360) % 360
    }

    /** Smallest difference between two headings (0..180). */
    internal fun angleBetween(a: Double, b: Double): Double {
        val d = abs(a - b) % 360
        return if (d > 180) 360 - d else d
    }

    /** "Srirangapatna Fort 1.2 km · Ranganathittu 1.8 km" */
    fun summary(places: List<Pair<Place, Double>>, distance: (Double) -> String): String =
        places.joinToString(" · ") { "${it.first.name} ${distance(it.second)}" }
}
