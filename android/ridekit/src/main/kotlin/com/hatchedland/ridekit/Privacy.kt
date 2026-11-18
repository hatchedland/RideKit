package com.hatchedland.ridekit

// Twin of Social/SharePrivacy.swift and SharedRide.redacted. The server decides what friends see
// (supabase/functions/_shared/privacy.ts); the app uses this to hide the start of a live ride and to
// skip uploading photos the server would drop.

/** A place the rider never wants to reveal to friends, such as home or work. */
data class PrivacyZone(val id: String, val name: String, val center: Coordinate, val radius: Double = DEFAULT_RADIUS) {
    fun contains(c: Coordinate): Boolean = center.distanceTo(c) <= radius

    companion object {
        const val DEFAULT_RADIUS = 500.0
    }
}

/** What friends may see: nothing in a zone, and not the first or last [endTrim] meters of a ride. */
data class SharePrivacy(val zones: List<PrivacyZone> = emptyList(), private val trim: Double = DEFAULT_END_TRIM) {
    val endTrim: Double = maxOf(0.0, trim)

    fun hides(c: Coordinate): Boolean = zones.any { it.contains(c) }

    /** The part of the track friends may see. */
    fun redact(track: List<TrackPoint>): List<TrackPoint> {
        val visible = track.filter { !hides(it.coordinate) }
        if (endTrim <= 0 || visible.size <= 1) return visible
        val total = Odometer(visible).distanceAt(visible.last().t) ?: 0.0
        if (!(total > endTrim * 2)) return emptyList()

        val cumulative = DoubleArray(visible.size)
        for (i in 1 until visible.size) {
            cumulative[i] = cumulative[i - 1] + visible[i - 1].coordinate.distanceTo(visible[i].coordinate)
        }
        return visible.filterIndexed { i, _ -> cumulative[i] >= endTrim && cumulative[i] <= total - endTrim }
    }

    /** `true` if a point of the ride may be shown: outside every zone and not near the ride's ends. */
    fun shows(c: Coordinate, track: List<TrackPoint>): Boolean {
        if (hides(c)) return false
        if (endTrim <= 0) return true
        val ends = listOfNotNull(track.firstOrNull()?.coordinate, track.lastOrNull()?.coordinate)
        return ends.all { it.distanceTo(c) > endTrim }
    }

    companion object {
        const val DEFAULT_END_TRIM = 500.0
    }
}

/** The parts of a shared ride that carry a place, for [redact]. */
data class SharedStop(val id: String, val coordinate: Coordinate, val photoIDs: List<String>)
data class SharedPhoto(val id: String, val coordinate: Coordinate?)

/**
 * Removes what [privacy] doesn't allow: stops near home or the ride's ends, every photo taken at
 * such a stop, and photo locations there. Order is kept.
 */
fun redact(privacy: SharePrivacy, track: List<TrackPoint>, stops: List<SharedStop>, photos: List<SharedPhoto>):
    Pair<List<SharedStop>, List<SharedPhoto>> {
    val hiddenPhotoIDs = stops.filter { !privacy.shows(it.coordinate, track) }.flatMap { it.photoIDs }.toSet()
    val keptStops = stops.filter { privacy.shows(it.coordinate, track) }
    val keptPhotos = photos.filter { it.id !in hiddenPhotoIDs }.map { photo ->
        if (photo.coordinate != null && !privacy.shows(photo.coordinate, track)) photo.copy(coordinate = null) else photo
    }
    return keptStops to keptPhotos
}
