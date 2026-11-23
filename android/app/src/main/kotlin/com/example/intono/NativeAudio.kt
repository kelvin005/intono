package com.example.intono

/**
 * The only place Kotlin touches the native shim (libintono_android.so: libintono + AudioPump + Oboe streams, ADR 0009).
 * Nothing in Kotlin is on the audio path: the Oboe callbacks run in C++ and call the engine directly.
 */
class NativeAudio {
    private var handle: Long = 0

    /** Opens the microphone stream (low latency, exclusive if granted, unprocessed preset), creates the engine at the stream's
     *  sample rate and starts capture. Returns false and sets [lastError] on failure. Needs the RECORD_AUDIO permission. */
    @Synchronized
    fun start(): Boolean {
        if (handle != 0L) return true
        handle = nativeStart()
        return handle != 0L
    }

    @Synchronized
    fun stop() {
        if (handle == 0L) return
        nativeStop(handle)
        handle = 0
    }

    val running: Boolean @Synchronized get() = handle != 0L

    /** False after the input stream was disconnected (headset change, another app took the device): restart it. */
    @Synchronized
    fun healthy(): Boolean = handle != 0L && nativeHealthy(handle)

    /** The engine pointer for dart:ffi (Phase 2 PR 3). 0 when stopped. */
    @Synchronized
    fun enginePointer(): Long = if (handle == 0L) 0 else nativeEnginePointer(handle)

    /** Opens or closes the drone output stream. Returns false if the output stream cannot be opened. */
    @Synchronized
    fun setDrone(enabled: Boolean, midiNote: Int = 57, gain: Float = 0.3f): Boolean = handle != 0L && nativeSetDrone(handle, enabled, midiNote, gain)

    /** Granted modes, sample rate, burst and buffer sizes, xruns: text, timing and settings only, never audio. */
    @Synchronized
    fun info(): String = if (handle == 0L) "stopped" else nativeInfo(handle)

    val lastError: String get() = nativeLastError()

    /** Engine create / process / destroy through the JNI layer, no audio device: proves the library, its symbols and the engine load. */
    fun smokeTest(): Boolean = nativeSmoke()

    private external fun nativeStart(): Long
    private external fun nativeStop(handle: Long)
    private external fun nativeHealthy(handle: Long): Boolean
    private external fun nativeEnginePointer(handle: Long): Long
    private external fun nativeSetDrone(handle: Long, enabled: Boolean, midiNote: Int, gain: Float): Boolean
    private external fun nativeInfo(handle: Long): String
    private external fun nativeLastError(): String
    private external fun nativeSmoke(): Boolean

    companion object {
        init {
            System.loadLibrary("intono_android")
        }
    }
}
