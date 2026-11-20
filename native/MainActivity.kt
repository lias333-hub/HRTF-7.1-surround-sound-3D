package com.directionalaudio.directional_audio

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Thin bridge between Flutter and [EngineHub]. All live audio effects belong to the hub (not to the
 * activity), so they keep working when the screen is closed and the activity is destroyed.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val NOTIF_REQ = 4201

        // Each new test tone gets a new token; an older tone stops when it sees the token changed.
        @Volatile
        private var toneToken = 0
    }

    private var pendingNotif: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EngineHub.init(applicationContext)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "directional/status")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    EngineHub.sink = events
                    EngineHub.emit()
                }

                override fun onCancel(arguments: Any?) {
                    EngineHub.sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "directional/eq")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // --- system equalizer
                        "start" -> result.success(EngineHub.startSystem(call.argument<Int>("session") ?: 0))
                        "setLevels" -> {
                            EngineHub.setSysLevels(call.argument<List<Int>>("levels") ?: emptyList())
                            result.success(null)
                        }
                        // --- Dynamics Processing equalizer
                        "dpProbe" -> result.success(EngineHub.probeDynamics())
                        "dpStart" -> result.success(
                            EngineHub.startDynamics(call.argument<List<Double>>("centers") ?: emptyList())
                        )
                        "dpGains" -> {
                            EngineHub.setDpGains(
                                call.argument<List<Double>>("gains") ?: emptyList(),
                                call.argument<Double>("preamp") ?: 0.0
                            )
                            result.success(null)
                        }
                        // --- shared
                        "setEnabled" -> result.success(EngineHub.setEqEnabled(call.argument<Boolean>("on") ?: false))
                        "stop" -> {
                            EngineHub.stopEq()
                            result.success(null)
                        }
                        "deviceInfo" -> result.success(deviceInfo())
                        // --- bass / virtualizer / loudness
                        "fxStart" -> result.success(EngineHub.fxStart())
                        "fxSet" -> {
                            EngineHub.fxSet(
                                call.argument<String>("name") ?: "",
                                call.argument<Boolean>("on") ?: false,
                                call.argument<Int>("value") ?: 0
                            )
                            result.success(null)
                        }
                        "fxStop" -> {
                            EngineHub.fxStop()
                            result.success(null)
                        }
                        // --- foreground service
                        "svcStart" -> {
                            startEngineService(
                                call.argument<String>("title") ?: "",
                                call.argument<String>("text") ?: "",
                                call.argument<String>("stop") ?: ""
                            )
                            result.success(null)
                        }
                        "svcStop" -> {
                            EngineHub.setWanted(false)
                            stopService(Intent(this, EngineService::class.java))
                            result.success(null)
                        }
                        "status" -> result.success(EngineHub.status())
                        // --- permissions / battery
                        "notifStatus" -> result.success(notifStatus())
                        "notifRequest" -> requestNotif(result)
                        "batteryIgnored" -> result.success(batteryIgnored())
                        "batteryRequest" -> {
                            requestBattery()
                            result.success(null)
                        }
                        // --- test tone
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

    // ---------------------------------------------------------------- service, permissions, battery

    private fun startEngineService(title: String, text: String, stop: String) {
        EngineHub.setWanted(true)
        val i = Intent(this, EngineService::class.java)
            .putExtra("title", title)
            .putExtra("text", text)
            .putExtra("stop", stop)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    }

    // "na" below Android 13 (no runtime permission), otherwise "granted" or "denied".
    private fun notifStatus(): String {
        if (Build.VERSION.SDK_INT < 33) return "na"
        return if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            "granted"
        } else {
            "denied"
        }
    }

    private fun requestNotif(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || notifStatus() == "granted") {
            result.success(notifStatus())
            return
        }
        pendingNotif?.success("denied")
        pendingNotif = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIF_REQ)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIF_REQ) {
            val r = pendingNotif
            pendingNotif = null
            r?.success(notifStatus())
        }
    }

    private fun batteryIgnored(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBattery() {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (ignored: Exception) {
            }
        }
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
            val active = EngineHub.systemEqMap()
            if (active != null) {
                eqInfo = active
            } else {
                val probe = Equalizer(0, 0)
                try {
                    eqInfo = EngineHub.eqMap(probe)
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
            "eqError" to eqError,
            "dynamics" to EngineHub.probeDynamics(),
            "notif" to notifStatus(),
            "batteryIgnored" to batteryIgnored()
        )
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
