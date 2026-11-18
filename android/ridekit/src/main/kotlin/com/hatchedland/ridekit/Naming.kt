package com.hatchedland.ridekit

// Twin of Rides/RideNaming.swift and App/AppVersion.swift.

/** Names for rides (on iOS also the Photos album name). */
object RideNaming {

    /**
     * The final name for a ride started with [input] as typed. [dateText] is the start date in the
     * rider's time zone and locale, day-month-year abbreviated (ICU skeleton "yMMMd"; en_IN →
     * "18 Nov 2026"). The app formats it, because Android's formatter isn't on the JVM.
     *
     * Empty input → "Ride · 18 Nov 2026". A name already used gets the date, then a counter.
     */
    fun resolve(input: String, dateText: String, existingNames: Collection<String>): String {
        val trimmed = input.trim().replace("/", "-")   // "/" reads like a folder path
        val taken = existingNames.map { it.lowercase() }.toSet()

        val base = trimmed.ifEmpty { "Ride · $dateText" }
        if (base.lowercase() !in taken) return base

        // A name that already ends with today's date (e.g. picked from suggestions) isn't dated twice.
        val alreadyDated = trimmed.lowercase().endsWith(" · $dateText".lowercase())
        val dated = if (trimmed.isEmpty() || alreadyDated) base else "$trimmed · $dateText"
        if (dated.lowercase() !in taken) return dated

        var counter = 2
        while ("$dated ($counter)".lowercase() in taken) counter++
        return "$dated ($counter)"
    }

    /** Suggestions under the name field: recent ride names, then wishlist spot names, no duplicates. */
    fun suggestions(input: String, recentRideNames: List<String>, wishlistSpotNames: List<String>, limit: Int = 6): List<String> {
        val query = input.trim().lowercase()
        val seen = mutableSetOf<String>()
        val result = mutableListOf<String>()
        for (name in recentRideNames + wishlistSpotNames) {
            val key = name.lowercase()
            if (name.isEmpty() || key in seen) continue
            if (query.isNotEmpty() && !key.contains(query)) continue
            if (key == query) continue
            seen += key
            result += name
            if (result.size == limit) break
        }
        return result
    }
}

/** A marketing version like "1.2.0", compared part by part; anything after the numbers is ignored. */
class AppVersion private constructor(val parts: List<Int>) : Comparable<AppVersion> {

    override fun compareTo(other: AppVersion): Int {
        for (i in 0 until maxOf(parts.size, other.parts.size)) {
            val x = parts.getOrElse(i) { 0 }
            val y = other.parts.getOrElse(i) { 0 }
            if (x != y) return x.compareTo(y)
        }
        return 0
    }

    override fun equals(other: Any?): Boolean = other is AppVersion && compareTo(other) == 0
    override fun hashCode(): Int = parts.dropLastWhile { it == 0 }.hashCode()
    override fun toString(): String = parts.joinToString(".")

    companion object {
        fun parse(text: String): AppVersion? {
            val parts = mutableListOf<Int>()
            for (piece in text.trim().split(".")) {
                val digits = piece.takeWhile { it in '0'..'9' }
                val value = digits.toIntOrNull() ?: break
                parts += value
                if (digits.length < piece.length) break
            }
            return if (parts.isEmpty()) null else AppVersion(parts)
        }

        /** The server's app_config.min_version says this build is too old; unreadable never blocks. */
        fun needsUpdate(current: String, minimum: String?): Boolean {
            val min = minimum?.let(::parse) ?: return false
            val now = parse(current) ?: return false
            return now < min
        }
    }
}
