package com.hatchedland.ridekit

// Twin of Spots/StopDetector.swift, Spots/WishlistMatcher.swift and the spot types in Media.

/** Photo → spot matching and wishlist auto-visit radius. */
object MediaPlacer {
    const val DEFAULT_SPOT_RADIUS = 150.0
}

/** A spot reduced to what matching needs. Ids are uppercase UUID strings, as on iOS. */
data class SpotReference(val id: String, val coordinate: Coordinate)

/** A photo or video of the ride, reduced to what matching needs. */
data class MediaCandidate(val id: String, val capturedAt: Double, val coordinate: Coordinate? = null)

/** A period during a ride when the rider was stationary. */
data class Stop(val start: Double, val end: Double, val center: Coordinate) {
    val duration: Double get() = end - start
}

object StopDetector {
    /** Slower than this (m/s ≈ 5 km/h) counts as stopped. */
    const val STOP_SPEED = 1.39
    /** Stopped for at least this long (s) counts as a real stop, not a red light. */
    const val MINIMUM_DURATION = 120.0

    fun stops(points: List<TrackPoint>, minimumDuration: Double = MINIMUM_DURATION): List<Stop> {
        val result = mutableListOf<Stop>()
        val run = mutableListOf<TrackPoint>()

        fun flush() {
            if (run.isNotEmpty() && run.last().t - run.first().t >= minimumDuration) {
                val lat = run.sumOf { it.coordinate.latitude } / run.size
                val lon = run.sumOf { it.coordinate.longitude } / run.size
                result += Stop(run.first().t, run.last().t, Coordinate(lat, lon))
            }
            run.clear()
        }

        points.forEachIndexed { index, point ->
            val reported = point.speed
            val speed = when {
                reported != null && reported >= 0 -> reported
                index > 0 -> {
                    val previous = points[index - 1]
                    val dt = point.t - previous.t
                    if (dt > 0) point.coordinate.distanceTo(previous.coordinate) / dt else 0.0
                }
                else -> 0.0
            }
            if (speed < STOP_SPEED) run += point else flush()
        }
        flush()
        return result
    }
}

object WishlistMatcher {
    sealed interface Evidence {
        data class Stopped(val stop: Stop) : Evidence
        data class Photo(val mediaID: String) : Evidence
    }

    data class Visit(val spotID: String, val t: Double, val evidence: Evidence)

    /**
     * A wishlist spot counts as visited when, within [radius], the rider **stopped** (≥ 2 min) or
     * **took a photo/video**. Riding past doesn't count. Each spot once, with its earliest evidence.
     */
    fun visits(
        wishlist: List<SpotReference>,
        track: List<TrackPoint>,
        media: List<MediaCandidate>,
        radius: Double = MediaPlacer.DEFAULT_SPOT_RADIUS,
    ): List<Visit> {
        val stops = StopDetector.stops(track)
        val result = mutableListOf<Visit>()
        for (spot in wishlist) {
            val candidates = mutableListOf<Visit>()
            stops.firstOrNull { it.center.distanceTo(spot.coordinate) <= radius }?.let {
                candidates += Visit(spot.id, it.start, Evidence.Stopped(it))
            }
            media.filter { (it.coordinate?.distanceTo(spot.coordinate) ?: Double.POSITIVE_INFINITY) <= radius }
                .minByOrNull { it.capturedAt }
                ?.let { candidates += Visit(spot.id, it.capturedAt, Evidence.Photo(it.id)) }
            candidates.minByOrNull { it.t }?.let { result += it }
        }
        return result.sortedBy { it.t }
    }

    /** Distance at which the rider is told a wishlist spot is near. */
    const val NEARBY_ALERT_DISTANCE = 2_000.0

    /** Wishlist spots within [distance] of [position] not yet announced this ride, nearest first. */
    fun nearbyAlerts(
        position: Coordinate,
        wishlist: List<SpotReference>,
        alreadyAlerted: Set<String>,
        distance: Double = NEARBY_ALERT_DISTANCE,
    ): List<Pair<SpotReference, Double>> = wishlist
        .filter { it.id !in alreadyAlerted }
        .map { it to it.coordinate.distanceTo(position) }
        .filter { it.second <= distance }
        .sortedBy { it.second }
}

object RevisitDetector {
    /** Marking a spot this close to an existing one offers "Add visit to …?" instead of a duplicate. */
    const val RADIUS = 100.0

    fun existingSpot(near: Coordinate, spots: List<SpotReference>): SpotReference? =
        spots.nearest(near, RADIUS) { it.coordinate }?.first
}
