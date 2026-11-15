package com.directionalaudio.directional_audio

import android.media.audiofx.Equalizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // Kept outside the activity so the effect survives the activity being destroyed
        // (it still dies if Android kills the whole process; a foreground service is a later step).
        private var eq: Equalizer? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "directional/eq")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> result.success(start(call.argument<Int>("session") ?: 0))
                        "setLevels" -> {
                            setLevels(call.argument<List<Int>>("levels") ?: emptyList())
                            result.success(null)
                        }
                        "setEnabled" -> {
                            eq?.enabled = call.argument<Boolean>("on") ?: false
                            result.success(eq?.enabled ?: false)
                        }
                        "stop" -> {
                            release()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }

    private fun start(session: Int): Map<String, Any> {
        release()
        val e = Equalizer(0, session)
        eq = e
        e.enabled = false
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

    private fun setLevels(levels: List<Int>) {
        val e = eq ?: return
        val range = e.bandLevelRange
        val n = e.numberOfBands.toInt()
        for ((i, l) in levels.withIndex()) {
            if (i >= n) break
            e.setBandLevel(i.toShort(), l.coerceIn(range[0].toInt(), range[1].toInt()).toShort())
        }
    }

    private fun release() {
        try {
            eq?.release()
        } catch (_: Exception) {
        }
        eq = null
    }
}
