package com.directionalaudio.directional_audio

/**
 * Bridge to the C++ core (libdacore.so). Every answer is a "key=value;key=value" string that starts with
 * ok=1 or ok=0;error=... — this object never throws, so a missing library (an ABI we did not build, a failed
 * load) shows up as a readable error in the app instead of a crash.
 *
 * The two `external` functions are registered from C++ (RegisterNatives in JNI_OnLoad, see jni/da_jni.cpp).
 */
object NativeCore {
    private var state = 0 // 0 = not tried yet, 1 = loaded, 2 = failed
    private var failure = ""

    @Synchronized
    fun load(): Boolean {
        if (state == 0) {
            try {
                System.loadLibrary("dacore")
                state = 1
            } catch (t: Throwable) {
                failure = "${t.javaClass.simpleName}: ${t.message}"
                state = 2
            }
        }
        return state == 1
    }

    fun loadError(): String = failure

    /** Same shape as every native answer, for failures that happen before or around the native call. */
    internal fun fail(msg: String): String =
        "ok=0;error=" + msg.replace(';', ',').replace('\n', ' ').replace('\r', ' ')

    fun info(): String {
        if (!load()) return fail("native library not loaded ($failure)")
        return try {
            nativeInfo()
        } catch (t: Throwable) {
            fail("${t.javaClass.simpleName}: ${t.message}")
        }
    }

    fun bench(kernel: Int, taps: Int, block: Int, rtMs: Int): String {
        if (!load()) return fail("native library not loaded ($failure)")
        return try {
            nativeBench(kernel, taps, block, rtMs)
        } catch (t: Throwable) {
            fail("${t.javaClass.simpleName}: ${t.message}")
        }
    }

    @JvmStatic
    private external fun nativeInfo(): String

    @JvmStatic
    private external fun nativeBench(kernel: Int, taps: Int, block: Int, rtMs: Int): String
}
