package com.directionalaudio.directional_audio

import java.io.File
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EventLogTest {
    private val utc = TimeZone.getTimeZone("UTC")

    private fun tmp(): File {
        val f = File.createTempFile("events", ".log")
        f.deleteOnExit()
        return f
    }

    @Test
    fun linesAreTimestampedTaggedAndOrdered() {
        var t = 1_700_000_000_000L // 2023-11-14 22:13:20 UTC
        val log = EventLog(null, clock = { t }, tz = utc)
        log.add("route", "main=3|Headset")
        t += 1_250
        log.add("switch", "to Bass")
        assertEquals(
            "11-14 22:13:20.000 [route] main=3|Headset\n11-14 22:13:21.250 [switch] to Bass",
            log.text()
        )
        assertEquals(2, log.size())
    }

    @Test
    fun keepsOnlyTheNewestLines() {
        val log = EventLog(null, max = 5, tz = utc)
        for (i in 1..12) log.add("t", "e$i")
        assertEquals(5, log.size())
        val l = log.text().lines()
        assertTrue(l.first().endsWith("e8"))
        assertTrue(l.last().endsWith("e12"))
    }

    @Test
    fun newlinesInAMessageDoNotBreakTheLine() {
        val log = EventLog(null, tz = utc)
        log.add("err", "a\nb\r\nc")
        assertEquals(1, log.text().lines().size)
        assertTrue(log.text().endsWith("a b  c"))
    }

    @Test
    fun survivesBeingReopened() {
        val f = tmp()
        val a = EventLog(f, tz = utc)
        a.add("proc", "started")
        a.add("route", "changed")
        val b = EventLog(f, tz = utc) // like a new process reading the same file
        assertEquals(a.text(), b.text())
        b.add("proc", "again")
        assertEquals(3, EventLog(f, tz = utc).size())
    }

    @Test
    fun fileStaysBoundedAndKeepsTheNewestLines() {
        val f = tmp()
        val log = EventLog(f, max = 10, tz = utc)
        for (i in 1..95) log.add("t", "e$i")
        val onDisk = f.readLines().filter { it.isNotBlank() }
        assertTrue("file has ${onDisk.size} lines", onDisk.size <= 20)
        val reopened = EventLog(f, max = 10, tz = utc)
        assertEquals(10, reopened.size())
        assertTrue(reopened.text().lines().last().endsWith("e95"))
        assertTrue(reopened.text().lines().first().endsWith("e86"))
    }

    @Test
    fun clearEmptiesMemoryAndFile() {
        val f = tmp()
        val log = EventLog(f, tz = utc)
        log.add("t", "x")
        log.clear()
        assertEquals(0, log.size())
        assertFalse(f.readText().isNotBlank())
        assertEquals(0, EventLog(f, tz = utc).size())
    }

    @Test
    fun anUnwritableFileNeverThrows() {
        val dir = java.nio.file.Files.createTempDirectory("evlog").toFile()
        dir.deleteOnExit()
        val log = EventLog(dir, tz = utc) // a directory is not a writable log file
        log.add("t", "still works in memory")
        assertEquals(1, log.size())
    }
}
