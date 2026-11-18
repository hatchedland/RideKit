package com.hatchedland.ridekit

import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin

// Twin of Rides/RideTimePlan.swift and Sun (Weather/WeatherAlerts.swift).

/** How this rider actually rides, learned from their own past rides. */
data class RidePace(
    /** Typical moving speed (m/s), `null` without enough rides. */
    val movingSpeedMps: Double?,
    /** Share of a ride's elapsed time spent stopped, 0…1. */
    val stopShare: Double,
    /** How many rides this is based on (0: the defaults). */
    val rideCount: Int,
) {
    data class Sample(val distanceMeters: Double, val movingSeconds: Double, val elapsedSeconds: Double)

    companion object {
        /** About 10 minutes stopped per hour on the road. */
        val DEFAULT = RidePace(null, 0.15, 0)
        const val MINIMUM_DISTANCE = 20_000.0
        const val MINIMUM_MOVING_SECONDS = 20 * 60.0
        const val RECENT_RIDES = 20
        private const val STOP_SHARE_MIN = 0.05
        private const val STOP_SHARE_MAX = 0.45

        /** Learns the pace from rides, newest first: distance-weighted speed, median stop share. */
        fun learn(rides: List<Sample>): RidePace {
            val usable = rides.filter {
                it.distanceMeters >= MINIMUM_DISTANCE && it.movingSeconds >= MINIMUM_MOVING_SECONDS &&
                    it.elapsedSeconds >= it.movingSeconds
            }.take(RECENT_RIDES)
            if (usable.size < 2) return DEFAULT
            val distance = usable.sumOf { it.distanceMeters }
            val moving = usable.sumOf { it.movingSeconds }
            val shares = usable.map { (1 - it.movingSeconds / it.elapsedSeconds).coerceIn(STOP_SHARE_MIN, STOP_SHARE_MAX) }.sorted()
            val median = if (shares.size % 2 == 0) (shares[shares.size / 2 - 1] + shares[shares.size / 2]) / 2 else shares[shares.size / 2]
            return RidePace(distance / moving, median, usable.size)
        }
    }
}

/** How long a ride really takes, when it arrives, and whether that's in daylight. */
class RideTimePlan(val departure: Double, distanceMeters: Double, roadSeconds: Double, destination: Coordinate, val pace: RidePace) {
    val movingSeconds: Double
    val breakSeconds: Double
    val arrival: Double
    /** Sunset at the destination on the day of departure; `null` near the poles or for multi-day rides. */
    val sunset: Double?
    /** Leave by this to arrive [DAYLIGHT_MARGIN] before sunset. */
    val latestDeparture: Double?

    val totalSeconds: Double get() = movingSeconds + breakSeconds
    val arrivesAfterDark: Boolean get() = sunset?.let { arrival > it } ?: false
    val canStillArriveInDaylight: Boolean get() = latestDeparture?.let { it >= departure } ?: true

    init {
        // Google knows the roads, the rider's history knows the rider: average them, never faster
        // than Google, never slower than 1.6× Google.
        var moving = roadSeconds
        val speed = pace.movingSpeedMps
        if (speed != null && speed > 0) {
            val personal = distanceMeters / speed
            moving = minOf(maxOf((roadSeconds + personal) / 2, roadSeconds), roadSeconds * SLOWEST_FACTOR)
        }
        movingSeconds = moving
        breakSeconds = moving * pace.stopShare / (1 - pace.stopShare)
        arrival = departure + moving + breakSeconds

        val set = if (moving + breakSeconds <= LONGEST_DAY_RIDE) Sun.sunset(departure, destination) else null
        sunset = set
        latestDeparture = set?.let { it - DAYLIGHT_MARGIN - moving - breakSeconds }
    }

    companion object {
        const val DAYLIGHT_MARGIN = 20 * 60.0
        const val LONGEST_DAY_RIDE = 14 * 3600.0
        private const val SLOWEST_FACTOR = 1.6
    }
}

/** Sunrise-equation sunset (accurate to a couple of minutes), so the sunset alert needs no request. */
object Sun {
    /** Sunset (Unix seconds) on the day of the solar noon nearest [t]; `null` in polar day or night. */
    fun sunset(t: Double, at: Coordinate): Double? {
        val rad = Math.PI / 180
        val julianDay = t / 86_400 + 2_440_587.5
        val east = at.longitude / 360
        val noon = (julianDay - 2_451_545.0 + east).roundedAwayFromZero() - east
        val anomaly = (357.5291 + 0.985_600_28 * noon) % 360
        val center = 1.9148 * sin(anomaly * rad) + 0.02 * sin(2 * anomaly * rad) + 0.0003 * sin(3 * anomaly * rad)
        val longitude = (anomaly + center + 180 + 102.9372) % 360
        val transit = 2_451_545.0 + noon + 0.0053 * sin(anomaly * rad) - 0.0069 * sin(2 * longitude * rad)
        val declination = asin(sin(longitude * rad) * sin(23.4397 * rad))
        val latitude = at.latitude * rad
        val cosHourAngle = (sin(-0.833 * rad) - sin(latitude) * sin(declination)) / (cos(latitude) * cos(declination))
        if (cosHourAngle < -1 || cosHourAngle > 1) return null
        val set = transit + acos(cosHourAngle) / rad / 360
        return (set - 2_440_587.5) * 86_400
    }
}
