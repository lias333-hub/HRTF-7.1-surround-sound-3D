package com.directionalaudio.directional_audio

/**
 * Bookkeeping (no Android classes, so plain JVM unit tests cover it) of what the engine knows about every
 * effect it holds: "eq" (system equalizer or Dynamics Processing), "bass", "virt" and "loud".
 *
 * For each effect three separate facts are tracked, because "the sound is really being processed" needs all of them:
 *  - created: the system gave us the effect object;
 *  - applied: the last attempt to switch it on / set it worked (the effect is really on);
 *  - control: this app is the one controlling it (another app may take it over).
 *
 * [reason] turns that into the bypass reason the UI shows, looking only at the effects the user actually wants.
 * An effect nobody has reported on yet is treated as fine (unknown is not a failure), so every place that creates
 * an effect must report to [created].
 */
class EffectHealth {
    private class State(var created: Boolean, var applied: Boolean, var control: Boolean)

    private val states = LinkedHashMap<String, State>()

    /** The system did ([ok] true) or did not give us the effect. A fresh effect is assumed on and controlled. */
    @Synchronized
    fun created(name: String, ok: Boolean) {
        states[name] = State(ok, ok, ok)
    }

    /** Switching the effect on / setting it worked ([ok] true) or did not (it reads back as off). */
    @Synchronized
    fun applied(name: String, ok: Boolean) {
        states[name]?.applied = ok
    }

    /** The system told us this app has ([granted] true) or lost control of the effect. */
    @Synchronized
    fun control(name: String, granted: Boolean) {
        states[name]?.control = granted
    }

    /** The effect was released on purpose: forget it. */
    @Synchronized
    fun clear(name: String) {
        states.remove(name)
    }

    @Synchronized
    fun clearAll() {
        states.clear()
    }

    /**
     * Why wanted processing is not happening: [CREATE_FAILED] (not created, or could not be switched on),
     * [CONTROL_LOST] (another app owns it), or null. A failure to create wins over a loss of control.
     */
    @Synchronized
    fun reason(wanted: Collection<String>): String? {
        var lost = false
        for (n in wanted) {
            val s = states[n] ?: continue
            if (!s.created || !s.applied) return CREATE_FAILED
            if (!s.control) lost = true
        }
        return if (lost) CONTROL_LOST else null
    }

    /** One short line for the event log, for example "eq=ok bass=lost virt=failed". */
    @Synchronized
    fun describe(): String {
        if (states.isEmpty()) return "-"
        return states.entries.joinToString(" ") { e ->
            val s = e.value
            e.key + "=" + when {
                !s.created -> "failed"
                !s.applied -> "off"
                !s.control -> "lost"
                else -> "ok"
            }
        }
    }

    companion object {
        const val CREATE_FAILED = "create_failed"
        const val CONTROL_LOST = "control_lost"
    }
}
