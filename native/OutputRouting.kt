package com.directionalaudio.directional_audio

/**
 * Pure decision logic for per-output profiles. It uses no Android classes on purpose, so it runs in plain
 * JVM unit tests (native/test/OutputRoutingTest.kt).
 */
object OutputRouting {
    /** One audio output as reported by AudioDeviceInfo: its type constant and product name. */
    data class Out(val type: Int, val name: String)

    /**
     * How much an output type is preferred as "where the music goes" (AudioDeviceInfo.TYPE_* values).
     * 0 means: never the target of music (call audio, telephony, remote submix, unknown types).
     * This is a fixed guess: Android does not tell us the route that is really in use below API 33.
     */
    fun rank(type: Int): Int = when (type) {
        22 -> 100 // USB headset
        26 -> 95 // Bluetooth LE headset
        27 -> 94 // Bluetooth LE speaker
        8 -> 90 // Bluetooth A2DP
        3 -> 85 // wired headset
        4 -> 84 // wired headphones
        11, 12 -> 80 // USB device / accessory
        5 -> 70 // analog line out
        23 -> 65 // hearing aid
        30 -> 60 // Bluetooth LE broadcast
        9, 10, 29 -> 50 // HDMI
        2 -> 20 // built-in speaker
        24 -> 19 // built-in speaker (safe)
        1 -> 10 // earpiece
        else -> 0
    }

    /** The output that music most likely uses, or null when nothing usable is connected. */
    fun primary(outs: List<Out>): Out? {
        var best: Out? = null
        var bestRank = 0
        for (o in outs) {
            val r = rank(o.type)
            if (r > bestRank) {
                best = o
                bestRank = r
            }
        }
        return best
    }

    /** Stable identity of an output, used as the key of the saved profile table. */
    fun key(o: Out): String = "${o.type}|${o.name}"

    /**
     * Should the equalizer switch to the profile assigned to the current output?
     * Only when the main output actually changed, nothing is locked and the new output has an assignment:
     * a plain "another device appeared" event must not undo a profile the user picked by hand.
     */
    fun shouldSwitch(prevKey: String?, curKey: String?, locked: Boolean, hasSlot: Boolean): Boolean =
        !locked && hasSlot && curKey != null && curKey != prevKey

    private val RETRY_MS = longArrayOf(5_000, 15_000, 45_000)

    /** Delay before automatic retry number [attempt] (0-based) after the effects could not be (re)built; null = give up. */
    fun retryDelay(attempt: Int): Long? = if (attempt in RETRY_MS.indices) RETRY_MS[attempt] else null
}
