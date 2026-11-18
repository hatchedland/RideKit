package com.hatchedland.ridekit

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.DataFormatException
import java.util.zip.Deflater
import java.util.zip.Inflater

// Twin of Tracking/TrackPoint.swift and Tracking/TrackCodec.swift (format: spec/track-codec.md).

/** One accepted GPS fix of a ride. */
data class TrackPoint(
    /** Unix seconds. */
    val t: Double,
    val coordinate: Coordinate,
    /** Meters above sea level. */
    val altitude: Double? = null,
    /** Meters per second as reported by GPS. */
    val speed: Double? = null,
    /** Degrees from true north. */
    val course: Double? = null,
    /** Horizontal accuracy radius in meters. */
    val horizontalAccuracy: Double = 5.0,
    /** Lean angle in degrees (negative = left). */
    val lean: Double? = null,
)

/** Where the rider was at [t], interpolated; `null` outside the track or in a gap longer than [maxGap] s. */
fun List<TrackPoint>.coordinateAt(t: Double, maxGap: Double = 120.0): Coordinate? {
    if (isEmpty() || t < first().t || t > last().t) return null
    var low = 0
    var high = size - 1
    while (low < high) {
        val mid = (low + high) / 2
        if (this[mid].t < t) low = mid + 1 else high = mid
    }
    val after = this[low]
    if (after.t == t || low == 0) return after.coordinate
    val before = this[low - 1]
    val span = after.t - before.t
    if (span > maxGap) return null
    return before.coordinate.interpolated(after.coordinate, (t - before.t) / span)
}

/** Distance ridden up to any moment of the ride. */
internal class Odometer(track: List<TrackPoint>) {
    private val times = track.map { it.t }
    private val cumulative: List<Double>

    init {
        var total = 0.0
        cumulative = track.mapIndexed { index, point ->
            if (index > 0) total += track[index - 1].coordinate.distanceTo(point.coordinate)
            total
        }
    }

    /** Meters ridden by [t], interpolated and clamped to the track; `null` without a track. */
    fun distanceAt(t: Double): Double? {
        if (times.isEmpty()) return null
        if (t <= times.first()) return 0.0
        if (t >= times.last()) return cumulative.last()
        var low = 0
        var high = times.size - 1
        while (low < high) {
            val mid = (low + high) / 2
            if (times[mid] < t) low = mid + 1 else high = mid
        }
        val span = times[low] - times[low - 1]
        val fraction = if (span > 0) (t - times[low - 1]) / span else 1.0
        return cumulative[low - 1] + (cumulative[low] - cumulative[low - 1]) * fraction
    }

    fun distance(from: Double, to: Double): Double? {
        val a = distanceAt(from) ?: return null
        val b = distanceAt(to) ?: return null
        return maxOf(0.0, b - a)
    }
}

/** A ride's track as one compact file: "RTK" + 2 + count, then raw DEFLATE of 44-byte points. */
object TrackCodec {
    const val VERSION: Byte = 2
    const val BYTES_PER_POINT = 44
    private const val HEADER_SIZE = 8
    private val magic = byteArrayOf(0x52, 0x54, 0x4b)

    class DecodeException(val reason: Reason, message: String) : Exception(message) {
        enum class Reason {
            /** Old LZFSE file from an iPhone that hasn't synced since 2026-11-18. */
            LEGACY, BAD_HEADER, UNSUPPORTED_VERSION, TRUNCATED
        }
    }

    fun encode(points: List<TrackPoint>): ByteArray {
        val header = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
            .put(magic).put(VERSION).putInt(points.size).array()
        if (points.isEmpty()) return header

        val body = ByteBuffer.allocate(points.size * BYTES_PER_POINT).order(ByteOrder.LITTLE_ENDIAN)
        for (p in points) {
            body.putDouble(p.t).putDouble(p.coordinate.latitude).putDouble(p.coordinate.longitude)
                .putFloat((p.altitude ?: Double.NaN).toFloat()).putFloat((p.speed ?: Double.NaN).toFloat())
                .putFloat((p.course ?: Double.NaN).toFloat()).putFloat(p.horizontalAccuracy.toFloat())
                .putFloat((p.lean ?: Double.NaN).toFloat())
        }
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, /* nowrap = raw DEFLATE */ true)
        val out = ByteArrayOutputStream()
        out.write(header)
        try {
            deflater.setInput(body.array())
            deflater.finish()
            val chunk = ByteArray(16 * 1024)
            while (!deflater.finished()) out.write(chunk, 0, deflater.deflate(chunk))
        } finally {
            deflater.end()
        }
        return out.toByteArray()
    }

    fun decode(data: ByteArray): List<TrackPoint> {
        if (data.size < 4 || data[0] != magic[0] || data[1] != magic[1] || data[2] != magic[2]) {
            throw DecodeException(DecodeException.Reason.LEGACY, "Track is in the old format; the iPhone upgrades it on its next sync")
        }
        if (data[3] != VERSION) throw DecodeException(DecodeException.Reason.UNSUPPORTED_VERSION, "Unsupported track version ${data[3]}")
        if (data.size < HEADER_SIZE) throw DecodeException(DecodeException.Reason.BAD_HEADER, "Track header is cut short")
        val count = ByteBuffer.wrap(data, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int.toLong() and 0xffffffffL
        if (count == 0L) return emptyList()
        if (count > Int.MAX_VALUE / BYTES_PER_POINT) throw DecodeException(DecodeException.Reason.BAD_HEADER, "Track is too large")

        val expected = count.toInt() * BYTES_PER_POINT
        val body = ByteArray(expected)
        val inflater = Inflater(true)
        try {
            inflater.setInput(data, HEADER_SIZE, data.size - HEADER_SIZE)
            var read = 0
            while (read < expected) {
                val n = inflater.inflate(body, read, expected - read)
                if (n == 0 && (inflater.finished() || inflater.needsInput() || inflater.needsDictionary())) break
                read += n
            }
            if (read < expected) throw DecodeException(DecodeException.Reason.TRUNCATED, "Track data is cut short")
        } catch (e: DataFormatException) {
            throw DecodeException(DecodeException.Reason.TRUNCATED, "Track data is damaged")
        } finally {
            inflater.end()
        }

        val buffer = ByteBuffer.wrap(body).order(ByteOrder.LITTLE_ENDIAN)
        fun optional(v: Float): Double? = if (v.isNaN()) null else v.toDouble()
        return List(count.toInt()) {
            val t = buffer.double
            val lat = buffer.double
            val lon = buffer.double
            val alt = buffer.float
            val speed = buffer.float
            val course = buffer.float
            val hAcc = buffer.float
            val lean = buffer.float
            TrackPoint(t, Coordinate(lat, lon), optional(alt), optional(speed), optional(course), hAcc.toDouble(), optional(lean))
        }
    }
}
