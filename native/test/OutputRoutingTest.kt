package com.directionalaudio.directional_audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OutputRoutingTest {
    private fun o(type: Int, name: String = "") = OutputRouting.Out(type, name)

    @Test
    fun speakerOnly() {
        assertEquals(o(2, "Speaker"), OutputRouting.primary(listOf(o(2, "Speaker"))))
    }

    @Test
    fun wiredHeadsetBeatsSpeaker() {
        val p = OutputRouting.primary(listOf(o(2, "Speaker"), o(3, "Headset")))
        assertEquals(3, p!!.type)
    }

    @Test
    fun usbHeadsetBeatsBluetoothAndWired() {
        val p = OutputRouting.primary(listOf(o(3, "Headset"), o(8, "Buds"), o(22, "USB-C")))
        assertEquals(22, p!!.type)
    }

    @Test
    fun bluetoothA2dpBeatsWired() {
        val p = OutputRouting.primary(listOf(o(3, "Headset"), o(8, "Buds")))
        assertEquals("Buds", p!!.name)
    }

    @Test
    fun callAndTelephonyAndSubmixNeverWin() {
        assertNull(OutputRouting.primary(listOf(o(7, "SCO"), o(18, ""), o(25, "submix"))))
        val p = OutputRouting.primary(listOf(o(7, "SCO"), o(2, "Speaker")))
        assertEquals(2, p!!.type)
    }

    @Test
    fun emptyAndUnknownTypes() {
        assertNull(OutputRouting.primary(emptyList()))
        assertNull(OutputRouting.primary(listOf(o(999, "weird"))))
    }

    @Test
    fun equalRankKeepsTheFirst() {
        val p = OutputRouting.primary(listOf(o(8, "A"), o(8, "B")))
        assertEquals("A", p!!.name)
    }

    @Test
    fun keyCombinesTypeAndName() {
        assertEquals("8|Buds", OutputRouting.key(o(8, "Buds")))
        assertEquals("3|", OutputRouting.key(o(3)))
    }

    @Test
    fun switchesOnlyWhenTheMainOutputChangesAndAnAssignmentExists() {
        assertTrue(OutputRouting.shouldSwitch("2|Speaker", "3|Headset", locked = false, hasSlot = true))
        assertTrue(OutputRouting.shouldSwitch(null, "3|Headset", locked = false, hasSlot = true))
        // same output again: a manual choice stays
        assertFalse(OutputRouting.shouldSwitch("3|Headset", "3|Headset", locked = false, hasSlot = true))
        // locked
        assertFalse(OutputRouting.shouldSwitch("2|Speaker", "3|Headset", locked = true, hasSlot = true))
        // nothing assigned: keep the current profile
        assertFalse(OutputRouting.shouldSwitch("2|Speaker", "3|Headset", locked = false, hasSlot = false))
        // no usable output
        assertFalse(OutputRouting.shouldSwitch("3|Headset", null, locked = false, hasSlot = true))
    }

    @Test
    fun retryBackoffStopsAfterThreeTries() {
        assertEquals(5_000L, OutputRouting.retryDelay(0))
        assertEquals(15_000L, OutputRouting.retryDelay(1))
        assertEquals(45_000L, OutputRouting.retryDelay(2))
        assertNull(OutputRouting.retryDelay(3))
        assertNull(OutputRouting.retryDelay(-1))
    }
}
