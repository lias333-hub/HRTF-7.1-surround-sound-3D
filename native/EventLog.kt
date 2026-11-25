package com.directionalaudio.directional_audio

import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Locale
import java.util.TimeZone

/**
 * A small rolling log of what the sound engine did (output changes, profile switches, effect rebuilds, bypass,
 * retries), kept in a file so it survives the process being killed. It exists so that a test on a real phone
 * leaves evidence that can be copied and read later. No Android imports: it is unit-tested on the JVM.
 *
 * Cost: events are rare (a handful per output change) and never come from the audio path. The file write goes
 * through [io], which the app points at a background thread, so the main thread only touches memory.
 */
class EventLog(
    private val file: File?,
    private val max: Int = 300,
    private val clock: () -> Long = { System.currentTimeMillis() },
    tz: TimeZone = TimeZone.getDefault(),
    private val io: (Runnable) -> Unit = { it.run() }
) {
    private val lines = ArrayDeque<String>()
    private val fmt = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).also { it.timeZone = tz }
    private var sinceCompact = 0

    init {
        try {
            if (file != null && file.exists()) {
                for (l in file.readLines()) {
                    if (l.isNotBlank()) lines.addLast(l)
                }
                while (lines.size > max) lines.removeFirst()
            }
        } catch (ignored: Exception) {
        }
    }

    /** [tag] is a short word ("route", "switch", "rebuild", ...), [msg] one line of detail. */
    @Synchronized
    fun add(tag: String, msg: String) {
        val line = "${fmt.format(clock())} [$tag] ${msg.replace('\n', ' ').replace('\r', ' ')}"
        lines.addLast(line)
        while (lines.size > max) lines.removeFirst()
        sinceCompact++
        val f = file ?: return
        if (sinceCompact >= max) {
            // The file grew to about twice the limit: rewrite it from memory.
            sinceCompact = 0
            val snapshot = lines.joinToString("\n", postfix = "\n")
            io(Runnable {
                try {
                    f.writeText(snapshot)
                } catch (ignored: Exception) {
                }
            })
        } else {
            io(Runnable {
                try {
                    f.appendText(line + "\n")
                } catch (ignored: Exception) {
                }
            })
        }
    }

    @Synchronized
    fun text(): String = lines.joinToString("\n")

    @Synchronized
    fun size(): Int = lines.size

    @Synchronized
    fun clear() {
        lines.clear()
        sinceCompact = 0
        val f = file ?: return
        io(Runnable {
            try {
                f.writeText("")
            } catch (ignored: Exception) {
            }
        })
    }
}
