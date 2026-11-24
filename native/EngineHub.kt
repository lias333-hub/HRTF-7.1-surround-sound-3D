package com.directionalaudio.directional_audio

import android.annotation.TargetApi
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Owns every live audio effect, so they outlive the activity and can be rebuilt after the sound output
 * changes (headphones plugged in or out, Bluetooth connecting) or after the service is restarted.
 *
 * Two equalizer back ends share one slot ([eqKind]):
 *  - "system": android.media.audiofx.Equalizer (few bands on most phones, works on old Android)
 *  - "dynamics": DynamicsProcessing, Android 9+, one real band per UI band plus a limiter
 * Whatever the user last asked for is kept in plain fields and saved to SharedPreferences, so
 * [rebuild] can recreate everything from scratch.
 */
object EngineHub {
    private const val PREFS = "engine_state"

    private var appCtx: Context? = null
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var sink: EventChannel.EventSink? = null

    // live effect objects
    private var eq: Equalizer? = null
    private var dp: DynamicsProcessing? = null
    private var bass: BassBoost? = null
    private var virt: Virtualizer? = null
    private var loud: LoudnessEnhancer? = null

    // what the user asked for (this is what gets saved and replayed)
    private var eqKind = "none" // "none" | "system" | "dynamics"
    private var eqEnabled = false
    private var sysSession = 0
    private var sysLevels: List<Int> = emptyList()
    private var dpCenters: List<Double> = emptyList()
    private var dpGains: List<Double> = emptyList()
    private var dpPreamp = 0.0
    private var fxActive = false
    private val fxOn = hashMapOf("bass" to false, "virt" to false, "loud" to false)
    private val fxVal = hashMapOf("bass" to 0, "virt" to 0, "loud" to 0)

    private var running = false
    private var wanted = false
    private var lastError: String? = null
    private var lastRebuildMs = 0L
    private var eqBands = 0

    // per-output profiles. The table lives here (not in Dart) because an output can change while the service
    // runs without any screen. Dart only edits it. "levels" are the millibel values for the system equalizer,
    // computed by Dart (it owns that maths), so a slot is applied without any calculation here.
    private class Slot(
        val key: String,
        val type: Int,
        val name: String,
        val profile: String,
        val gains: List<Double>,
        val preamp: Double,
        val levels: List<Int>
    )

    private val slots = LinkedHashMap<String, Slot>()
    private var profile = "" // name of the profile last applied ("" = never told)
    private var locked = false // manual lock: no automatic profile switch on output changes
    private var lastKey: String? = null // main output the last time we looked
    private var switchSeq = 0 // grows each time a profile was switched automatically (not saved)

    // bypass: the user wants processing but the sound is passing through untouched
    private var createFailed = false
    private var controlLost = false
    private var retryAttempt = 0

    /** Set by the service so the notification can show the bypass state. Called on the main thread. */
    @Volatile
    var stateListener: ((String?) -> Unit)? = null

    // route watching
    private var watching = false
    private var watchStartedMs = 0L
    private var devCb: Any? = null
    private val routeRunnable = Runnable { onRouteChange() }
    private val retryRunnable = Runnable { rebuild() }

    fun init(c: Context) {
        if (appCtx == null) {
            appCtx = c.applicationContext
            try {
                val p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                wanted = p.getBoolean("wanted", false)
                loadAssignments(p.getString("state", null))
            } catch (ignored: Exception) {
            }
        }
    }

    // ---------------------------------------------------------------- status for the UI

    fun markService(v: Boolean) {
        running = v
        if (!v) maybeUnwatch()
        emit()
    }

    /** "The user wants the service running": survives process death so the app can restart it. */
    fun setWanted(v: Boolean) {
        wanted = v
        try {
            appCtx?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()?.putBoolean("wanted", v)?.apply()
        } catch (ignored: Exception) {
        }
        emit()
    }

    /** Every output the system lists right now. */
    private fun currentOutputs(): List<OutputRouting.Out> {
        val out = ArrayList<OutputRouting.Out>()
        val c = appCtx
        if (c != null && Build.VERSION.SDK_INT >= 23) {
            try {
                val am = c.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                for (d in am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                    out.add(OutputRouting.Out(d.type, d.productName?.toString() ?: ""))
                }
            } catch (ignored: Exception) {
            }
        }
        return out
    }

    /** Why the sound is not being processed although the user wants it ("create_failed" / "control_lost"), or null. */
    private fun bypassReason(): String? {
        val wantsProcessing = (eqKind != "none" && eqEnabled) || (fxActive && fxOn.values.any { it })
        if (!wantsProcessing) return null
        return if (createFailed) "create_failed" else if (controlLost) "control_lost" else null
    }

    fun bypass(): String? = bypassReason()

    fun status(): Map<String, Any?> {
        val outs = currentOutputs()
        val cur = OutputRouting.primary(outs)
        val assigned = ArrayList<Map<String, Any>>()
        for (s in slots.values) {
            assigned.add(mapOf("key" to s.key, "type" to s.type, "name" to s.name, "profile" to s.profile))
        }
        return mapOf(
            "service" to running,
            "wanted" to wanted,
            "eqKind" to eqKind,
            "eqEnabled" to eqEnabled,
            "eqBands" to eqBands,
            "fxActive" to fxActive,
            "outputs" to outs.map { mapOf("type" to it.type, "name" to it.name) },
            "error" to lastError,
            "rebuiltAt" to lastRebuildMs,
            "profile" to profile,
            "switchSeq" to switchSeq,
            "locked" to locked,
            "bypass" to bypassReason(),
            "output" to (if (cur == null) null else mapOf(
                "key" to OutputRouting.key(cur), "type" to cur.type, "name" to cur.name
            )),
            "assignments" to assigned
        )
    }

    fun emit() {
        val m = status()
        main.post {
            try {
                sink?.success(m)
            } catch (ignored: Exception) {
            }
            try {
                stateListener?.invoke(m["bypass"] as String?)
            } catch (ignored: Exception) {
            }
        }
    }

    // ---------------------------------------------------------------- system equalizer

    fun eqMap(e: Equalizer): Map<String, Any> {
        val n = e.numberOfBands.toInt()
        val range = e.bandLevelRange
        val centers = ArrayList<Double>()
        val lows = ArrayList<Double>()
        val highs = ArrayList<Double>()
        for (i in 0 until n) {
            val b = i.toShort()
            centers.add(e.getCenterFreq(b) / 1000.0)
            val r = e.getBandFreqRange(b)
            lows.add(r[0] / 1000.0)
            highs.add(r[1] / 1000.0)
        }
        return mapOf(
            "bands" to n,
            "minLevel" to range[0].toInt(),
            "maxLevel" to range[1].toInt(),
            "centers" to centers,
            "lows" to lows,
            "highs" to highs
        )
    }

    /** The live system equalizer's bands, or null when none is running. */
    fun systemEqMap(): Map<String, Any>? {
        val e = eq ?: return null
        return eqMap(e)
    }

    fun startSystem(session: Int): Map<String, Any> {
        releaseEq()
        releaseDp()
        eqKind = "none"
        val e = Equalizer(0, session)
        e.enabled = false
        eq = e
        watchControl(e)
        eqKind = "system"
        eqEnabled = false
        sysSession = session
        eqBands = e.numberOfBands.toInt()
        lastError = null
        createFailed = false
        persist()
        watchRoutes()
        emit()
        return eqMap(e)
    }

    /** [profileName]: which saved profile these levels come from, so the hub knows what is applied. */
    fun setSysLevels(levels: List<Int>, profileName: String? = null) {
        sysLevels = levels
        if (profileName != null) profile = profileName
        try {
            applySysLevels()
        } catch (e: Exception) {
            lastError = e.message ?: e.javaClass.simpleName
        }
        persist()
        emit()
    }

    private fun applySysLevels() {
        val e = eq ?: return
        val range = e.bandLevelRange
        val n = e.numberOfBands.toInt()
        for ((i, l) in sysLevels.withIndex()) {
            if (i >= n) break
            e.setBandLevel(i.toShort(), l.coerceIn(range[0].toInt(), range[1].toInt()).toShort())
        }
    }

    // ---------------------------------------------------------------- dynamics processing equalizer

    /** One band per entry of [centers] (Hz). Never throws: the reason is returned so the UI can fall back. */
    fun startDynamics(centers: List<Double>): Map<String, Any> {
        releaseEq()
        releaseDp()
        eqKind = "none"
        if (Build.VERSION.SDK_INT < 28) return mapOf("ok" to false, "error" to "needs Android 9+")
        if (centers.isEmpty()) return mapOf("ok" to false, "error" to "no bands")
        return try {
            val d = createDp(centers)
            dp = d
            watchControl(d)
            dpCenters = centers
            eqKind = "dynamics"
            eqEnabled = false
            eqBands = centers.size
            lastError = null
            createFailed = false
            persist()
            watchRoutes()
            emit()
            mapOf("ok" to true, "bands" to centers.size)
        } catch (t: Throwable) {
            releaseDp()
            mapOf("ok" to false, "error" to (t.message ?: t.javaClass.simpleName))
        }
    }

    /** Can a Dynamics Processing effect be created on the global mix here? (Does not prove it is audible.) */
    fun probeDynamics(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < 28) return mapOf("ok" to false, "error" to "needs Android 9+")
        if (dp != null) return mapOf("ok" to true)
        return try {
            val d = createDp(listOf(100.0, 1000.0))
            d.release()
            mapOf("ok" to true)
        } catch (t: Throwable) {
            mapOf("ok" to false, "error" to (t.message ?: t.javaClass.simpleName))
        }
    }

    fun setDpGains(gains: List<Double>, preamp: Double, profileName: String? = null) {
        dpGains = gains
        dpPreamp = preamp
        if (profileName != null) profile = profileName
        try {
            if (Build.VERSION.SDK_INT >= 28) applyDp()
        } catch (t: Throwable) {
            lastError = t.message ?: t.javaClass.simpleName
        }
        persist()
        emit()
    }

    // Band i covers everything up to its cutoff; cutoffs sit halfway (geometric mean) between centres.
    private fun cutoffs(c: List<Double>): List<Float> {
        val out = ArrayList<Float>()
        for (i in c.indices) {
            val hi = if (i + 1 < c.size) Math.sqrt(c[i] * c[i + 1]) else 20000.0
            out.add(hi.toFloat().coerceAtMost(20000f))
        }
        return out
    }

    @TargetApi(28)
    private fun createDp(centers: List<Double>): DynamicsProcessing {
        val n = centers.size
        val cfg = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            2,
            true, n,
            false, 0,
            false, 0,
            true
        ).build()
        val d = DynamicsProcessing(0, 0, cfg)
        val cut = cutoffs(centers)
        for (i in 0 until n) {
            d.setPreEqBandAllChannelsTo(i, DynamicsProcessing.EqBand(true, cut[i], 0f))
        }
        // A gentle limiter so boosted curves do not clip.
        d.setLimiterAllChannelsTo(DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -1f, 0f))
        d.setInputGainAllChannelsTo(0f)
        d.enabled = false
        return d
    }

    @TargetApi(28)
    private fun applyDp() {
        val d = dp ?: return
        val cut = cutoffs(dpCenters)
        for (i in dpGains.indices) {
            if (i >= cut.size) break
            val g = dpGains[i].coerceIn(-15.0, 15.0).toFloat()
            d.setPreEqBandAllChannelsTo(i, DynamicsProcessing.EqBand(true, cut[i], g))
        }
        d.setInputGainAllChannelsTo(dpPreamp.coerceIn(-24.0, 24.0).toFloat())
    }

    // ---------------------------------------------------------------- shared equalizer controls

    /** Turns whichever equalizer is active on or off; returns whether it is now on. */
    fun setEqEnabled(on: Boolean): Boolean {
        eqEnabled = on
        var effective = false
        try {
            val e = eq
            if (e != null) {
                e.enabled = on
                effective = e.enabled
            }
            effective = effective || setDpEnabled(on)
        } catch (t: Throwable) {
            lastError = t.message ?: t.javaClass.simpleName
        }
        persist()
        emit()
        return effective
    }

    private fun setDpEnabled(on: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < 28) return false
        val d = dp ?: return false
        d.enabled = on
        return d.enabled
    }

    fun stopEq() {
        releaseEq()
        releaseDp()
        eqKind = "none"
        eqEnabled = false
        eqBands = 0
        persist()
        maybeUnwatch()
        emit()
    }

    private fun releaseEq() {
        try {
            eq?.release()
        } catch (ignored: Exception) {
        }
        eq = null
    }

    private fun releaseDp() {
        try {
            dp?.release()
        } catch (ignored: Throwable) {
        }
        dp = null
    }

    // ---------------------------------------------------------------- bass boost / virtualizer / loudness

    private fun failure(e: Throwable): Map<String, Any> =
        mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName))

    private fun fxCreate(): Map<String, Any> {
        val out = HashMap<String, Any>()

        out["bass"] = try {
            val b = BassBoost(0, 0)
            bass = b
            b.enabled = false
            mapOf("ok" to true, "strengthSupported" to b.strengthSupported)
        } catch (e: Exception) {
            failure(e)
        }

        out["virt"] = try {
            val v = Virtualizer(0, 0)
            virt = v
            v.enabled = false
            mapOf("ok" to true, "strengthSupported" to v.strengthSupported)
        } catch (e: Exception) {
            failure(e)
        }

        out["loud"] = try {
            val l = LoudnessEnhancer(0)
            loud = l
            l.enabled = false
            mapOf("ok" to true, "strengthSupported" to true)
        } catch (e: Exception) {
            failure(e)
        }

        return out
    }

    fun fxStart(): Map<String, Any> {
        fxRelease()
        val out = fxCreate()
        fxActive = true
        persist()
        watchRoutes()
        emit()
        return out
    }

    // value: strength 0..1000 for bass/virt; gain in millibels for loud.
    fun fxSet(name: String, on: Boolean, value: Int) {
        if (!fxOn.containsKey(name)) return
        fxOn[name] = on
        fxVal[name] = value
        try {
            fxApply(name)
        } catch (e: Exception) {
            lastError = e.message ?: e.javaClass.simpleName
        }
        persist()
        emit()
    }

    private fun fxApply(name: String) {
        val on = fxOn[name] ?: false
        val value = fxVal[name] ?: 0
        when (name) {
            "bass" -> {
                val b = bass
                if (b != null) {
                    if (b.strengthSupported) b.setStrength(value.coerceIn(0, 1000).toShort())
                    b.enabled = on
                }
            }
            "virt" -> {
                val v = virt
                if (v != null) {
                    if (v.strengthSupported) v.setStrength(value.coerceIn(0, 1000).toShort())
                    v.enabled = on
                }
            }
            "loud" -> {
                val l = loud
                if (l != null) {
                    l.setTargetGain(value.coerceIn(0, 1500))
                    l.enabled = on
                }
            }
        }
    }

    fun fxStop() {
        fxRelease()
        fxActive = false
        persist()
        maybeUnwatch()
        emit()
    }

    private fun fxRelease() {
        try {
            bass?.release()
        } catch (ignored: Exception) {
        }
        try {
            virt?.release()
        } catch (ignored: Exception) {
        }
        try {
            loud?.release()
        } catch (ignored: Exception) {
        }
        bass = null
        virt = null
        loud = null
    }

    // ---------------------------------------------------------------- bypass (state + return rule)

    /**
     * Another app may take over the effect (only one app controls an effect type at a time). The system tells us;
     * the sound is then unprocessed, which must be visible and must come back by itself when possible.
     */
    private fun watchControl(e: AudioEffect) {
        controlLost = try {
            !e.hasControl()
        } catch (ignored: Exception) {
            false
        }
        try {
            e.setControlStatusListener { _, granted ->
                controlLost = !granted
                if (controlLost) scheduleRetry() else cancelRetry()
                emit()
            }
        } catch (ignored: Exception) {
        }
    }

    private fun scheduleRetry() {
        main.removeCallbacks(retryRunnable)
        val d = OutputRouting.retryDelay(retryAttempt) ?: return
        retryAttempt++
        main.postDelayed(retryRunnable, d)
    }

    private fun cancelRetry() {
        retryAttempt = 0
        main.removeCallbacks(retryRunnable)
    }

    /** User pressed "retry", the app came back to the screen, or the output changed: start the return rule over. */
    fun retryNow() {
        cancelRetry()
        rebuild()
    }

    // ---------------------------------------------------------------- rebuild after route change / restart

    /** Throws everything away and recreates it from the remembered settings. */
    fun rebuild() {
        var err: String? = null
        controlLost = false
        try {
            if (eqKind == "system") {
                releaseEq()
                val e = Equalizer(0, sysSession)
                eq = e
                watchControl(e)
                applySysLevels()
                e.enabled = eqEnabled
                eqBands = e.numberOfBands.toInt()
            } else if (eqKind == "dynamics" && Build.VERSION.SDK_INT >= 28) {
                releaseDp()
                val d = createDp(dpCenters)
                dp = d
                watchControl(d)
                if (dpGains.isNotEmpty()) applyDp()
                d.enabled = eqEnabled
                eqBands = dpCenters.size
            }
        } catch (t: Throwable) {
            err = t.message ?: t.javaClass.simpleName
        }
        if (fxActive) {
            try {
                fxRelease()
                fxCreate()
                for (k in fxOn.keys.toList()) fxApply(k)
            } catch (t: Throwable) {
                err = err ?: (t.message ?: t.javaClass.simpleName)
            }
        }
        createFailed = err != null
        lastError = err
        lastRebuildMs = System.currentTimeMillis()
        // The return rule: while the sound is unprocessed, try again by itself (5 s, 15 s, 45 s), then wait for
        // the next output change, app resume or the user's retry button.
        if (createFailed || controlLost) scheduleRetry() else cancelRetry()
        emit()
    }

    /** After the process was killed and the service restarted: read the saved settings and rebuild. */
    fun restoreIfEmpty() {
        if (eqKind != "none" || fxActive) return
        val c = appCtx ?: return
        try {
            val raw = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("state", null) ?: return
            val o = JSONObject(raw)
            eqKind = o.optString("kind", "none")
            eqEnabled = o.optBoolean("enabled", false)
            sysSession = o.optInt("session", 0)
            sysLevels = ints(o.optJSONArray("sysLevels"))
            dpCenters = doubles(o.optJSONArray("centers"))
            dpGains = doubles(o.optJSONArray("gains"))
            dpPreamp = o.optDouble("preamp", 0.0)
            fxActive = o.optBoolean("fxActive", false)
            val on = o.optJSONObject("fxOn")
            val v = o.optJSONObject("fxVal")
            for (k in fxOn.keys.toList()) {
                fxOn[k] = on?.optBoolean(k, false) ?: false
                fxVal[k] = v?.optInt(k, 0) ?: 0
            }
            profile = o.optString("profile", "")
            loadAssignments(raw)
            // The output may have changed while the process was dead: pick the profile for it, then rebuild.
            if (eqKind != "none" || fxActive) onRouteChange()
        } catch (ignored: Exception) {
        }
    }

    /** The per-output table, the lock and the last seen main output (all survive a process restart). */
    private fun loadAssignments(raw: String?) {
        if (raw == null) return
        try {
            val o = JSONObject(raw)
            locked = o.optBoolean("locked", false)
            val lk = o.optString("lastKey", "")
            lastKey = if (lk.isEmpty()) null else lk
            slots.clear()
            val arr = o.optJSONArray("slots")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val so = arr.optJSONObject(i) ?: continue
                    val key = so.optString("key", "")
                    if (key.isEmpty()) continue
                    slots[key] = Slot(
                        key,
                        so.optInt("type", 0),
                        so.optString("name", ""),
                        so.optString("profile", ""),
                        doubles(so.optJSONArray("gains")),
                        so.optDouble("preamp", 0.0),
                        ints(so.optJSONArray("levels"))
                    )
                }
            }
        } catch (ignored: Exception) {
        }
    }

    private fun ints(a: JSONArray?): List<Int> {
        val l = ArrayList<Int>()
        if (a != null) for (i in 0 until a.length()) l.add(a.optInt(i))
        return l
    }

    private fun doubles(a: JSONArray?): List<Double> {
        val l = ArrayList<Double>()
        if (a != null) for (i in 0 until a.length()) l.add(a.optDouble(i))
        return l
    }

    private fun persist() {
        val c = appCtx ?: return
        try {
            val o = JSONObject()
            o.put("kind", eqKind)
            o.put("enabled", eqEnabled)
            o.put("session", sysSession)
            o.put("sysLevels", JSONArray(sysLevels))
            o.put("centers", JSONArray(dpCenters))
            o.put("gains", JSONArray(dpGains))
            o.put("preamp", dpPreamp)
            o.put("fxActive", fxActive)
            val on = JSONObject()
            val v = JSONObject()
            for (k in fxOn.keys) {
                on.put(k, fxOn[k] ?: false)
                v.put(k, fxVal[k] ?: 0)
            }
            o.put("fxOn", on)
            o.put("fxVal", v)
            o.put("profile", profile)
            o.put("locked", locked)
            o.put("lastKey", lastKey ?: "")
            val arr = JSONArray()
            for (sl in slots.values) {
                val so = JSONObject()
                so.put("key", sl.key)
                so.put("type", sl.type)
                so.put("name", sl.name)
                so.put("profile", sl.profile)
                so.put("gains", JSONArray(sl.gains))
                so.put("preamp", sl.preamp)
                so.put("levels", JSONArray(sl.levels))
                arr.put(so)
            }
            o.put("slots", arr)
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("state", o.toString()).apply()
        } catch (ignored: Exception) {
        }
    }

    // ---------------------------------------------------------------- per-output profiles

    fun assignOutput(
        key: String, type: Int, name: String, profileName: String,
        gains: List<Double>, preamp: Double, levels: List<Int>
    ) {
        if (key.isEmpty()) return
        slots[key] = Slot(key, type, name, profileName, gains, preamp, levels)
        persist()
        emit()
    }

    fun unassignOutput(key: String) {
        slots.remove(key)
        persist()
        emit()
    }

    fun setLocked(v: Boolean) {
        locked = v
        persist()
        emit()
    }

    private fun applySlot(s: Slot) {
        switchSeq++
        profile = s.profile
        dpGains = s.gains
        dpPreamp = s.preamp
        if (s.levels.isNotEmpty()) sysLevels = s.levels
    }

    /**
     * Looks at the main output now and, when the rules in [OutputRouting.shouldSwitch] allow it, loads the profile
     * assigned to it into the remembered settings (the effects are updated by the caller). True when it switched.
     */
    private fun decideProfile(): Boolean {
        val cur = OutputRouting.primary(currentOutputs())
        val curKey = if (cur == null) null else OutputRouting.key(cur)
        val slot = if (curKey == null) null else slots[curKey]
        var switched = false
        if (slot != null && OutputRouting.shouldSwitch(lastKey, curKey, locked, true)) {
            applySlot(slot)
            switched = true
        }
        lastKey = curKey
        persist()
        return switched
    }

    /**
     * Dart calls this right after it started the equalizer: if the main output changed since last time (or the
     * process was restarted), the assigned profile is applied now. Returns the new status.
     */
    fun syncOutput(): Map<String, Any?> {
        val switched = decideProfile()
        if (switched) {
            try {
                if (eqKind == "system") {
                    applySysLevels()
                } else if (eqKind == "dynamics" && Build.VERSION.SDK_INT >= 28) {
                    applyDp()
                }
            } catch (t: Throwable) {
                lastError = t.message ?: t.javaClass.simpleName
            }
        }
        emit()
        return status() + mapOf("switched" to switched)
    }

    // ---------------------------------------------------------------- output (route) changes

    /** The debounced reaction to a device being added or removed. */
    fun onRouteChange() {
        decideProfile()
        retryNow()
    }

    private fun routeChanged() {
        // Registering the callback reports every existing device once: ignore that burst.
        if (System.currentTimeMillis() - watchStartedMs < 1500) return
        main.removeCallbacks(routeRunnable)
        main.postDelayed(routeRunnable, 700)
    }

    @TargetApi(23)
    fun watchRoutes() {
        val c = appCtx ?: return
        if (watching || Build.VERSION.SDK_INT < 23) return
        try {
            val am = c.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val cb = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                    routeChanged()
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                    routeChanged()
                }
            }
            watchStartedMs = System.currentTimeMillis()
            am.registerAudioDeviceCallback(cb, main)
            devCb = cb
            watching = true
        } catch (ignored: Exception) {
        }
    }

    @TargetApi(23)
    private fun maybeUnwatch() {
        if (!watching || running || eqKind != "none" || fxActive) return
        val c = appCtx ?: return
        try {
            val am = c.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val cb = devCb as? AudioDeviceCallback
            if (cb != null) am.unregisterAudioDeviceCallback(cb)
        } catch (ignored: Exception) {
        }
        devCb = null
        watching = false
        main.removeCallbacks(routeRunnable)
    }
}
