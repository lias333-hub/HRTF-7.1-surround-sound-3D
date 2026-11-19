package com.directionalaudio.directional_audio

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // Kept outside the activity so the effects survive the activity being destroyed
        // (they still die if Android kills the whole process; a foreground service is a later step).
        private var eq: Equalizer? = null
        private var bass: BassBoost? = null
        private var virt: Virtualizer? = null
        private var loud: LoudnessEnhancer? = null

        // Each new test tone gets a new token; an older tone stops when it sees the token changed.
        @Volatile
        private var toneToken = 0
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
                            releaseEq()
                            result.success(null)
                        }
                        "deviceInfo" -> result.success(deviceInfo())
                        "fxStart" -> result.success(fxStart())
                        "fxSet" -> {
                            fxSet(
                                call.argument<String>("name") ?: "",
                                call.argument<Boolean>("on") ?: false,
                                call.argument<Int>("value") ?: 0
                            )
                            result.success(null)
                        }
                        "fxStop" -> {
                            fxStop()
                            result.success(null)
                        }
                        "tone" -> {
                            playTone(
                                call.argument<String>("channel") ?: "both",
                                call.argument<Double>("freq") ?: 1000.0,
                                call.argument<Double>("seconds") ?: 2.0
                            )
                            result.success(null)
                        }
                        "toneStop" -> {
                            toneToken++
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("EQ_ERROR", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }

    // ---------------------------------------------------------------- equalizer

    private fun eqMap(e: Equalizer): Map<String, Any> {
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

    private fun start(session: Int): Map<String, Any> {
        releaseEq()
        val e = Equalizer(0, session)
        eq = e
        e.enabled = false
        return eqMap(e)
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

    private fun releaseEq() {
        try {
            eq?.release()
        } catch (ignored: Exception) {
        }
        eq = null
    }

    // ---------------------------------------------------------------- device info

    private fun deviceInfo(): Map<String, Any?> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val outs = ArrayList<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= 23) {
            for (d in am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                outs.add(mapOf("type" to d.type, "name" to (d.productName?.toString() ?: "")))
            }
        }

        val fx = ArrayList<Map<String, String>>()
        try {
            val list = AudioEffect.queryEffects()
            if (list != null) {
                for (d in list) {
                    fx.add(
                        mapOf(
                            "name" to (d.name ?: ""),
                            "implementor" to (d.implementor ?: ""),
                            "type" to d.type.toString(),
                            "uuid" to d.uuid.toString()
                        )
                    )
                }
            }
        } catch (ignored: Exception) {
        }

        // Use the running equalizer if there is one, otherwise create a throw-away one just to read its bands.
        var eqInfo: Map<String, Any>? = null
        var eqError: String? = null
        try {
            val active = eq
            if (active != null) {
                eqInfo = eqMap(active)
            } else {
                val probe = Equalizer(0, 0)
                try {
                    eqInfo = eqMap(probe)
                } finally {
                    probe.release()
                }
            }
        } catch (e: Exception) {
            eqError = e.message ?: e.javaClass.simpleName
        }

        val abis = ArrayList<String>()
        if (Build.VERSION.SDK_INT >= 21) {
            for (a in Build.SUPPORTED_ABIS) abis.add(a)
        } else {
            abis.add(Build.CPU_ABI)
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "release" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "abis" to abis,
            "sampleRate" to am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE),
            "framesPerBuffer" to am.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER),
            "outputs" to outs,
            "effects" to fx,
            "eq" to eqInfo,
            "eqError" to eqError
        )
    }

    // ---------------------------------------------------------------- bass boost / virtualizer / loudness

    private fun failure(e: Exception): Map<String, Any> =
        mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName))

    private fun fxStart(): Map<String, Any> {
        fxStop()
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

    // value: strength 0..1000 for bass/virt; gain in millibels for loud.
    private fun fxSet(name: String, on: Boolean, value: Int) {
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

    private fun fxStop() {
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

    // ---------------------------------------------------------------- test tone

    // Plays a sine on the left channel, the right channel or both, so the user can check for leakage by ear.
    private fun playTone(channel: String, freq: Double, seconds: Double) {
        val token = ++toneToken
        val rate = 44100
        val f = freq.coerceIn(50.0, 12000.0)
        val total = (rate * seconds.coerceIn(0.2, 10.0)).toInt()
        val left = channel != "right"
        val right = channel != "left"
        val minBuf = AudioTrack.getMinBufferSize(
            rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT
        )
        val track = AudioTrack(
            AudioManager.STREAM_MUSIC, rate, AudioFormat.CHANNEL_OUT_STEREO,
            AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, 8192), AudioTrack.MODE_STREAM
        )
        Thread {
            try {
                track.play()
                val chunk = 1024
                val buf = ShortArray(chunk * 2)
                val fade = rate / 50 // 20 ms fade in/out, avoids clicks
                var pos = 0
                while (pos < total && token == toneToken) {
                    val n = minOf(chunk, total - pos)
                    for (i in 0 until n) {
                        val t = pos + i
                        var env = 1.0
                        if (t < fade) env = t.toDouble() / fade
                        if (total - t < fade) env = minOf(env, (total - t).toDouble() / fade)
                        val s = (Math.sin(2.0 * Math.PI * f * t / rate) * 0.3 * env * 32767.0).toInt().toShort()
                        val silence: Short = 0
                        buf[2 * i] = if (left) s else silence
                        buf[2 * i + 1] = if (right) s else silence
                    }
                    track.write(buf, 0, n * 2)
                    pos += n
                }
                track.stop()
                Thread.sleep(150)
            } catch (ignored: Exception) {
            } finally {
                try {
                    track.release()
                } catch (ignored: Exception) {
                }
            }
        }.start()
    }
}
