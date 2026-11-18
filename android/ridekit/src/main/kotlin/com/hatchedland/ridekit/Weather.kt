package com.hatchedland.ridekit

// Twin of Weather/GoogleWeather.swift (WeatherHour) and Weather/WeatherAlerts.swift.

/** One hour of Google's forecast, reduced to what ride alerts need. Metric throughout. */
data class WeatherHour(
    /** Start of the hour, Unix seconds (Google's hours can start on the half hour). */
    val start: Double,
    /** Google's condition type, e.g. "LIGHT_RAIN" or "THUNDERSTORM". */
    val condition: String = "CLEAR",
    val temperature: Double? = null,
    val feelsLike: Double? = null,
    /** Chance of rain (or other precipitation), 0–100. */
    val rainChance: Int = 0,
    val thunderChance: Int = 0,
    val gustKmh: Double? = null,
    val isDaytime: Boolean? = null,
) {
    val end: Double get() = start + 3_600

    private val isWetCondition: Boolean
        get() = listOf("RAIN", "SHOWER", "THUNDER", "HAIL", "SLEET", "SNOW").any { condition.contains(it) }

    /** Worth getting the rain gear out for: likely, or forecast as wet with a fair chance. */
    val isRainy: Boolean
        get() = rainChance >= WeatherAlerts.RAIN_CHANCE || (isWetCondition && rainChance >= WeatherAlerts.WET_CONDITION_RAIN_CHANCE)

    val isStormy: Boolean
        get() = thunderChance >= WeatherAlerts.THUNDER_CHANCE || condition.contains("THUNDER") || condition.contains("HAIL")

    /** What the sky is doing this hour, most important first. */
    val sky: WeatherSky
        get() = when {
            isStormy -> WeatherSky.STORM
            isRainy -> WeatherSky.RAIN
            (gustKmh ?: 0.0) >= WeatherAlerts.GUST_KMH -> WeatherSky.WIND
            (feelsLike ?: 0.0) >= WeatherAlerts.FEELS_LIKE_HEAT -> WeatherSky.HEAT
            listOf("CLOUDY", "FOG", "OVERCAST").any { condition.contains(it) } && !condition.contains("MOSTLY_CLEAR") ->
                if (condition.contains("PARTLY")) WeatherSky.PARTLY_CLOUDY else WeatherSky.CLOUDY
            else -> WeatherSky.CLEAR
        }
}

enum class WeatherSky { CLEAR, PARTLY_CLOUDY, CLOUDY, RAIN, STORM, WIND, HEAT }

/** A weather alert while riding: passive, like the wishlist and famous-places alerts. */
data class WeatherAlert(
    val kind: Kind,
    /** When it starts (Unix seconds); `null` means now. */
    val at: Double? = null,
    /** Rain chance for RAIN and STORM. */
    val percent: Int? = null,
    /** Gust km/h (WIND), feels-like °C (HEAT), meters still to ride (SUNSET). */
    val value: Double? = null,
) {
    /** In priority order. `raw` matches Swift's raw values and spec/fixtures. */
    enum class Kind(val raw: String) { STORM("storm"), RAIN("rain"), WIND("wind"), HEAT("heat"), CLEARING("clearing"), SUNSET("sunset") }

    /** What and when, e.g. "Rain from 4:30 pm". */
    fun headline(time: (Double) -> String): String {
        val from = at?.let { " from ${time(it)}" }
        return when (kind) {
            Kind.STORM -> "Thunderstorm" + (from ?: " likely now")
            Kind.RAIN -> "Rain" + (from ?: " now")
            Kind.WIND -> "Strong gusts"
            Kind.HEAT -> "Feels like ${(value ?: 0.0).roundedAwayFromZero().toInt()}°"
            Kind.CLEARING -> "Rain easing" + (from ?: " now")
            Kind.SUNSET -> at?.let { "Sunset at ${time(it)}" } ?: "Sunset soon"
        }
    }

    /** How much, or what to do: the quieter second line. */
    fun detail(distance: (Double) -> String): String? = when (kind) {
        Kind.STORM -> "Find shelter"
        Kind.RAIN -> percent?.let { "$it% chance" }
        Kind.WIND -> "Up to ${(value ?: 0.0).roundedAwayFromZero().toInt()} km/h"
        Kind.HEAT -> "Take a water break"
        Kind.CLEARING -> "Drier road ahead"
        Kind.SUNSET -> value?.let { "${distance(it)} to go" }
    }

    fun text(time: (Double) -> String, distance: (Double) -> String): String =
        listOfNotNull(headline(time), detail(distance)).joinToString(" · ")
}

/** What has been announced this ride, so alerts fire on changes rather than repeating. */
data class WeatherAlertState(
    var lastAlert: Double? = null,
    val lastByKind: MutableMap<WeatherAlert.Kind, Double> = mutableMapOf(),
    /** A rain or storm alert was given and it hasn't cleared since. */
    var isWet: Boolean = false,
)

/** Which weather alert to give, if any. Same rules as iOS; see spec/fixtures/weather-alerts.json. */
object WeatherAlerts {
    const val RAIN_CHANCE = 60
    const val WET_CONDITION_RAIN_CHANCE = 40
    const val THUNDER_CHANCE = 50
    const val GUST_KMH = 40.0
    const val FEELS_LIKE_HEAT = 38.0
    const val LOOK_AHEAD = 60 * 60.0
    const val SAME_KIND_INTERVAL = 60 * 60.0
    const val MINIMUM_INTERVAL = 15 * 60.0
    const val SUNSET_WARNING = 30 * 60.0
    const val SUNSET_MINIMUM_REMAINING = 5_000.0

    fun next(forecast: List<WeatherHour>, now: Double, state: WeatherAlertState): WeatherAlert? {
        val window = forecast.filter { it.end > now && it.start < now + LOOK_AHEAD }.sortedBy { it.start }
        if (window.isEmpty()) return null
        fun startTime(hour: WeatherHour): Double? = if (hour.start > now) hour.start else null

        val candidates = mutableListOf<WeatherAlert>()
        val wetHours = window.filter { it.isRainy || it.isStormy }
        window.firstOrNull { it.isStormy }?.let { candidates += WeatherAlert(WeatherAlert.Kind.STORM, startTime(it), it.rainChance) }
        if (!state.isWet) wetHours.firstOrNull()?.let { candidates += WeatherAlert(WeatherAlert.Kind.RAIN, startTime(it), it.rainChance) }
        window.mapNotNull { it.gustKmh }.maxOrNull()?.takeIf { it >= GUST_KMH }?.let {
            candidates += WeatherAlert(WeatherAlert.Kind.WIND, value = it)
        }
        window.mapNotNull { it.feelsLike }.maxOrNull()?.takeIf { it >= FEELS_LIKE_HEAT }?.let {
            candidates += WeatherAlert(WeatherAlert.Kind.HEAT, value = it)
        }
        val current = window.first()
        if (state.isWet && current.start <= now && (current.isRainy || current.isStormy)) {
            window.drop(1).firstOrNull { !it.isRainy && !it.isStormy }?.let {
                candidates += WeatherAlert(WeatherAlert.Kind.CLEARING, startTime(it))
            }
        }
        if (state.isWet && wetHours.isEmpty()) {
            // It cleared without us catching the hour it stopped; next rain is news again.
            state.isWet = false
        }

        val chosen = candidates.firstOrNull { alert ->
            state.lastByKind[alert.kind]?.let { now - it >= SAME_KIND_INTERVAL } ?: true
        } ?: return null
        if (!(state.lastAlert?.let { now - it >= MINIMUM_INTERVAL } ?: true)) return null
        record(chosen, now, state)
        return chosen
    }

    /** "Sunset at 6:12 pm · 48 km to go" once, in the last half hour of daylight with ≥ 5 km left. */
    fun sunset(sunset: Double?, now: Double, remainingMeters: Double?, state: WeatherAlertState): WeatherAlert? {
        if (sunset == null || remainingMeters == null || remainingMeters < SUNSET_MINIMUM_REMAINING) return null
        if (!(now < sunset) || sunset - now > SUNSET_WARNING || state.lastByKind.containsKey(WeatherAlert.Kind.SUNSET)) return null
        if (!(state.lastAlert?.let { now - it >= MINIMUM_INTERVAL } ?: true)) return null
        val alert = WeatherAlert(WeatherAlert.Kind.SUNSET, at = sunset, value = remainingMeters)
        record(alert, now, state)
        return alert
    }

    private fun record(alert: WeatherAlert, now: Double, state: WeatherAlertState) {
        state.lastAlert = now
        state.lastByKind[alert.kind] = now
        when (alert.kind) {
            WeatherAlert.Kind.RAIN, WeatherAlert.Kind.STORM -> state.isWet = true
            WeatherAlert.Kind.CLEARING -> state.isWet = false
            else -> Unit
        }
    }

    /** Before a ride: the one thing worth knowing about the next [hours] hours, most serious first. */
    fun outlook(forecast: List<WeatherHour>, now: Double, hours: Double = 6.0): WeatherAlert? {
        val ahead = forecast.filter { it.end > now && it.start < now + hours * 3_600 }.sortedBy { it.start }
        fun at(hour: WeatherHour): Double? = if (hour.start > now) hour.start else null
        ahead.firstOrNull { it.isStormy }?.let { return WeatherAlert(WeatherAlert.Kind.STORM, at(it), it.rainChance) }
        ahead.firstOrNull { it.isRainy }?.let { return WeatherAlert(WeatherAlert.Kind.RAIN, at(it), it.rainChance) }
        ahead.mapNotNull { it.gustKmh }.maxOrNull()?.takeIf { it >= GUST_KMH }?.let { return WeatherAlert(WeatherAlert.Kind.WIND, value = it) }
        ahead.mapNotNull { it.feelsLike }.maxOrNull()?.takeIf { it >= FEELS_LIKE_HEAT }?.let { return WeatherAlert(WeatherAlert.Kind.HEAT, value = it) }
        return null
    }

    /** The forecast hour covering [now], for the riding screen's readout. */
    fun current(forecast: List<WeatherHour>, now: Double): WeatherHour? = forecast.firstOrNull { it.start <= now && now < it.end }

    /** Where to ask for the forecast: about [seconds] of riding ahead along the route, else here. */
    fun forecastPoint(position: Coordinate, routeAhead: List<Coordinate>, speedMps: Double, seconds: Double = 30 * 60.0): Coordinate {
        val target = minOf(40_000.0, maxOf(5_000.0, speedMps * seconds))
        if (routeAhead.size <= 1) return position
        var travelled = 0.0
        for ((a, b) in routeAhead.zipWithNext()) {
            val step = a.distanceTo(b)
            if (travelled + step >= target) return a.interpolated(b, if (step > 0) (target - travelled) / step else 0.0)
            travelled += step
        }
        return routeAhead.last()
    }
}
