package com.hatchedland.ridekit


// Twin of Media/Trail.swift: a ride told as stops joined by legs of road, in the order they happened.
//   start ─ leg ─ stop ─ leg ─ stop ─ leg ─ end      (legs.size == stops.size + 1)

data class Trail(val stops: List<Stop>, val legs: List<Leg>) {

    data class Stop(
        /** Stable across rebuilds: the spot's id, or the cluster's first media id. */
        val id: String,
        val kind: Kind,
        val coordinate: Coordinate,
        val arrivedAt: Double,
        val departedAt: Double,
        /** Meters along the route from the start, `null` without a track. */
        val distanceFromStart: Double? = null,
        /** Media ids, oldest first. */
        val mediaIDs: List<String> = emptyList(),
        /** Songs that started while the rider was here. */
        val songIDs: List<String> = emptyList(),
    ) {
        sealed interface Kind {
            /** A saved spot. */
            data class Spot(val spotID: String) : Kind
            /** Photos taken together away from any spot; the app suggests a name and offers "Save as spot". */
            data object Cluster : Kind
        }

        internal fun including(item: Media) = copy(
            arrivedAt = minOf(arrivedAt, item.capturedAt),
            departedAt = maxOf(departedAt, item.capturedAt),
            mediaIDs = mediaIDs + item.id,
        )

        internal fun timeDistance(t: Double): Double = when {
            t < arrivedAt -> arrivedAt - t
            t > departedAt -> t - departedAt
            else -> 0.0
        }
    }

    data class Leg(
        val start: Double,
        val end: Double,
        /** Meters ridden on this leg, `null` without a track. */
        val distance: Double?,
        /** Photos with no location that weren't taken at a stop: "on the road". */
        val mediaIDs: List<String> = emptyList(),
        /** Songs that started on this leg and not at a stop. */
        val songIDs: List<String> = emptyList(),
    ) {
        val duration: Double get() = end - start
    }

    /** A photo or video of the ride, reduced to what the trail needs. */
    data class Media(val id: String, val capturedAt: Double, val coordinate: Coordinate? = null, val spotID: String? = null)

    /** A spot that should appear even without photos (e.g. marked while riding). */
    data class Spot(val id: String, val coordinate: Coordinate, val markedAt: Double)

    data class Song(val id: String, val startedAt: Double)

    companion object {
        const val CLUSTER_RADIUS = MediaPlacer.DEFAULT_SPOT_RADIUS
        const val CLUSTER_GAP = 10 * 60.0
        const val STOP_TIME_SLACK = 10 * 60.0

        private val stopOrder = compareBy<Stop>({ it.arrivedAt }, { it.id })

        fun build(
            rideStart: Double,
            rideEnd: Double,
            track: List<TrackPoint>,
            media: List<Media>,
            spots: List<Spot>,
            songs: List<Song> = emptyList(),
        ): Trail {
            val odometer = Odometer(track)
            val sortedMedia = media.sortedWith(compareBy({ it.capturedAt }, { it.id }))

            // 1. Spot stops: every spot that has photos here or was marked on this ride.
            val spotStops = LinkedHashMap<String, Stop>()
            for (spot in spots) {
                spotStops[spot.id] = Stop(spot.id, Stop.Kind.Spot(spot.id), spot.coordinate, spot.markedAt, spot.markedAt)
            }
            val unlocated = mutableListOf<Media>()
            val clusters = mutableListOf<Stop>()
            for (item in sortedMedia) {
                val spotID = item.spotID
                val spotCoordinate = spotID?.let { spotStops[it]?.coordinate ?: item.coordinate }
                if (spotID != null && spotCoordinate != null) {
                    // Spots should all be passed in; one that wasn't is placed at its first photo.
                    val stop = spotStops[spotID]
                        ?: Stop(spotID, Stop.Kind.Spot(spotID), spotCoordinate, item.capturedAt, item.capturedAt)
                    spotStops[spotID] = stop.including(item)
                } else if (item.coordinate != null && item.coordinate.isValid) {
                    // 2. Clusters: photos close in place and time, away from any spot.
                    val last = clusters.lastOrNull()
                    if (last != null && last.coordinate.distanceTo(item.coordinate) <= CLUSTER_RADIUS &&
                        item.capturedAt - last.departedAt <= CLUSTER_GAP
                    ) {
                        clusters[clusters.size - 1] = last.including(item)
                    } else {
                        clusters += Stop(item.id, Stop.Kind.Cluster, item.coordinate, item.capturedAt, item.capturedAt, mediaIDs = listOf(item.id))
                    }
                } else {
                    unlocated += item
                }
            }

            val stops = (spotStops.values + clusters).sortedWith(stopOrder).toMutableList()

            // 3. Photos without location: into the stop closest in time, if close enough.
            val onTheRoad = mutableListOf<Media>()
            for (item in unlocated) {
                val nearest = stops.indices.minByOrNull { stops[it].timeDistance(item.capturedAt) }
                if (nearest != null && stops[nearest].timeDistance(item.capturedAt) <= STOP_TIME_SLACK) {
                    stops[nearest] = stops[nearest].copy(mediaIDs = stops[nearest].mediaIDs + item.id)
                } else {
                    onTheRoad += item
                }
            }
            for (i in stops.indices) stops[i] = stops[i].copy(distanceFromStart = odometer.distanceAt(stops[i].arrivedAt))

            // 4. Legs: the road before each stop, and after the last one.
            val start = minOf(track.firstOrNull()?.t ?: rideStart, rideStart)
            val end = maxOf(track.lastOrNull()?.t ?: rideEnd, rideEnd)
            val boundaries = mutableListOf<Pair<Double, Double>>()
            var cursor = start
            for (stop in stops) {
                boundaries += cursor to maxOf(cursor, stop.arrivedAt)
                cursor = maxOf(cursor, stop.departedAt)
            }
            boundaries += cursor to maxOf(cursor, end)

            val legs = boundaries.map { (from, to) -> Leg(from, to, odometer.distance(from, to)) }.toMutableList()
            // Something that happened at or after a leg's start belongs to the last such leg.
            fun legIndex(t: Double): Int = legs.indexOfLast { it.start <= t }.coerceAtLeast(0)
            for (item in onTheRoad) {
                val i = legIndex(item.capturedAt)
                legs[i] = legs[i].copy(mediaIDs = legs[i].mediaIDs + item.id)
            }
            // A song that started during a stop (arrival to departure) belongs to the stop, else to its leg.
            for (song in songs.sortedBy { it.startedAt }) {
                val stopIndex = stops.indexOfFirst { it.arrivedAt <= song.startedAt && song.startedAt <= it.departedAt }
                if (stopIndex >= 0) {
                    stops[stopIndex] = stops[stopIndex].copy(songIDs = stops[stopIndex].songIDs + song.id)
                } else {
                    val i = legIndex(song.startedAt)
                    legs[i] = legs[i].copy(songIDs = legs[i].songIDs + song.id)
                }
            }
            return Trail(stops, legs)
        }
    }
}

