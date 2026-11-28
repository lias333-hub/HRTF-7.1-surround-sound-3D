package com.directionalaudio.directional_audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EffectHealthTest {
    private val eqOnly = listOf("eq")

    @Test
    fun nothingReportedIsFine() {
        assertNull(EffectHealth().reason(listOf("eq", "bass")))
    }

    @Test
    fun createdAndControlledIsFine() {
        val h = EffectHealth()
        h.created("eq", true)
        assertNull(h.reason(eqOnly))
    }

    @Test
    fun failedCreationIsReportedOnlyWhenThatEffectIsWanted() {
        val h = EffectHealth()
        h.created("eq", true)
        h.created("bass", false)
        assertNull(h.reason(eqOnly)) // bass is not wanted: no bypass
        assertEquals(EffectHealth.CREATE_FAILED, h.reason(listOf("eq", "bass")))
    }

    @Test
    fun lostControlOfAnFxEffectIsSeen() {
        val h = EffectHealth()
        h.created("virt", true)
        h.control("virt", false)
        assertEquals(EffectHealth.CONTROL_LOST, h.reason(listOf("virt")))
        h.control("virt", true)
        assertNull(h.reason(listOf("virt")))
    }

    @Test
    fun createFailureWinsOverLostControl() {
        val h = EffectHealth()
        h.created("eq", true)
        h.control("eq", false)
        h.created("loud", false)
        assertEquals(EffectHealth.CREATE_FAILED, h.reason(listOf("eq", "loud")))
    }

    @Test
    fun anEffectThatCouldNotBeSwitchedOnCountsAsFailed() {
        val h = EffectHealth()
        h.created("eq", true)
        h.applied("eq", false)
        assertEquals(EffectHealth.CREATE_FAILED, h.reason(eqOnly))
        h.applied("eq", true)
        assertNull(h.reason(eqOnly))
    }

    @Test
    fun aFreshCreationForgetsTheOldFailure() {
        val h = EffectHealth()
        h.created("bass", false)
        h.created("bass", true)
        assertNull(h.reason(listOf("bass")))
    }

    @Test
    fun clearForgetsAnEffectSoOldBypassCannotLinger() {
        val h = EffectHealth()
        h.created("eq", true)
        h.control("eq", false)
        h.clear("eq")
        assertNull(h.reason(eqOnly))
        h.control("eq", false) // late callback of a released effect: ignored
        assertNull(h.reason(eqOnly))
    }

    @Test
    fun describeListsEveryEffect() {
        val h = EffectHealth()
        assertEquals("-", h.describe())
        h.created("eq", true)
        h.created("bass", false)
        h.created("virt", true)
        h.control("virt", false)
        h.created("loud", true)
        h.applied("loud", false)
        assertEquals("eq=ok bass=failed virt=lost loud=off", h.describe())
    }
}
