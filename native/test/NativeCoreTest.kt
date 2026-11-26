package com.directionalaudio.directional_audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The JVM test run has no libdacore.so (it is built for Android only). That is exactly the situation to test:
 * a missing library must come back as a readable ok=0 answer, never as a crash.
 */
class NativeCoreTest {
    @Test
    fun aMissingLibraryAnswersWithAnErrorInsteadOfThrowing() {
        val info = NativeCore.info()
        assertTrue(info, info.startsWith("ok=0;error="))
        assertTrue(info, info.contains("not loaded"))
        val bench = NativeCore.bench(2, 256, 480, 1000)
        assertTrue(bench, bench.startsWith("ok=0;error="))
        assertFalse(NativeCore.load())
        assertTrue(NativeCore.loadError().isNotEmpty())
    }

    @Test
    fun errorTextCannotBreakTheKeyValueFormat() {
        assertEquals("ok=0;error=a, b c d", NativeCore.fail("a; b\nc\rd"))
    }
}
