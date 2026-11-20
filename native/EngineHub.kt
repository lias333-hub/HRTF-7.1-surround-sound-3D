package com.directionalaudio.directional_audio

import android.annotation.TargetApi
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
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

    // route watching
    private var watching = false
    private var watchStartedMs = 0L
    private var devCb: Any? = null
    private val routeRunnable = Runnable { rebuild() }

    fun init(c: Context) {
        if (appCtx == null) {
            appCtx = c.applicationContext
            try {
                wanted = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("wanted", false)
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

    fun status(): Map<String, Any?> {
        val outs = ArrayList<Map<String, Any>>()
        val c = appCtx
        if (c != null && Build.VERSION.SDK_INT >= 23) {
            try {
                val am = c.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                for (d in am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                    outs.add(mapOf("type" to d.type, "name" to (d.productName?.toString() ?: "")))
                }
            } catch (ignored: Exception) {
            }
        }
        return mapOf(
            "service" to running,
            "wanted" to wanted,
            "eqKind" to eqKind,
            "eqEnabled" to eqEnabled,
            "eqBands" to eqBands,
            "fxActive" to fxActive,
            "outputs" to outs,
            "error" to lastError,
            "rebuiltAt" to lastRebuildMs
        )
    }

    fun emit() {
        val s = sink ?: return
        val m = status()
        main.post {
            try {
                s.success(m)
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
        eqKind = "system"
        eqEnabled = false
        sysSession = session
        eqBands = e.numberOfBands.toInt()
        lastError = null
        persist()
        watchRoutes()
        emit()
        return eqMap(e)
    }

    fun setSysLevels(levels: List<Int>) {
        sysLevels = levels
        try {
            applySysLevels()
        } catch (e: Exception) {
            lastError = e.message ?: e.javaClass.simpleName
        }
        persist()
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
            dp = createDp(centers)
            dpCenters = centers
            eqKind = "dynamics"
            eqEnabled = false
            eqBands = centers.size
            lastError = null
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

    fun setDpGains(gains: List<Double>, preamp: Double) {
        dpGains = gains
        dpPreamp = preamp
        try {
            if (Build.VERSION.SDK_INT >= 28) applyDp()
        } catch (t: Throwable) {
            lastError = t.message ?: t.javaClass.simpleName
        }
        persist()
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

    // ---------------------------------------------------------------- rebuild after route change / restart

    /** Throws everything away and recreates it from the remembered settings. */
    fun rebuild() {
        var err: String? = null
        try {
            if (eqKind == "system") {
                releaseEq()
                val e = Equalizer(0, sysSession)
                eq = e
                applySysLevels()
                e.enabled = eqEnabled
                eqBands = e.numberOfBands.toInt()
            } else if (eqKind == "dynamics" && Build.VERSION.SDK_INT >= 28) {
                releaseDp()
                val d = createDp(dpCenters)
                dp = d
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
        lastError = err
        lastRebuildMs = System.currentTimeMillis()
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
            if (eqKind != "none" || fxActive) rebuild()
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
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("state", o.toString()).apply()
        } catch (ignored: Exception) {
        }
    }

    // ---------------------------------------------------------------- output (route) changes

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
