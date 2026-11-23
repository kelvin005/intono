package com.example.intono

import android.Manifest
import android.content.pm.PackageManager
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
            "stop" -> { audio.stop(); result.success(null) }
            "enginePointer" -> result.success(audio.enginePointer())
            "setDrone" -> result.success(
                audio.setDrone(
                    call.argument<Boolean>("enabled") ?: false,
                    call.argument<Int>("midiNote") ?: 57,
                    (call.argument<Double>("gain") ?: 0.3).toFloat(),
                ),
            )
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
        super.onStop()
    }
}

private const val REQUEST_RECORD_AUDIO = 1
