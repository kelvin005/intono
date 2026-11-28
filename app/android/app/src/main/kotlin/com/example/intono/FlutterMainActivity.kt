package com.example.intono

import android.Manifest
import android.content.pm.PackageManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The platform side of the Flutter app (ADR 0009 decision 3): permission, the Oboe streams and the engine's lifetime, behind the
 * method channel `intono/audio`. No audio crosses the channel; Dart reads frames from the engine itself over dart:ffi.
 */
class FlutterMainActivity : FlutterActivity() {
    private val audio = NativeAudio()
    private lateinit var monitor: HeadphoneMonitor
    private var pendingStart: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        monitor = HeadphoneMonitor(this) { }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "intono/audio").setMethodCallHandler(::onCall)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(result)
            "stop" -> { audio.stop(); keepScreenOn(false); result.success(null) }
            "startSoak" -> startSoak(call.argument<Int>("minutes") ?: 30, call.argument<Boolean>("inline") ?: false, result)
            "soakStatus" -> result.success(audio.soakStatus())
            "finishSoak" -> { val r = audio.finishSoak(); keepScreenOn(false); result.success(r) }
            "enginePointer" -> result.success(audio.enginePointer())
            "setDrone" -> result.success(
                audio.setDrone(
                    call.argument<Boolean>("enabled") ?: false,
                    call.argument<Int>("midiNote") ?: 57,
                    (call.argument<Double>("gain") ?: 0.3).toFloat(),
                ),
            )
            "replayArm" -> result.success(audio.replayArm(call.argument<Double>("seconds") ?: 60.0))
            "replayFreeze" -> { audio.replayFreeze(); result.success(null) }
            "replayPlay" -> result.success(audio.replayPlay(call.argument<Double>("from") ?: 0.0, call.argument<Double>("to") ?: 0.0))
            "replayStop" -> { audio.replayStop(); result.success(null) }
            "replayRelease" -> { audio.replayRelease(); result.success(null) }
            "replayPlaying" -> result.success(audio.replayPlaying())
            "headphones" -> result.success(monitor.connected())
            "info" -> result.success(audio.info())
            "lastError" -> result.success(audio.lastError)
            else -> result.notImplemented()
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingStart?.success(false)
            pendingStart = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
            return
        }
        result.success(audio.start())
    }

    /** The soak runs in the foreground with the screen on: the app stops capture when it is hidden, and both soak runs (worker and
     *  inline) then carry the same screen cost, so their difference is the worker's. */
    private fun startSoak(minutes: Int, inline: Boolean, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.success(false)   // the meter's Start asks for the permission; the bench does not
            return
        }
        val ok = audio.startSoak(minutes, inline)
        if (ok) keepScreenOn(true)
        result.success(ok)
    }

    private fun keepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    @Deprecated("FlutterActivity still routes permission results through this callback")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_RECORD_AUDIO) return
        val r = pendingStart ?: return
        pendingStart = null
        r.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && audio.start())
    }

    /** Never record in the background; Dart stops capture on its own lifecycle signal first, this is the backstop. */
    override fun onStop() {
        audio.stop()
        keepScreenOn(false)
        super.onStop()
    }
}

private const val REQUEST_RECORD_AUDIO = 1
